import Dispatch
import Foundation

public enum TerminationSignals {
    public static let all: [Int32] = [SIGINT, SIGTERM, SIGHUP]
}

/// Turns termination signals into a callback on the main actor. The default dispositions are replaced
/// (a signal kills the process before cleanup otherwise), so the handler is responsible for ending the process.
@MainActor
public final class TerminationSignalObserver {
    private var sources: [DispatchSourceSignal] = []

    public init(signals: [Int32] = TerminationSignals.all, handler: @escaping @MainActor @Sendable () -> Void) {
        sources = signals.map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { Task { @MainActor in handler() } }
            source.resume()
            return source
        }
    }

    public func cancel() {
        for source in sources { source.cancel() }
        sources = []
    }
}
