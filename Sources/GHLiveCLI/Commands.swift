import Combine
import Foundation
import GHLiveCore
import GIPProtocol
import GuitarInput
import KeyMapping
import KeyboardOutput
import USBTransport

enum ExitCode {
    static let success: Int32 = 0
    static let failure: Int32 = 1
    static let usage: Int32 = 2
}

private func printLine(_ text: String) {
    print(text)
    fflush(stdout)
}

private func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// Parses the arguments and runs the command; returns the process exit code.
@MainActor
public func runCLI(arguments: [String]) async -> Int32 {
    do {
        return await execute(try parseArguments(arguments))
    } catch {
        printError("ghlive: \(error)\n\n\(usage)")
        return ExitCode.usage
    }
}

@MainActor
func execute(_ command: Command) async -> Int32 {
    switch command {
    case .version:
        printLine("ghlive \(GHLiveInfo.version)")
        return ExitCode.success
    case .help:
        printLine(usage)
        return ExitCode.success
    case .printKeymap(let preset):
        return printKeymap(preset)
    case .run(let options):
        return await run(options)
    case .sniff:
        return await sniff()
    }
}

func keymapJSON(for preset: KeymapPreset) throws -> String {
    String(decoding: try preset.keymap.jsonData(), as: UTF8.self)
}

private func printKeymap(_ preset: KeymapPreset) -> Int32 {
    do {
        printLine(try keymapJSON(for: preset))
        return ExitCode.success
    } catch {
        printError("cannot encode the \(preset.rawValue) keymap: \(error)")
        return ExitCode.failure
    }
}

@MainActor
private func run(_ options: RunOptions) async -> Int32 {
    let keymap: Keymap
    do {
        keymap = try loadKeymap(options.keymapPath)
    } catch {
        printError("\(error)")
        return ExitCode.failure
    }
    if !options.dryRun, !AccessibilityPermission.request() {
        printError(
            "Accessibility permission is missing: macOS drops the key events without it. Allow your terminal in "
                + "System Settings > Privacy & Security > Accessibility, then run ghlive again. "
                + "Use --dry-run to try it without keys."
        )
        return ExitCode.failure
    }
    let emitter: any KeyEmitter
    if options.dryRun {
        emitter = DryRunKeyEmitter(write: printLine)
    } else {
        emitter = CGEventKeyEmitter()
    }
    let log: @Sendable (String) -> Void = { text in
        if options.verbose { printLine(text) }
    }
    let latestStatus = LatestStatus()
    let eventLog = makeEventLog(
        verbose: options.verbose, failures: StderrFailureLog(latestStatus: latestStatus, write: printError),
        write: printLine)
    let driver = GuitarDriver.live(keymap: keymap, emitter: emitter, log: log, eventLog: eventLog)
    let subscription = options.verbose ? reportInput(of: driver) : nil
    let statusFollower = driver.$status.sink { latestStatus.value = $0 }
    driver.start()
    printLine("waiting for the dongle (Ctrl-C to quit)")
    await waitForTerminationSignal()
    await driver.stop()
    subscription?.cancel()
    statusFollower.cancel()
    return ExitCode.success
}

@MainActor
private func reportInput(of driver: GuitarDriver) -> AnyCancellable {
    var reporter = VerboseReporter()
    return driver.$snapshot.compactMap { $0 }.sink { snapshot in
        if let line = reporter.line(for: snapshot) { printLine(line) }
    }
}

private func loadKeymap(_ path: String?) throws -> Keymap {
    guard let path else { return try KeymapStore.standard.load() }
    return try Keymap.load(from: URL(fileURLWithPath: path))
}

@MainActor
private func sniff() async -> Int32 {
    let driver = GuitarDriver(
        monitor: DongleMonitor(),
        connector: DongleConnector(),
        sink: DiscardingSink(),
        log: printLine,
        eventLog: makeEventLog(verbose: true, failures: nil, write: printLine),
        packetObserver: { direction, packet in
            let label = direction == .received ? "rx" : "tx"
            let name = packet.knownCommand.map { "\($0)" } ?? "unknown"
            printLine("\(label) \(name) \(packet.encoded().hexString)")
        }
    )
    driver.start()
    await waitForTerminationSignal()
    await driver.stop()
    return ExitCode.success
}

/// Sniffing only watches the wire; nothing is ever pressed.
@MainActor
private final class DiscardingSink: OutputSink {
    func apply(state: GuitarState, controls: Set<Control>) {}
    func releaseAll() -> Int { 0 }
}

/// Suspends until SIGINT, SIGTERM or SIGHUP arrives. The default dispositions are replaced so the process
/// stays alive long enough to release every key.
@MainActor
private func waitForTerminationSignal() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let wait = SignalWait(continuation)
        wait.observer = TerminationSignalObserver { wait.fire() }
    }
}

/// Resumes once, however many signals arrive.
@MainActor
private final class SignalWait {
    private var continuation: CheckedContinuation<Void, Never>?
    var observer: TerminationSignalObserver?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func fire() {
        observer?.cancel()
        observer = nil
        continuation?.resume()
        continuation = nil
    }
}
