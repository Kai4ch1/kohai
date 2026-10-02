import Foundation
import Testing
@testable import KohaiCore

@Suite("Space rules")
struct SpaceRulesTests {
    let personal = Space(name: "Personal", color: .blue, symbol: "house")
    let work = Space(name: "Work", color: .orange, symbol: "briefcase")
    let accounts = [
        AccountLabel(configDir: "/Users/me/.claude", name: "Personal", color: .blue),
        AccountLabel(configDir: "/Users/me/.claude-work", name: "Work", color: .orange),
    ]

    func settings(_ spaces: [Space]) -> KohaiSettings {
        KohaiSettings(accounts: accounts, spaces: spaces)
    }

    func with(_ space: Space, _ rules: SpaceRule...) -> Space {
        var copy = space
        copy.rules = rules
        return copy
    }

    func traits(account: String = "/Users/me/.claude", remote: String? = nil, folder: String = "/Users/me/x") -> SessionTraits {
        SessionTraits(configDir: account, gitRemote: remote, folder: folder)
    }

    @Test func accountBeatsRemoteBeatsFolderRegardlessOfSpaceOrder() {
        // Personal is first in order but only has weaker rules.
        let p = with(personal, SpaceRule(.folder, "/Users/me/dev"), SpaceRule(.gitRemote, "github.com/acme/*"))
        let w = with(work, SpaceRule(.account, "/Users/me/.claude-work"))
        let s = settings([p, w])
        let t = traits(account: "/Users/me/.claude-work", remote: "github.com/acme/api", folder: "/Users/me/dev/api")
        #expect(SpaceRules.space(for: t, in: s) == w.id)

        let w2 = with(work, SpaceRule(.gitRemote, "github.com/acme/*"))
        let p2 = with(personal, SpaceRule(.folder, "/Users/me/dev"))
        #expect(SpaceRules.space(for: traits(remote: "github.com/acme/api", folder: "/Users/me/dev/api"), in: settings([p2, w2])) == w2.id)
    }

    @Test func tiesGoToTheFirstSpaceInUserOrder() {
        let a = with(personal, SpaceRule(.gitRemote, "github.com/acme/*"))
        let b = with(work, SpaceRule(.gitRemote, "github.com/acme/api"))
        let t = traits(remote: "github.com/acme/api")
        #expect(SpaceRules.space(for: t, in: settings([a, b])) == a.id)
        #expect(SpaceRules.space(for: t, in: settings([b, a])) == b.id)
    }

    @Test func unmatchedIsUnsorted() {
        let w = with(work, SpaceRule(.gitRemote, "github.com/acme/*"), SpaceRule(.folder, "/Users/me/work"))
        #expect(SpaceRules.space(for: traits(remote: "github.com/other/api", folder: "/Users/me/x"), in: settings([w])) == nil)
        #expect(SpaceRules.space(for: traits(remote: nil), in: settings([w])) == nil)
        #expect(SpaceRules.space(for: traits(), in: settings([])) == nil)
    }

    @Test(arguments: [
        ("github.com/acme/*", "github.com/acme/api", true),
        ("github.com/acme/*", "github.com/ACME/Api", true),
        ("github.com/acme/*", "github.com/acme/group/api", false),
        ("github.com/acme/**", "github.com/acme/group/api", true),
        ("github.com/acme/*", "github.com/acmecorp/api", false),
        ("github.com/*/kohai", "github.com/kai4ch1/kohai", true),
        ("*/acme/api", "gitlab.com/acme/api", true),
        ("github.com/acme/api", "github.com/acme/api", true),
        ("github.com/acme/api", "github.com/acme/api-v2", false),
        ("git@github.com:acme/api.git", "github.com/acme/api", true),
        ("https://github.com/acme/api.git", "github.com/acme/api", true),
        ("github.com/acme/api.git", "github.com/acme/api", true),
        ("github.com/acme/", "github.com/acme/api", false),
        ("", "github.com/acme/api", false),
        ("**", "github.com/acme/api", true),
    ])
    func remoteGlobs(pattern: String, remote: String, expected: Bool) {
        #expect(SpaceRules.remoteMatches(pattern: pattern, remote: remote) == expected)
    }

    @Test(arguments: [
        ("/Users/me/work", "/Users/me/work", true),
        ("/Users/me/work", "/Users/me/work/api/src", true),
        ("/Users/me/work/", "/Users/me/work/api", true),
        ("/Users/me/work", "/Users/me/workshop", false),
        ("/Users/me/work", "/Users/me", false),
        ("relative/path", "/Users/me/relative/path", false),
        ("/", "/anything", true),
        ("/Users/me/./work/../work", "/Users/me/work/x", true),
    ])
    func folderPrefixes(prefix: String, folder: String, expected: Bool) {
        #expect(SpaceRules.folderMatches(prefix: prefix, folder: folder) == expected)
    }

    @Test func ruleOrderInsideASpaceDoesNotMatter() {
        let w1 = with(work, SpaceRule(.folder, "/Users/me/work"), SpaceRule(.account, "/Users/me/.claude-work"))
        let w2 = with(work, SpaceRule(.account, "/Users/me/.claude-work"), SpaceRule(.folder, "/Users/me/work"))
        let t = traits(account: "/Users/me/.claude-work")
        #expect(SpaceRules.space(for: t, in: settings([w1])) == work.id)
        #expect(SpaceRules.space(for: t, in: settings([w2])) == work.id)
    }

    @Test func deletedAccountRuleStopsMatching() {
        let w = with(work, SpaceRule(.account, "/Users/me/.claude-work"), SpaceRule(.folder, "/Users/me/work"))
        var s = settings([w])
        s.accounts.removeAll { $0.configDir == "/Users/me/.claude-work" }
        #expect(SpaceRules.space(for: traits(account: "/Users/me/.claude-work"), in: s) == nil)
        // Its other rules still work.
        #expect(SpaceRules.space(for: traits(account: "/Users/me/.claude-work", folder: "/Users/me/work/a"), in: s) == w.id)
    }

    @Test func deletedSpaceFallsThroughToTheNextMatch() {
        let p = with(personal, SpaceRule(.folder, "/Users/me"))
        let w = with(work, SpaceRule(.account, "/Users/me/.claude-work"))
        let t = traits(account: "/Users/me/.claude-work", folder: "/Users/me/x")
        var s = settings([w, p])
        #expect(SpaceRules.space(for: t, in: s) == w.id)
        s.spaces.removeAll { $0.id == w.id }
        #expect(SpaceRules.space(for: t, in: s) == p.id)
        s.spaces.removeAll()
        #expect(SpaceRules.space(for: t, in: s) == nil)
    }
}
