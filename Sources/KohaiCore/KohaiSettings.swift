import Foundation

/// Named colors only: the app maps them to design tokens, so settings never carry raw RGB.
public enum LabelColor: String, Codable, Sendable, CaseIterable {
    case blue, orange, green, purple, pink, red, yellow, teal, gray
}

/// User-given name and color for one agent config dir.
public struct AccountLabel: Codable, Sendable, Equatable {
    public var configDir: String
    public var name: String
    public var color: LabelColor

    public init(configDir: String, name: String, color: LabelColor) {
        self.configDir = configDir
        self.name = name
        self.color = color
    }
}

public struct SpaceRule: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// Agent config dir, exact.
        case account
        /// Normalized remote, exact or glob (`*` one segment, `**` any number).
        case gitRemote
        /// Absolute folder, matches itself and everything below it.
        case folder
    }

    public var kind: Kind
    public var value: String

    public init(_ kind: Kind, _ value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct Space: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: LabelColor
    /// SF Symbol name.
    public var symbol: String
    public var rules: [SpaceRule]

    public init(id: UUID = UUID(), name: String, color: LabelColor, symbol: String, rules: [SpaceRule] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.symbol = symbol
        self.rules = rules
    }
}

public struct NotificationSettings: Codable, Sendable, Equatable {
    /// Off until the user turns it on; that is when macOS is asked for permission.
    public var enabled: Bool
    public var mutedSpaces: Set<UUID>

    public init(enabled: Bool = false, mutedSpaces: Set<UUID> = []) {
        self.enabled = enabled
        self.mutedSpaces = mutedSpaces
    }
}

/// Everything Kohai remembers. Sessions are never persisted.
public struct KohaiSettings: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var accounts: [AccountLabel]
    /// In the user's order; order breaks ties in `SpaceRules`.
    public var spaces: [Space]
    public var notifications: NotificationSettings
    /// Config dirs added by hand on the connect screen.
    public var extraAccounts: [AgentAccount]
    /// Account ids the user left unconnected; not hinted again.
    public var declinedAccounts: [String]

    public init(
        accounts: [AccountLabel] = [],
        spaces: [Space] = [],
        notifications: NotificationSettings = NotificationSettings(),
        extraAccounts: [AgentAccount] = [],
        declinedAccounts: [String] = []
    ) {
        version = Self.currentVersion
        self.accounts = accounts
        self.spaces = spaces
        self.notifications = notifications
        self.extraAccounts = extraAccounts
        self.declinedAccounts = declinedAccounts
    }

    public func label(forConfigDir dir: String) -> AccountLabel? {
        accounts.first { $0.configDir == dir }
    }

    // Missing keys fall back to defaults so an older or hand-edited file still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        accounts = try c.decodeIfPresent([AccountLabel].self, forKey: .accounts) ?? []
        spaces = try c.decodeIfPresent([Space].self, forKey: .spaces) ?? []
        notifications = try c.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? NotificationSettings()
        extraAccounts = try c.decodeIfPresent([AgentAccount].self, forKey: .extraAccounts) ?? []
        declinedAccounts = try c.decodeIfPresent([String].self, forKey: .declinedAccounts) ?? []
    }
}

/// Why the settings on screen are not simply what was on disk.
public enum SettingsWarning: Equatable, Sendable {
    /// The file could not be read; it was kept at `backup` and defaults are in use.
    case unreadable(backup: String)
    /// Written by a newer Kohai; kept at `backup` and defaults are in use.
    case newerVersion(Int, backup: String)
}

/// `settings.json` in Application Support: versioned, atomic writes, never loses the user's file.
public final class SettingsStore: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    /// Upgrades the raw JSON of version N to N+1. Empty until the format changes; the
    /// "no version field" case (a hand-made file) is treated as version 0 → 1.
    static func migrate(_ json: [String: Any], from version: Int) -> [String: Any]? {
        switch version {
        case 0: return json
        default: return nil
        }
    }

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kohai", isDirectory: true).appendingPathComponent("settings.json")
    }

    /// Never throws: a missing file gives defaults, a broken one gives defaults plus a warning
    /// and a backup copy of exactly what was on disk.
    public func load() -> (settings: KohaiSettings, warning: SettingsWarning?) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = FileManager.default.contents(atPath: url.path) else { return (KohaiSettings(), nil) }

        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (KohaiSettings(), .unreadable(backup: backUp(data)))
        }
        var version = json["version"] as? Int ?? 0
        if version > KohaiSettings.currentVersion {
            return (KohaiSettings(), .newerVersion(version, backup: backUp(data)))
        }
        while version < KohaiSettings.currentVersion {
            guard let next = Self.migrate(json, from: version) else {
                return (KohaiSettings(), .unreadable(backup: backUp(data)))
            }
            json = next
            version += 1
            json["version"] = version
        }
        guard let migrated = try? JSONSerialization.data(withJSONObject: json),
              let settings = try? JSONDecoder().decode(KohaiSettings.self, from: migrated)
        else {
            return (KohaiSettings(), .unreadable(backup: backUp(data)))
        }
        return (settings, nil)
    }

    /// Atomic replace. Safe to call from several threads; writes are serialized.
    public func save(_ settings: KohaiSettings) throws {
        var settings = settings
        settings.version = KohaiSettings.currentVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Copies the bytes to `settings.json.bak`, or `.bak.2`, `.bak.3`… so an older backup is
    /// never overwritten. Returns the path written ("" if even that failed).
    private func backUp(_ data: Data) -> String {
        let fm = FileManager.default
        var candidate = url.appendingPathExtension("bak")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = url.appendingPathExtension("bak.\(n)")
            n += 1
        }
        do {
            try data.write(to: candidate, options: .atomic)
            return candidate.path
        } catch {
            return ""
        }
    }
}
