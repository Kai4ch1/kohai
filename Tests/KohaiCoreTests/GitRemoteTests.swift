import Foundation
import Testing
@testable import KohaiCore

/// In-memory file tree: paths ending in "/" are directories, everything else is a file.
final class MemoryFiles: FileReading, @unchecked Sendable {
    var files: [String: (text: String, modified: Date)] = [:]
    var directories: Set<String> = []

    func addDirectory(_ path: String) {
        var p = path
        while p != "/" && !p.isEmpty {
            directories.insert(p)
            p = (p as NSString).deletingLastPathComponent
        }
    }

    func write(_ path: String, _ text: String, modified: Date = Date(timeIntervalSince1970: 1)) {
        addDirectory((path as NSString).deletingLastPathComponent)
        files[path] = (text, modified)
    }

    func contents(atPath path: String) -> Data? { files[path].map { Data($0.text.utf8) } }

    func isDirectory(atPath path: String) -> Bool? {
        if directories.contains(path) { return true }
        return files[path] == nil ? nil : false
    }

    func modificationDate(atPath path: String) -> Date? { files[path]?.modified }
}

@Suite("Git remote URLs")
struct GitRemoteURLTests {
    @Test(arguments: [
        ("https://github.com/Kai4ch1/kohai.git", "github.com/Kai4ch1/kohai"),
        ("https://github.com/Kai4ch1/kohai", "github.com/Kai4ch1/kohai"),
        ("https://github.com/Kai4ch1/kohai/", "github.com/Kai4ch1/kohai"),
        ("http://gitlab.example.com:8080/group/sub/project.git", "gitlab.example.com/group/sub/project"),
        ("ssh://git@github.com/acme/api.git", "github.com/acme/api"),
        ("ssh://git@github.com:2222/acme/api.git", "github.com/acme/api"),
        ("ssh://git@[::1]:22/acme/api.git", "[::1]/acme/api"),
        ("git+ssh://git@bitbucket.org/acme/api", "bitbucket.org/acme/api"),
        ("git://git.kernel.org/pub/scm/git/git.git", "git.kernel.org/pub/scm/git/git"),
        ("git@github.com:Kai4ch1/kohai.git", "github.com/Kai4ch1/kohai"),
        ("github.com:Kai4ch1/kohai", "github.com/Kai4ch1/kohai"),
        ("git@gitlab.com:group/sub/project.git", "gitlab.com/group/sub/project"),
        ("  git@github.com:acme/api.GIT  ", "github.com/acme/api"),
    ])
    func normalizes(url: String, expected: String) {
        #expect(GitRemote.normalize(url) == expected)
    }

    @Test(arguments: [
        "", "/Users/me/repos/kohai.git", "../other", "./x:y", "file:///Users/me/kohai.git",
        "https://github.com", "https://github.com/onlyowner", "git@github.com:", "ftp://example.com/a/b",
    ])
    func rejectsLocalOrIncomplete(url: String) {
        #expect(GitRemote.normalize(url) == nil)
    }

    /// URLs with a user and password. Assembled at runtime from obviously fake parts so secret
    /// scanners (GitGuardian) don't flag the test source as a leaked Basic Auth string.
    private static func withCredentials(_ user: String, _ password: String, _ rest: String) -> String {
        "https://" + user + ":" + password + "@" + rest
    }

    @Test func credentialsAndPortAreStripped() {
        let url = Self.withCredentials("fake-user", "FAKE-PASSWORD", "GitHub.com:443/Kai4ch1/kohai.git")
        #expect(GitRemote.normalize(url) == "github.com/Kai4ch1/kohai")
    }

    @Test func secretsNeverSurvive() {
        let url = Self.withCredentials("x-access-token", "FAKE-TOKEN-FOR-TESTS", "github.com/a/b.git")
        let normalized = GitRemote.normalize(url)
        #expect(normalized == "github.com/a/b")
        #expect(normalized?.contains("FAKE") == false)
    }
}

@Suite("Git config parsing")
struct GitConfigTests {
    @Test func prefersOriginOverEarlierRemotes() {
        let config = """
            [core]
            \trepositoryformatversion = 0
            [remote "upstream"]
            \turl = https://github.com/upstream/kohai.git
            [remote "origin"]
            \turl = git@github.com:Kai4ch1/kohai.git
            \tfetch = +refs/heads/*:refs/remotes/origin/*
            """
        #expect(GitRemote.remotes(inConfig: config).map(\.name) == ["upstream", "origin"])
        #expect(GitRemote.preferredURL(inConfig: config) == "git@github.com:Kai4ch1/kohai.git")
    }

    @Test func firstRemoteWithoutOrigin() {
        let config = "[remote \"fork\"]\n url = https://github.com/me/x\n[remote \"zz\"]\n url = https://github.com/zz/x\n"
        #expect(GitRemote.preferredURL(inConfig: config) == "https://github.com/me/x")
    }

    @Test func handlesCaseCommentsQuotesAndOldSyntax() {
        let config = """
            # comment
            [Remote "origin"] ; trailing
            \tURL = "https://github.com/a/b.git" # note
            \turl = https://github.com/ignored/second
            """
        #expect(GitRemote.preferredURL(inConfig: config) == "https://github.com/a/b.git")
        #expect(GitRemote.preferredURL(inConfig: "[remote.origin]\nurl = git@h.com:o/r.git\n") == "git@h.com:o/r.git")
        // Remote names are case-sensitive: this is not "origin".
        let mixed = "[remote \"Origin\"]\nurl = https://h.com/a/b\n[remote \"other\"]\nurl = https://h.com/c/d\n"
        #expect(GitRemote.preferredURL(inConfig: mixed) == "https://h.com/a/b")
    }

    @Test(arguments: ["", "garbage\u{0}\u{1}[[[", "[remote \"origin\"]\n", "[remote]\nurl = https://h.com/a/b\n", "[core]\nbare = false\n"])
    func noRemoteInGarbageOrEmptyConfig(config: String) {
        #expect(GitRemote.preferredURL(inConfig: config) == nil)
    }
}

@Suite("Git repository lookup")
struct GitRepositoryTests {
    @Test func walksUpFromASubfolder() {
        let fs = MemoryFiles()
        fs.addDirectory("/r/.git")
        fs.write("/r/.git/config", "[remote \"origin\"]\nurl = git@github.com:acme/api.git\n")
        fs.addDirectory("/r/src/deep")
        #expect(GitRemote.remote(forFolder: "/r/src/deep", files: fs) == "github.com/acme/api")
        #expect(GitRemote.remote(forFolder: "/r", files: fs) == "github.com/acme/api")
    }

    @Test func worktreeFollowsGitdirAndCommondir() {
        let fs = MemoryFiles()
        fs.addDirectory("/main/.git/worktrees/feature")
        fs.write("/main/.git/config", "[remote \"origin\"]\nurl = https://github.com/acme/api\n")
        fs.write("/main/.git/worktrees/feature/commondir", "../..\n")
        fs.write("/wt/feature/.git", "gitdir: /main/.git/worktrees/feature\n")
        #expect(GitRemote.configPath(forFolder: "/wt/feature", files: fs) == "/main/.git/config")
        #expect(GitRemote.remote(forFolder: "/wt/feature", files: fs) == "github.com/acme/api")
    }

    @Test func submoduleRelativeGitdirHasItsOwnConfig() {
        let fs = MemoryFiles()
        fs.addDirectory("/super/.git/modules/lib")
        fs.write("/super/.git/config", "[remote \"origin\"]\nurl = https://github.com/acme/super\n")
        fs.write("/super/.git/modules/lib/config", "[remote \"origin\"]\nurl = https://github.com/acme/lib\n")
        fs.write("/super/lib/.git", "gitdir: ../.git/modules/lib")
        #expect(GitRemote.remote(forFolder: "/super/lib", files: fs) == "github.com/acme/lib")
    }

    @Test func brokenGitFilesAndMissingConfigGiveNil() {
        let fs = MemoryFiles()
        fs.write("/a/.git", "not a gitdir line")
        fs.write("/b/.git", "gitdir: /does/not/exist")
        fs.addDirectory("/c/.git") // no config file
        fs.addDirectory("/d/plain")
        for folder in ["/a", "/b", "/c", "/d/plain", "/nowhere"] {
            #expect(GitRemote.remote(forFolder: folder, files: fs) == nil, "\(folder)")
        }
    }
}

@Suite("Git remote cache")
struct GitRemoteCacheTests {
    @Test func rereadsOnlyWhenConfigChanges() {
        let fs = MemoryFiles()
        fs.addDirectory("/r/.git")
        fs.write("/r/.git/config", "[remote \"origin\"]\nurl = https://github.com/a/one\n", modified: Date(timeIntervalSince1970: 10))
        let cache = GitRemoteCache(files: fs)
        #expect(cache.remote(forFolder: "/r") == "github.com/a/one")
        #expect(cache.remote(forFolder: "/r") == "github.com/a/one")
        #expect(cache.reads == 1)

        fs.write("/r/.git/config", "[remote \"origin\"]\nurl = https://github.com/a/two\n", modified: Date(timeIntervalSince1970: 20))
        #expect(cache.remote(forFolder: "/r") == "github.com/a/two")
        #expect(cache.reads == 2)
    }

    @Test func noticesARepoAppearingAndDisappearing() {
        let fs = MemoryFiles()
        fs.addDirectory("/r")
        let cache = GitRemoteCache(files: fs)
        #expect(cache.remote(forFolder: "/r") == nil)
        fs.addDirectory("/r/.git")
        fs.write("/r/.git/config", "[remote \"origin\"]\nurl = https://github.com/a/b\n")
        #expect(cache.remote(forFolder: "/r") == "github.com/a/b")
        fs.directories.remove("/r/.git")
        fs.files["/r/.git/config"] = nil
        #expect(cache.remote(forFolder: "/r") == nil)
    }
}
