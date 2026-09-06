import Foundation

/// Logout must invalidate actor continuations synchronously, before main-context
/// cleanup runs. No model crosses this lock; it protects one session counter.
final class OutboundSessionLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var enabled = true

    func snapshot() -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        return enabled ? generation : nil
    }

    func isCurrent(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled && token == generation
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        enabled = false
    }

    func resume() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        enabled = true
    }
}
