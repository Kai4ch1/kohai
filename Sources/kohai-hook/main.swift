// kohai-hook <claude|codex>
//
// Reads one hook payload from stdin, adds terminal info and sends a normalized event to the
// Kohai app over its Unix socket. Contract with the agent: never print anything, always exit 0,
// and never run longer than the watchdog (150 ms), whatever happens.

import Foundation
import KohaiCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let watchdogMicroseconds = 150_000
let maxInputBytes = 8 << 20
let sendTimeout: TimeInterval = 0.1

// 1. Safety first: a dead peer must not kill us, and a hard deadline ends the process with 0.
signal(SIGPIPE, SIG_IGN)
signal(SIGALRM) { _ in _exit(0) }
var watchdog = itimerval()
watchdog.it_value.tv_sec = 0
watchdog.it_value.tv_usec = .init(watchdogMicroseconds)
#if canImport(Darwin)
_ = setitimer(ITIMER_REAL, &watchdog, nil)
#else
_ = alarm(1) // coarse fallback; Kohai only ships on macOS
#endif

@MainActor
func readStandardInput(limit: Int) -> Data? {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let n = read(STDIN_FILENO, &buffer, buffer.count)
        if n > 0 {
            data.append(contentsOf: buffer[0..<n])
            if data.count > limit { return nil }
        } else if n == 0 {
            return data
        } else if errno == EINTR {
            continue
        } else {
            return nil
        }
    }
}

@MainActor
func run() {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2, let agent = Agent(rawValue: arguments[1]) else { return }
    guard let input = readStandardInput(limit: maxInputBytes) else { return }

    let environment = ProcessInfo.processInfo.environment
    let terminal = TerminalProbe.info(environment: environment, tty: TerminalProbe.controllingTTY())
    let result = HookPayloadParser.parse(input, agent: agent, environment: environment, terminal: terminal, now: Date())
    guard case .event(let event) = result, let data = try? WireCodec.encode(event) else { return }

    SocketClient.send(data, to: KohaiPaths.socketPath(environment: environment), timeout: sendTimeout)
}

run()
exit(0)
