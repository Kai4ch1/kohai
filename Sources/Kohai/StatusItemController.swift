import AppKit
import Observation
import SwiftUI

/// The menu bar icon. AppKit rather than `MenuBarExtra`, which cannot tell a right-click apart:
/// left-click toggles the dropdown, right-click (or ⌃-click) opens a small menu with Quit.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(model: AppModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(rootView: SessionMenuView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        updateButton()
    }

    /// Opens the dropdown, optionally straight on the Agents screen.
    func showDropdown(agents: Bool = false) {
        if agents { model.showingConnect = true }
        guard let button = item.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            popover.performClose(nil)
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showDropdown()
        }
    }

    private func showMenu() {
        let tone = CopyTone.polite
        let menu = NSMenu()
        let agents = NSMenuItem(title: Copy.footerAgents.text(tone), action: #selector(openAgents), keyEquivalent: "")
        agents.target = self
        menu.addItem(agents)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: Copy.quit.text(tone), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        // Attach only while open so a left-click keeps opening the dropdown.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openAgents() {
        showDropdown(agents: true)
    }

    /// Re-renders the icon whenever the needs-input count changes.
    private func updateButton() {
        let count = withObservationTracking {
            model.store.needsInputCount
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateButton() }
        }
        guard let button = item.button else { return }
        button.image = MenuBarImages.image(filled: count > 0)
        button.title = count > 0 ? (count > 9 ? "9+" : "\(count)") : ""
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.setAccessibilityLabel(
            count > 0 ? Copy.menuBarSome.text(.polite, ["n": "\(count)"]) : Copy.menuBarNone.text(.polite))
    }
}
