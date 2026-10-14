import Foundation
import Network

/// Model upgrades only download on their own where data costs nothing extra.
enum UnmeteredNetwork {
    /// True on a network that is neither expensive (cellular, personal hotspot) nor in Low
    /// Data Mode.
    static func isAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let firstAnswer = FirstCall()
            monitor.pathUpdateHandler = { path in
                guard firstAnswer.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied && !path.isExpensive && !path.isConstrained)
            }
            monitor.start(queue: DispatchQueue(label: "app.blitztext.unmetered-network"))
        }
    }

    /// The path handler can fire again before `cancel()` takes effect; only the first answers.
    private final class FirstCall: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
