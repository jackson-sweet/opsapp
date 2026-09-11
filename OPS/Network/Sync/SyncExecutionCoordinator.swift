import Foundation
import UIKit

/// Task-local ownership crosses actor hops without passing a ModelContext.
/// Callers outside a managed sync pass retain their existing persistence policy.
enum SyncExecutionContext {
    @TaskLocal static var scope: SyncExecutionScope?

    static var isCurrent: Bool { (try? checkCurrent()) != nil }

    static func checkCurrent() throws {
        try Task.checkCancellation()
        try scope?.check()
    }

    static func withTransaction<T>(_ operation: () throws -> T) throws -> T {
        try Task.checkCancellation()
        guard let scope else { return try operation() }
        return try scope.withTransaction(operation)
    }
}

/// Only the permission and transaction count are shared across executors.
/// Closing a scope is immediate; drainage is reported only after every admitted
/// synchronous transaction exits. No lock is held while touching SwiftData.
final class SyncExecutionScope: @unchecked Sendable {
    private let lock = NSLock()
    private let uptime: @Sendable () -> TimeInterval
    private var closed = false
    private var activeTransactions = 0
    private var deadline: TimeInterval?
    private var cancelWork: (@Sendable () -> Void)?
    private var drainCallbacks: [@Sendable () -> Void] = []

    init(uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
    }

    var isDrained: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed && activeTransactions == 0
    }

    func check() throws {
        lock.lock(); defer { lock.unlock() }
        guard !closed, deadline.map({ uptime() < $0 }) ?? true else {
            throw CancellationError()
        }
    }

    func setDeadline(_ value: TimeInterval?) {
        lock.lock()
        deadline = value
        lock.unlock()
    }

    func onCancellation(_ callback: @escaping @Sendable () -> Void) {
        lock.lock()
        let alreadyClosed = closed
        if !alreadyClosed { cancelWork = callback }
        lock.unlock()
        if alreadyClosed { callback() }
    }

    func whenDrained(_ callback: @escaping @Sendable () -> Void) {
        lock.lock()
        let alreadyDrained = closed && activeTransactions == 0
        if !alreadyDrained { drainCallbacks.append(callback) }
        lock.unlock()
        if alreadyDrained { callback() }
    }

    func close() {
        lock.lock()
        closed = true
        let cancellation = cancelWork
        cancelWork = nil
        let callbacks = activeTransactions == 0 ? drainCallbacks : []
        if activeTransactions == 0 { drainCallbacks.removeAll() }
        lock.unlock()
        cancellation?()
        callbacks.forEach { $0() }
    }

    func waitUntilDrained() async {
        await withCheckedContinuation { continuation in
            whenDrained { continuation.resume() }
        }
    }

    func withTransaction<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        guard !closed, deadline.map({ uptime() < $0 }) ?? true else {
            lock.unlock()
            throw CancellationError()
        }
        activeTransactions += 1
        lock.unlock()
        defer { transactionFinished() }

        let result = try operation()
        // A committed chunk remains durable, but an interrupted pass must not
        // advance its pull cursors or announce successful completion.
        try check()
        return result
    }

    private func transactionFinished() {
        lock.lock()
        activeTransactions -= 1
        let callbacks = closed && activeTransactions == 0 ? drainCallbacks : []
        if closed && activeTransactions == 0 { drainCallbacks.removeAll() }
        lock.unlock()
        callbacks.forEach { $0() }
    }
}

@MainActor
protocol SyncBackgroundAllowance: AnyObject {
    var remainingTime: TimeInterval { get }
    func begin(name: String, expiration: @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
private final class UIKitSyncBackgroundAllowance: SyncBackgroundAllowance {
    var remainingTime: TimeInterval { UIApplication.shared.backgroundTimeRemaining }
    func begin(name: String, expiration: @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expiration)
    }
    func end(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

/// Ending an OS assertion and finishing a SQLite transaction are different
/// events. Normal/proactive completion ends after drainage. UIKit expiration
/// must end promptly even if SQLite is still returning; scope drainage remains
/// accurate and no caller may report completed work before it occurs.
@MainActor
private final class SyncExecutionAssertion {
    private let allowance: any SyncBackgroundAllowance
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(allowance: any SyncBackgroundAllowance) { self.allowance = allowance }

    func begin(name: String, scope: SyncExecutionScope) -> Bool {
        identifier = allowance.begin(name: name) { [self] in
            scope.close()
            end()
        }
        guard identifier != .invalid else { scope.close(); return false }
        scope.whenDrained { [self] in Task { @MainActor in end() } }
        return true
    }

    func end() {
        guard identifier != .invalid else { return }
        let ending = identifier
        identifier = .invalid
        allowance.end(ending)
    }
}

/// Ordinary sync may start in the foreground. An admitted pass can finish its
/// bounded local chunks under an allowance; background notifications close new
/// admission before a queued follow-up can start. OS-granted tasks have their
/// own explicit entry and expiration, rather than bypassing the foreground gate.
@MainActor
final class SyncExecutionCoordinator {
    struct StartupAdmission: Sendable {
        let generation: UInt64
        let scope: SyncExecutionScope?
    }
    static let shared = SyncExecutionCoordinator(
        allowance: UIKitSyncBackgroundAllowance(),
        initiallyAllowsWork: UIApplication.shared.applicationState != .background,
        observeLifecycle: true
    )

    private let allowance: any SyncBackgroundAllowance
    private let notificationCenter: NotificationCenter
    private let transactionHeadroom: TimeInterval
    private let uptime: @Sendable () -> TimeInterval
    private var ordinaryScopes: [UUID: SyncExecutionScope] = [:]
    private var deadlineTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var systemScopes: [UUID: StartupAdmission] = [:]
    private var startupWaiters: [UUID: (UInt64?, CheckedContinuation<StartupAdmission, Error>)] = [:]
    private var startupAdmissionGeneration: UInt64 = 0
    private var ordinaryAdmissionGeneration: UInt64 = 0
    private(set) var acceptsOrdinaryWork: Bool

    init(
        allowance: any SyncBackgroundAllowance,
        initiallyAllowsWork: Bool = true,
        observeLifecycle: Bool = false,
        notificationCenter: NotificationCenter = .default,
        transactionHeadroom: TimeInterval = 2,
        uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.allowance = allowance
        self.acceptsOrdinaryWork = initiallyAllowsWork
        self.notificationCenter = notificationCenter
        self.transactionHeadroom = transactionHeadroom
        self.uptime = uptime
        if observeLifecycle {
            observers.append(notificationCenter.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterBackground() }
            })
            observers.append(notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterForeground() }
            })
        }
    }

    deinit {
        deadlineTask?.cancel()
        for observer in observers { notificationCenter.removeObserver(observer) }
        for waiter in startupWaiters.values { waiter.1.resume(throwing: CancellationError()) }
    }

    func enterBackground() {
        acceptsOrdinaryWork = false
        deadlineTask?.cancel()
        let duration = max(0, allowance.remainingTime - transactionHeadroom)
        // UIKit uses a practically infinite sentinel while foregrounded.
        guard duration.isFinite, duration < 86_400 else { return }
        let deadline = uptime() + duration
        ordinaryScopes.values.forEach { $0.setDeadline(deadline) }
        if duration == 0 {
            ordinaryScopes.values.forEach { $0.close() }
            return
        }
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, !self.acceptsOrdinaryWork else { return }
            self.ordinaryScopes.values.forEach { $0.close() }
        }
    }

    func enterForeground() {
        acceptsOrdinaryWork = true
        startupAdmissionGeneration &+= 1
        ordinaryAdmissionGeneration = startupAdmissionGeneration
        deadlineTask?.cancel()
        deadlineTask = nil
        ordinaryScopes.values.forEach { $0.setDeadline(nil) }
        resumeStartupWaiters()
    }

    /// Cold background launch can prepare storage using the current BG grant.
    /// The startup worker borrows that scope; it never installs a second root
    /// cancellation owner or manufactures foreground permission.
    func waitForStartupAdmission(after generation: UInt64? = nil) async throws -> StartupAdmission {
        try Task.checkCancellation()
        if let admission = startupAdmission(after: generation) { return admission }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                startupWaiters[id] = (generation, continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.startupWaiters.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
    }

    private func startupAdmission(after generation: UInt64?) -> StartupAdmission? {
        var candidates = systemScopes.values.filter { admission in
            (try? admission.scope?.check()) != nil
        }
        if acceptsOrdinaryWork {
            candidates.append(StartupAdmission(generation: ordinaryAdmissionGeneration, scope: nil))
        }
        return candidates.filter { admission in
            generation.map({ admission.generation > $0 }) ?? true
        }.max { $0.generation < $1.generation }
    }

    private func resumeStartupWaiters() {
        let ready = startupWaiters.compactMap { id, waiter -> (UUID, CheckedContinuation<StartupAdmission, Error>, StartupAdmission)? in
            guard let admission = startupAdmission(after: waiter.0) else { return nil }
            return (id, waiter.1, admission)
        }
        for (id, continuation, admission) in ready {
            startupWaiters.removeValue(forKey: id)
            continuation.resume(returning: admission)
        }
    }

    func run<T>(name: String, operation: @escaping @MainActor () async throws -> T) async throws -> T {
        try SyncExecutionContext.checkCurrent()
        if SyncExecutionContext.scope != nil {
            let result = try await operation()
            try SyncExecutionContext.checkCurrent()
            return result
        }
        guard acceptsOrdinaryWork else { throw CancellationError() }
        let scope = SyncExecutionScope(uptime: uptime)
        let assertion = SyncExecutionAssertion(allowance: allowance)
        guard assertion.begin(name: name, scope: scope) else { throw CancellationError() }
        guard acceptsOrdinaryWork else { scope.close(); throw CancellationError() }
        let id = UUID()
        ordinaryScopes[id] = scope
        defer { ordinaryScopes.removeValue(forKey: id) }
        return try await execute(scope: scope, operation: operation)
    }

    func runSystemTask<T>(
        installExpiration: (@escaping @Sendable () -> Void) -> Void,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let scope = SyncExecutionScope(uptime: uptime)
        installExpiration { scope.close() }
        return try await runSystemTask(scope: scope, operation: operation)
    }

    func runSystemTask<T>(
        scope: SyncExecutionScope,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try scope.check()
        let id = UUID()
        startupAdmissionGeneration &+= 1
        systemScopes[id] = StartupAdmission(generation: startupAdmissionGeneration, scope: scope)
        resumeStartupWaiters()
        defer { systemScopes.removeValue(forKey: id) }
        return try await execute(scope: scope, operation: operation)
    }

    private func execute<T>(
        scope: SyncExecutionScope,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let task = Task { @MainActor in
            try await SyncExecutionContext.$scope.withValue(scope) {
                try SyncExecutionContext.checkCurrent()
                let value = try await operation()
                try SyncExecutionContext.checkCurrent()
                return value
            }
        }
        scope.onCancellation { task.cancel() }
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                scope.close()
            }
            try Task.checkCancellation()
            try scope.check()
            scope.close()
            await scope.waitUntilDrained()
            return value
        } catch {
            scope.close()
            await scope.waitUntilDrained()
            throw error
        }
    }
}
