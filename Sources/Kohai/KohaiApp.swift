import AppKit
import KohaiCore
import Observation
import SwiftUI

@main
struct KohaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon is an NSStatusItem (see StatusItemController); the main window and
        // the real Settings screen come with the Milestone 2 UI.
        Settings {
            EmptyView()
        }
    }
}

/// Owns the session store and the socket listener. Events arrive on a background queue and are
/// applied on the main actor.
@MainActor
@Observable
final class AppModel {
    private(set) var store = SessionStore()
    private(set) var listenerError: String?
    /// Set when a jump was refused by macOS; the dropdown then explains how to allow it.
    var automationDenied = false
    @ObservationIgnored private var listener: SocketListener?

    let home = NSHomeDirectory()
    let connections = AgentConnections()
    /// The dropdown is on the Agents screen (footer link, hint, or the icon's right-click menu).
    var showingConnect = false
    /// Done was pressed on the connect screen: don't push it again until relaunch.
    var onboardingDismissed = false

    /// Re-reads agent accounts; accounts that live sessions report from are always included.
    func refreshConnections() {
        connections.refresh(seen: store.sessions.values.map { AgentAccount(agent: $0.agent, configDir: $0.configDir) })
    }

    /// Returns false when another Kohai already owns the socket.
    func start() -> Bool {
        let path = KohaiPaths.socketPath(environment: ProcessInfo.processInfo.environment)
        // The model lives as long as the app, so the strong capture is intended.
        let listener = SocketListener(path: path) { data in
            guard let event = try? WireCodec.decode(data) else { return }
            Task { @MainActor in self.store.apply(event) }
        }
        do {
            try listener.start()
            self.listener = listener
            listenerError = nil
            return true
        } catch SocketError.alreadyRunning {
            return false
        } catch {
            listenerError = "Cannot listen on \(path): \(error)"
            return true
        }
    }

    func stop() {
        listener?.stop()
        listener = nil
    }

    func clear(_ key: SessionKey) {
        store.clear(key, at: Date())
    }

    func jump(to key: SessionKey) {
        guard let terminal = store.sessions[key]?.terminal else { return }
        Task {
            switch await TerminalJumper.jump(to: terminal) {
            case .jumped: automationDenied = false
            case .notFound: NSSound.beep()
            case .automationDenied: automationDenied = true
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var signalSources: [DispatchSourceSignal] = []

    private var statusItem: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A regular app: Dock icon, and the Dock's right-click menu brings Quit for free.
        // Also covers running the bare executable from Xcode or `swift run`.
        NSApp.setActivationPolicy(.regular)
    }

    /// Clicking the Dock icon opens the dropdown until the main window exists.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showDropdown()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Turn termination signals into a normal quit so the socket file is removed.
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
        if !model.start() {
            NSApp.terminate(nil) // another instance is running
        }
        model.refreshConnections()
        statusItem = StatusItemController(model: model)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
