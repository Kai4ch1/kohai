import Foundation

/// The little file access GitRemote needs, so tests can use an in-memory tree.
public protocol FileReading: Sendable {
    func contents(atPath path: String) -> Data?
    /// true = directory, false = file, nil = nothing there.
    func isDirectory(atPath path: String) -> Bool?
    func modificationDate(atPath path: String) -> Date?
}

public struct LocalFiles: FileReading {
    public init() {}

    public func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    public func isDirectory(atPath path: String) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue
    }

    public func modificationDate(atPath path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

/// Git remotes from a repository's own `.git/config`. No `git` process, no network.
public enum GitRemote {
    /// "host/owner/repo" (any depth for GitLab-style groups), host lowercased, no user, password,
    /// port, scheme or ".git". nil for local paths and anything without a host.
    public static func normalize(_ url: String) -> String? {
        var rest = url.trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }

        let host: String
        if let schemeEnd = rest.range(of: "://") {
            let scheme = rest[..<schemeEnd.lowerBound].lowercased()
            guard ["https", "http", "ssh", "git", "git+ssh", "ssh+git"].contains(scheme) else { return nil }
            rest = String(rest[schemeEnd.upperBound...])
            let authorityEnd = rest.firstIndex(of: "/") ?? rest.endIndex
            var authority = String(rest[..<authorityEnd])
            rest = String(rest[authorityEnd...])
            if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
            if authority.hasPrefix("[") {
                // [::1]:22 style IPv6 literal
                guard let close = authority.firstIndex(of: "]") else { return nil }
                authority = String(authority[...close])
            } else if let colon = authority.lastIndex(of: ":") {
                authority = String(authority[..<colon])
            }
            host = authority
        } else {
            // scp-like: [user@]host:path. A colon after the first slash means a local path.
            guard let colon = rest.firstIndex(of: ":") else { return nil }
            if let slash = rest.firstIndex(of: "/"), slash < colon { return nil }
            var authority = String(rest[..<colon])
            if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
            host = authority
            rest = String(rest[rest.index(after: colon)...])
        }

        guard !host.isEmpty else { return nil }
        var path = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let last = path.last, last.lowercased().hasSuffix(".git") {
            path[path.count - 1] = String(last.dropLast(4))
        }
        path.removeAll { $0.isEmpty }
        // ssh://host/~user/repo and similar home-relative paths keep their "~user" segment.
        guard path.count >= 2 else { return nil }
        return ([host.lowercased()] + path).joined(separator: "/")
    }

    /// Remotes in file order as (name, first url). Section and key names are case-insensitive,
    /// subsection names (the remote name) are not, as in git.
    public static func remotes(inConfig text: String) -> [(name: String, url: String)] {
        var result: [(name: String, url: String)] = []
        var current: String?
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") {
                current = remoteName(fromSection: line)
                continue
            }
            guard let name = current, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "url" else { continue }
            let value = unquote(line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces))
            if !result.contains(where: { $0.name == name }) { result.append((name, value)) }
        }
        return result
    }

    /// origin when present, otherwise the first remote.
    public static func preferredURL(inConfig text: String) -> String? {
        let all = remotes(inConfig: text)
        return (all.first { $0.name == "origin" } ?? all.first)?.url
    }

    /// Path of the config file that holds the remotes for `folder`: walks up to the nearest
    /// `.git`, following a `.git` file's `gitdir:` (worktrees, submodules) and a worktree's
    /// `commondir`.
    public static func configPath(forFolder folder: String, files: FileReading) -> String? {
        var dir = (folder as NSString).standardizingPath
        while true {
            let dotGit = (dir as NSString).appendingPathComponent(".git")
            switch files.isDirectory(atPath: dotGit) {
            case true?:
                return (dotGit as NSString).appendingPathComponent("config")
            case false?:
                return configPath(fromGitFile: dotGit, files: files)
            case nil:
                break
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return nil }
            dir = parent
        }
    }

    /// Normalized preferred remote for a working folder, or nil (not a repo, no remotes, unreadable).
    public static func remote(forFolder folder: String, files: FileReading) -> String? {
        guard let path = configPath(forFolder: folder, files: files),
              let data = files.contents(atPath: path),
              let text = String(data: data, encoding: .utf8),
              let url = preferredURL(inConfig: text)
        else { return nil }
        return normalize(url)
    }

    // MARK: Helpers

    static func configPath(fromGitFile path: String, files: FileReading) -> String? {
        guard let data = files.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard line.hasPrefix("gitdir:") else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        let base = (path as NSString).deletingLastPathComponent
        let gitDir = resolve(target, relativeTo: base)
        guard files.isDirectory(atPath: gitDir) == true else { return nil }

        let commonFile = (gitDir as NSString).appendingPathComponent("commondir")
        if let data = files.contents(atPath: commonFile),
           let common = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !common.isEmpty {
            return (resolve(common, relativeTo: gitDir) as NSString).appendingPathComponent("config")
        }
        return (gitDir as NSString).appendingPathComponent("config")
    }

    static func resolve(_ path: String, relativeTo base: String) -> String {
        let joined = path.hasPrefix("/") ? path : (base as NSString).appendingPathComponent(path)
        return (joined as NSString).standardizingPath
    }

    /// `[remote "origin"]` → "origin". Any other section → nil.
    static func remoteName(fromSection line: String) -> String? {
        guard let close = line.firstIndex(of: "]") else { return nil }
        let inside = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces)
        guard let quote = inside.firstIndex(of: "\"") else {
            // Deprecated [remote.origin] form.
            let parts = inside.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "remote" else { return nil }
            return String(parts[1])
        }
        guard inside[..<quote].trimmingCharacters(in: .whitespaces).lowercased() == "remote" else { return nil }
        let name = inside[inside.index(after: quote)...]
        guard let end = name.lastIndex(of: "\"") else { return nil }
        let value = String(name[..<end])
        return value.isEmpty ? nil : value
    }

    /// Drops a trailing `#` or `;` comment that is not inside quotes.
    static func stripComment(_ line: String) -> String {
        var inQuotes = false
        var previous: Character?
        for index in line.indices {
            let c = line[index]
            if c == "\"" && previous != "\\" { inQuotes.toggle() }
            if (c == "#" || c == ";") && !inQuotes { return String(line[..<index]) }
            previous = c
        }
        return line
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}

/// Remembers each folder's remote and re-reads only when its config file's mtime changes.
/// Not thread-safe; the app uses one instance on the main actor.
public final class GitRemoteCache {
    private struct Entry {
        var configPath: String
        var modified: Date?
        var remote: String?
    }

    private let files: FileReading
    private var entries: [String: Entry] = [:]
    /// Config files actually parsed; lets tests prove the cache works.
    public private(set) var reads = 0

    public init(files: FileReading = LocalFiles()) {
        self.files = files
    }

    public func remote(forFolder folder: String) -> String? {
        // Locating the config is a handful of stats; it also notices `git init` and moved repos.
        guard let path = GitRemote.configPath(forFolder: folder, files: files) else {
            entries[folder] = nil
            return nil
        }
        let modified = files.modificationDate(atPath: path)
        if let entry = entries[folder], entry.configPath == path, entry.modified == modified, modified != nil {
            return entry.remote
        }
        reads += 1
        let remote = GitRemote.remote(forFolder: folder, files: files)
        entries[folder] = Entry(configPath: path, modified: modified, remote: remote)
        return remote
    }
}
