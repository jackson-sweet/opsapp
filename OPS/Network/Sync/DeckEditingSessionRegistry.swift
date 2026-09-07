import Foundation

/// Ephemeral upload exclusion, independent of durable outbox state. A crash
/// releases all holds naturally; no persisted operation can be stranded by it.
/// The lock permits both outbound executors to check immediately before claim.
final class DeckEditingSessionRegistry: @unchecked Sendable {
    static let shared = DeckEditingSessionRegistry()
    private let lock = NSLock()
    private var sessions: [UUID: String] = [:]

    func begin(designId: String) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let token = UUID()
        sessions[token] = designId.lowercased()
        return token
    }

    func end(_ token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: token)
    }

    func isHeld(entityType: String, entityId: String) -> Bool {
        guard entityType == "deckDesign" else { return false }
        lock.lock()
        defer { lock.unlock() }
        return sessions.values.contains(entityId.lowercased())
    }
}
