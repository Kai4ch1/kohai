import AppKit
import KohaiCore
import Observation
import SwiftUI

@main
struct KohaiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            SessionMenuView(model: appDelegate.model)
        } label: {
            MenuBarLabel(needsInput: appDelegate.model.store.needsInputCount)
        }
        .menuBarExtraStyle(.window)
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

    func applicationWillFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist hides the Dock icon for the bundled app; this also covers
        // running the bare executable from Xcode or `swift run`.
        NSApp.setActivationPolicy(.accessory)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
