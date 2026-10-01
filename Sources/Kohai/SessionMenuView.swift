import AppKit
import KohaiCore
import SwiftUI

struct MenuBarLabel: View {
    let needsInput: Int

    var body: some View {
        if needsInput > 0 {
            Label("\(needsInput)", systemImage: "exclamationmark.bubble.fill")
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Kohai: \(needsInput) sessions need input")
        } else {
            Image(systemName: "bubble.left.and.bubble.right")
                .accessibilityLabel("Kohai: no sessions need input")
        }
    }
}

struct SessionMenuView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kohai").font(.headline)
                Spacer()
                Text("\(model.store.needsInputCount) need input")
                    .foregroundStyle(.secondary)
            }

            if let error = model.listenerError {
                Text(error).font(.caption)
            }

            if model.store.sessions.isEmpty {
                Text("No agent sessions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.store.groups) { group in
                                ProjectSection(group: group, now: context.date, home: model.home) { key in
                                    model.clear(key)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 440)
            }

            Divider()
            Button("Quit Kohai") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 400)
    }
}

private struct ProjectSection: View {
    let group: ProjectGroup
    let now: Date
    let home: String
    let onClear: (SessionKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name).font(.subheadline.weight(.semibold))
                Text(abbreviateHome(group.projectDir, home: home))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ForEach(group.sessions) { session in
                SessionRow(session: session, now: now, home: home) { onClear(session.key) }
            }
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let now: Date
    let home: String
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(session.agent.displayName)
                Text(session.accountLabel(home: home))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(session.status.label)
                    .fontWeight(session.status == .needsInput ? .bold : .regular)
                Text(formatElapsed(now.timeIntervalSince(session.statusSince)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(action: onClear) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Clear this session from the list")
            }
            .font(.callout)
            if let message = session.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 8)
    }
}
