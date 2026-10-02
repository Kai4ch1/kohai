import AppKit
import KohaiCore
import Observation
import SwiftUI

@main
struct KohaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    static let mainWindowID = "main"

    var body: some Scene {
        // One main window; closing it keeps Kohai running in the menu bar and the Dock.
        // The menu bar icon itself is an NSStatusItem (see StatusItemController).
        Window(Copy.windowTitle.text(.polite), id: Self.mainWindowID) {
            MainWindowView(model: appDelegate.model)
        }
        .defaultSize(width: 1100, height: 640)

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
    let settings: SettingsModel
    let connections: AgentConnections

    init(settings: SettingsModel = SettingsModel()) {
        self.settings = settings
        connections = AgentConnections(settings: settings)
    }
    @ObservationIgnored let gitRemotes = GitRemoteCache()
    /// The session the user is looking at in a focused main window; never notified.
    var focusedSession: SessionKey?
    /// Set by the main window once it has appeared (SwiftUI's openWindow, usable from AppKit).
    @ObservationIgnored var openMainWindow: (() -> Void)?

    func traits(for session: Session) -> SessionTraits {
        SessionTraits(
            configDir: session.configDir,
            gitRemote: gitRemotes.remote(forFolder: session.projectDir),
            folder: session.projectDir)
    }

    /// nil = Unsorted.
    func spaceID(for session: Session) -> UUID? {
        SpaceRules.space(for: traits(for: session), in: settings.settings)
    }

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

    /// Clicking the Dock icon with no window open reopens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model.openMainWindow?() }
        return true
    }

    /// Closing the window must not quit: the menu bar icon keeps working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
