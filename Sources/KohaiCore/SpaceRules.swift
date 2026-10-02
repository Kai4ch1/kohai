import Foundation

/// What a session offers to space rules.
public struct SessionTraits: Sendable, Equatable {
    public var configDir: String
    /// Normalized "host/owner/repo", or nil when the folder has no usable remote.
    public var gitRemote: String?
    public var folder: String

    public init(configDir: String, gitRemote: String?, folder: String) {
        self.configDir = configDir
        self.gitRemote = gitRemote
        self.folder = folder
    }
}

/// Session → space. nil means Unsorted.
///
/// Precedence is by rule kind across all spaces: any account rule beats any git remote rule,
/// which beats any folder rule. Within one kind the first space in the user's order wins.
public enum SpaceRules {
    public static func space(for traits: SessionTraits, in settings: KohaiSettings) -> Space.ID? {
        // Account rules only count for accounts that still exist in settings; a deleted
        // account must not keep pulling sessions into a space.
        let knownAccounts = Set(settings.accounts.map(\.configDir))
        for kind in [SpaceRule.Kind.account, .gitRemote, .folder] {
            for space in settings.spaces {
                let matched = space.rules.contains { rule in
                    rule.kind == kind && matches(rule, traits, knownAccounts: knownAccounts)
                }
                if matched { return space.id }
            }
        }
        return nil
    }

    static func matches(_ rule: SpaceRule, _ traits: SessionTraits, knownAccounts: Set<String>) -> Bool {
        switch rule.kind {
        case .account:
            return rule.value == traits.configDir && knownAccounts.contains(rule.value)
        case .gitRemote:
            guard let remote = traits.gitRemote else { return false }
            return remoteMatches(pattern: rule.value, remote: remote)
        case .folder:
            return folderMatches(prefix: rule.value, folder: traits.folder)
        }
    }

    /// Case-insensitive; `*` matches within one segment, `**` across segments. A pattern written
    /// as a full URL ("git@github.com:acme/api.git") is normalized first.
    public static func remoteMatches(pattern rawPattern: String, remote: String) -> Bool {
        var pattern = rawPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return false }
        if !pattern.contains("*"), let normalized = GitRemote.normalize(pattern) {
            pattern = normalized
        }
        while pattern.hasSuffix("/") { pattern.removeLast() }
        if pattern.lowercased().hasSuffix(".git") { pattern.removeLast(4) }
        return glob(Array(pattern.lowercased()), Array(remote.lowercased()))
    }

    /// Path-component prefix: "/a/b" matches "/a/b" and "/a/b/c", not "/a/bc".
    public static func folderMatches(prefix rawPrefix: String, folder: String) -> Bool {
        let prefix = (rawPrefix as NSString).standardizingPath
        let path = (folder as NSString).standardizingPath
        guard prefix.hasPrefix("/") else { return false }
        if prefix == "/" { return true }
        return path == prefix || path.hasPrefix(prefix + "/")
    }

    private static func glob(_ p: [Character], _ s: [Character]) -> Bool {
        // Memoized recursion; patterns and remotes are short.
        var memo: [Int: Bool] = [:]
        func match(_ i: Int, _ j: Int) -> Bool {
            let key = i * (s.count + 1) + j
            if let known = memo[key] { return known }
            let result: Bool
            if i == p.count {
                result = j == s.count
            } else if p[i] == "*" {
                let double = i + 1 < p.count && p[i + 1] == "*"
                let next = double ? i + 2 : i + 1
                if match(next, j) {
                    result = true
                } else if j < s.count && (double || s[j] != "/") {
                    result = match(i, j + 1)
                } else {
                    result = false
                }
            } else {
                result = j < s.count && p[i] == s[j] && match(i + 1, j + 1)
            }
            memo[key] = result
            return result
        }
        return match(0, 0)
    }
}
