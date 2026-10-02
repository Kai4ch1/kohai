import Foundation
import KohaiCore
import Observation
import os

private let log = Logger(subsystem: "io.github.kai4ch1.kohai", category: "settings")

/// The app's live copy of `KohaiSettings`. Every change is saved at once; nothing is written
/// at launch, so a file that failed to load stays untouched (next to its .bak) until the user
/// changes something.
@MainActor
@Observable
final class SettingsModel {
    private(set) var settings: KohaiSettings
    /// Shown as a banner until dismissed.
    private(set) var warning: SettingsWarning?
    /// Last save failure, shown in the same banner.
    private(set) var saveError: String?

    @ObservationIgnored private let store: SettingsStore

    /// Keys Milestone 1 kept in UserDefaults. Moved into the settings file once, then removed.
    static let legacyExtraAccountsKey = "extraAccounts"
    static let legacyDeclinedKey = "declinedAccounts"

    init(store: SettingsStore = SettingsStore(url: SettingsStore.defaultURL), defaults: UserDefaults = .standard) {
        self.store = store
        let loaded = store.load()
        settings = loaded.settings
        warning = loaded.warning
        if let warning { log.error("settings: \(String(describing: warning), privacy: .public)") }
        migrateLegacyDefaults(defaults)
    }

    func update(_ change: (inout KohaiSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        save()
    }

    func dismissWarning() {
        warning = nil
        saveError = nil
    }

    private func save() {
        do {
            try store.save(settings)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            log.error("settings save failed: \(error, privacy: .public)")
        }
    }

    /// Merges M1's UserDefaults into the file. The old keys are removed only after a
    /// successful save, so a failed write never loses them.
    private func migrateLegacyDefaults(_ defaults: UserDefaults) {
        let extraData = defaults.data(forKey: Self.legacyExtraAccountsKey)
        let declined = defaults.stringArray(forKey: Self.legacyDeclinedKey)
        guard extraData != nil || declined != nil else { return }
        let extras = extraData.flatMap { try? JSONDecoder().decode([AgentAccount].self, from: $0) } ?? []

        var next = settings
        for account in extras where !next.extraAccounts.contains(account) {
            next.extraAccounts.append(account)
        }
        for id in declined ?? [] where !next.declinedAccounts.contains(id) {
            next.declinedAccounts.append(id)
        }
        do {
            try store.save(next)
            settings = next
            defaults.removeObject(forKey: Self.legacyExtraAccountsKey)
            defaults.removeObject(forKey: Self.legacyDeclinedKey)
            log.info("migrated \(extras.count) extra accounts and \(declined?.count ?? 0) declined ids from UserDefaults")
        } catch {
            log.error("migration save failed, keeping UserDefaults: \(error, privacy: .public)")
        }
    }
}
