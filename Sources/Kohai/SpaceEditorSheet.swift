import AppKit
import KohaiCore
import SwiftUI

/// Edits one space in settings: drafts from Core, saves back, picks folders.
struct SpaceEditorSheet: View {
    let model: AppModel
    let target: SpaceEditorTarget
    let dismiss: () -> Void

    @State private var draft: SpaceDraft

    init(model: AppModel, target: SpaceEditorTarget, dismiss: @escaping () -> Void) {
        self.model = model
        self.target = target
        self.dismiss = dismiss
        let existing: Space? = switch target {
        case .new: nil
        case .existing(let id): model.settings.settings.spaces.first { $0.id == id }
        }
        let initial: SpaceDraft
        if let existing {
            initial = SpaceDraft(existing)
        } else {
            initial = SpaceDraft(name: "", tone: .orange, symbol: "briefcase", rules: [])
        }
        _draft = State(initialValue: initial)
    }

    var body: some View {
        SpaceEditor(
            draft: $draft,
            isNew: target == .new,
            accounts: accountOptions,
            onChooseFolder: { chooseFolder($0) },
            onSave: { save() },
            onCancel: dismiss,
            onDelete: deleteAction)
        .kohaiThemed()
    }

    private var deleteAction: (() -> Void)? {
        guard case .existing = target else { return nil }
        return { delete() }
    }

    /// Every account Kohai knows: discovered, added by hand, named, or seen in a session.
    private var accountOptions: [AccountOption] {
        let settings = model.settings.settings
        var dirs = model.connections.accounts.map(\.configDir)
        for dir in settings.accounts.map(\.configDir) + model.store.sessions.values.map(\.configDir) where !dirs.contains(dir) {
            dirs.append(dir)
        }
        return dirs.map { dir in
            let label = settings.label(forConfigDir: dir)
            let path = abbreviateHome(dir, home: model.home)
            return AccountOption(id: dir, title: label.map { "\($0.name) (\(path))" } ?? path, tone: label.map { LabelTone($0.color) })
        }
    }

    private func chooseFolder(_ ruleID: RuleDraft.ID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: model.home)
        guard panel.runModal() == .OK, let url = panel.url,
              let index = draft.rules.firstIndex(where: { $0.id == ruleID })
        else { return }
        draft.rules[index].value = url.path
    }

    private func save() {
        guard draft.canSave else { return }
        let rules = draft.cleanedRules.map { SpaceRule(SpaceRule.Kind($0.kind), $0.value.trimmingCharacters(in: .whitespaces)) }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        model.settings.update { s in
            // An account rule needs the account in settings, or SpaceRules ignores it.
            for rule in rules where rule.kind == .account && s.label(forConfigDir: rule.value) == nil {
                let fallback = (rule.value as NSString).lastPathComponent
                s.accounts.append(AccountLabel(configDir: rule.value, name: fallback, color: .gray))
            }
            switch target {
            case .new:
                s.spaces.append(Space(name: name, color: LabelColor(draft.tone), symbol: draft.symbol, rules: rules))
            case .existing(let id):
                guard let index = s.spaces.firstIndex(where: { $0.id == id }) else { return }
                s.spaces[index].name = name
                s.spaces[index].color = LabelColor(draft.tone)
                s.spaces[index].symbol = draft.symbol
                s.spaces[index].rules = rules
            }
        }
        dismiss()
    }

    private func delete() {
        guard case .existing(let id) = target else { return }
        model.settings.update { s in
            s.spaces.removeAll { $0.id == id }
            s.notifications.mutedSpaces.remove(id)
        }
        dismiss()
    }
}

extension SpaceDraft {
    init(_ space: Space) {
        self.init(
            name: space.name,
            tone: LabelTone(space.color),
            symbol: space.symbol,
            rules: space.rules.map { RuleDraft(kind: RuleKind($0.kind), value: $0.value) })
    }
}

extension RuleKind {
    init(_ kind: SpaceRule.Kind) {
        switch kind {
        case .account: self = .account
        case .gitRemote: self = .remote
        case .folder: self = .folder
        }
    }
}

extension SpaceRule.Kind {
    init(_ kind: RuleKind) {
        switch kind {
        case .account: self = .account
        case .remote: self = .gitRemote
        case .folder: self = .folder
        }
    }
}
