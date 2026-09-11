import Foundation

/// A queued sync is an owned request, not a fire-and-forget continuation of the
/// previous pass. Background/cancel boundaries preserve one retry; account
/// replacement explicitly clears it. Identity prevents an old completion from
/// clearing a newer scheduled pass.
@MainActor
final class SyncFollowUpRequest {
    private(set) var isPending = false
    private var task: Task<Void, Never>?
    private var taskID: UUID?

    func request() { isPending = true }
    func consumePending() { isPending = false }

    func scheduleIfAdmitted(
        canStart: @escaping @MainActor () -> Bool,
        operation: @escaping @MainActor () async -> Bool
    ) {
        guard isPending, task == nil, !Task.isCancelled, canStart() else { return }
        let id = UUID()
        taskID = id
        task = Task { @MainActor [weak self] in
            // An expired parent scope must not poison the new pass. Admission
            // is rechecked below; operation acquires a fresh allowance itself.
            await SyncExecutionContext.$scope.withValue(nil) {
                guard let self else { return }
                defer {
                    if self.taskID == id { self.task = nil; self.taskID = nil }
                }
                while self.taskID == id, self.isPending, !Task.isCancelled, canStart() {
                    self.isPending = false
                    let completed = await operation()
                    guard self.taskID == id else { return }
                    if !completed {
                        self.isPending = true
                        break // A denied allowance must not create a busy retry loop.
                    }
                }
            }
        }
    }

    func cancel(preservingRequest: Bool) {
        if preservingRequest { isPending = isPending || task != nil }
        else { isPending = false }
        task?.cancel()
        task = nil
        taskID = nil
    }

    func waitForScheduledWork() async { await task?.value }
}
