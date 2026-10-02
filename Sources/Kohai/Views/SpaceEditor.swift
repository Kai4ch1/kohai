import SwiftUI

// PRESENTATION-ONLY space editor. The app turns a draft into a Core `Space`.

enum RuleKind: String, CaseIterable, Hashable, Sendable {
    case account, remote, folder
}

struct RuleDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: RuleKind
    /// Config dir, remote pattern or absolute folder.
    var value: String

    init(id: UUID = UUID(), kind: RuleKind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

struct SpaceDraft: Hashable, Sendable {
    var name: String
    var tone: LabelTone
    var symbol: String
    var rules: [RuleDraft]

    /// Rules the user left empty are dropped on save.
    var cleanedRules: [RuleDraft] {
        rules.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
}

struct AccountOption: Identifiable, Hashable, Sendable {
    /// Config dir.
    let id: String
    let title: String
    let tone: LabelTone?
}

struct SpaceEditor: View {
    @Binding var draft: SpaceDraft
    let isNew: Bool
    let accounts: [AccountOption]
    var onChooseFolder: (RuleDraft.ID) -> Void = { _ in }
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
    /// nil for a new space.
    var onDelete: (() -> Void)? = nil

    static let symbols = [
        "briefcase", "house", "building.2", "hammer", "flask", "graduationcap", "heart", "star",
        "bolt", "leaf", "gamecontroller", "paintbrush", "book", "globe", "person.2", "cpu",
    ]

    @Environment(\.kohaiPalette) private var palette
    @Environment(\.kohaiCopyTone) private var tone

    var body: some View {
        VStack(alignment: .leading, spacing: KohaiSpacing.lg) {
            HStack(spacing: KohaiSpacing.md) {
                Image(systemName: draft.symbol)
                    .font(KohaiType.symbol(size: 20))
                    .foregroundStyle(palette.label(draft.tone).color)
                Text(isNew ? Copy.editorNewTitle.text(tone) : Copy.editorEditTitle.text(tone))
                    .font(KohaiType.headerTitle)
                    .foregroundStyle(palette.text.primary.color)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: KohaiSpacing.md, verticalSpacing: KohaiSpacing.md) {
                GridRow {
                    label(Copy.editorName.text(tone))
                    TextField(Copy.editorNamePlaceholder.text(tone), text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    label(Copy.editorColor.text(tone))
                    HStack(spacing: KohaiSpacing.sm) {
                        ForEach(LabelTone.allCases, id: \.self) { swatch($0) }
                    }
                }
                GridRow(alignment: .top) {
                    label(Copy.editorSymbol.text(tone))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: KohaiSpacing.xs), count: 8),
                              alignment: .leading, spacing: KohaiSpacing.xs) {
                        ForEach(Self.symbols, id: \.self) { symbolButton($0) }
                    }
                }
            }

            KohaiSeparator()

            VStack(alignment: .leading, spacing: KohaiSpacing.sm) {
                Text(Copy.editorRules.text(tone))
                    .font(KohaiType.rowTitle)
                    .foregroundStyle(palette.text.primary.color)
                Text(Copy.editorRulesHelp.text(tone))
                    .font(KohaiType.secondary)
                    .foregroundStyle(palette.text.secondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if draft.rules.isEmpty {
                    Text(Copy.editorNoRules.text(tone))
                        .font(KohaiType.secondary)
                        .foregroundStyle(palette.text.tertiary.color)
                }
                ForEach($draft.rules) { $rule in
                    ruleRow($rule)
                }
                LinkButton(title: Copy.ruleAdd.text(tone)) {
                    draft.rules.append(RuleDraft(kind: .remote, value: ""))
                }
            }

            KohaiSeparator()

            HStack(spacing: KohaiSpacing.md) {
                if let onDelete {
                    LinkButton(title: Copy.editorDelete.text(tone), action: onDelete)
                        .help(Copy.editorDeleteHelp.text(tone))
                }
                Spacer()
                Button(Copy.editorCancel.text(tone), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(Copy.editorSave.text(tone), action: onSave)
                    .buttonStyle(.bordered)
                    .tint(palette.surface.buttonFill.color)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave)
            }
        }
        .padding(KohaiSpacing.xl)
        .frame(width: 560)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(KohaiType.secondary)
            .foregroundStyle(palette.text.tertiary.color)
            .gridColumnAlignment(.trailing)
    }

    private func swatch(_ labelTone: LabelTone) -> some View {
        let selected = draft.tone == labelTone
        return Button { draft.tone = labelTone } label: {
            Circle()
                .fill(palette.label(labelTone).color)
                .frame(width: KohaiMetrics.swatch, height: KohaiMetrics.swatch)
                .overlay {
                    if selected {
                        Circle()
                            .strokeBorder(palette.text.primary.color, lineWidth: 2)
                            .padding(-KohaiSpacing.xxs - 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(labelTone.rawValue)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    private func symbolButton(_ symbol: String) -> some View {
        let selected = draft.symbol == symbol
        return Button { draft.symbol = symbol } label: {
            Image(systemName: symbol)
                .font(KohaiType.symbol(size: 14))
                .foregroundStyle((selected ? palette.label(draft.tone) : palette.text.secondary).color)
                .frame(width: 28, height: 28)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: KohaiSpacing.xs, style: .continuous)
                            .fill(palette.surface.rowHighlight.color)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    private func ruleRow(_ rule: Binding<RuleDraft>) -> some View {
        HStack(spacing: KohaiSpacing.sm) {
            Picker("", selection: rule.kind) {
                Text(Copy.ruleAccount.text(tone)).tag(RuleKind.account)
                Text(Copy.ruleRemote.text(tone)).tag(RuleKind.remote)
                Text(Copy.ruleFolder.text(tone)).tag(RuleKind.folder)
            }
            .labelsHidden()
            .frame(width: 120)
            .onChange(of: rule.wrappedValue.kind) { rule.wrappedValue.value = "" }

            switch rule.wrappedValue.kind {
            case .account:
                Picker("", selection: rule.value) {
                    Text("—").tag("")
                    ForEach(accounts) { Text($0.title).tag($0.id) }
                }
                .labelsHidden()
            case .remote:
                TextField(Copy.ruleRemotePlaceholder.text(tone), text: rule.value)
                    .textFieldStyle(.roundedBorder)
                    .font(KohaiType.monoPath)
            case .folder:
                Text(rule.wrappedValue.value.isEmpty ? "—" : rule.wrappedValue.value)
                    .font(KohaiType.monoPath)
                    .foregroundStyle(palette.text.secondary.color)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LinkButton(title: Copy.ruleChooseFolder.text(tone)) { onChooseFolder(rule.wrappedValue.id) }
            }

            Button {
                draft.rules.removeAll { $0.id == rule.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(palette.text.secondary.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.ruleRemove.text(tone))
        }
    }
}
