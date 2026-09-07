import Combine
import Foundation
import SwiftData

/// One process cache for passive review consumers. Main-actor work is limited
/// to scope capture and scalar publication; model enumeration belongs to the
/// current ready DataActor. The injectable reader is also used by gate tests.
@MainActor
final class ReviewSnapshotStore: ObservableObject {
    typealias Reader = @MainActor (ReviewSnapshotRequest) async throws -> ReviewSnapshot?
    typealias RequestProvider = @MainActor () -> ReviewSnapshotRequest?

    static let shared = ReviewSnapshotStore()
    @Published private(set) var snapshot: ReviewSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var isUnavailable = false

    private var requestProvider: RequestProvider = { nil }
    private var reader: Reader = { _ in nil }
    private var scope: ReviewSnapshotScope?
    private var revision: UInt64 = 0
    private var dirty = true
    private var workID: UUID?
    private var work: Task<ReviewSnapshot?, Never>?
    private var reportWork: Task<Void, Never>?
    private var reportPending = false
    private weak var dataController: DataController?
    private weak var permissions: PermissionStore?
    private var containerID: ObjectIdentifier?
    private var observers = Set<AnyCancellable>()
    private let refreshMonitor = ReviewCountRefreshMonitor()
    private var refreshObserver: AnyCancellable?
    private var expiryTimer: Timer?

    init(requestProvider: @escaping RequestProvider = { nil }, reader: @escaping Reader = { _ in nil }) {
        self.requestProvider = requestProvider
        self.reader = reader
        refreshObserver = refreshMonitor.output.sink { [weak self] _ in
            Task { @MainActor [weak self] in _ = await self?.value() }
        }
    }

    /// Called by the root and compatibility entry points. Rebinding the same
    /// controller does not discard its cache or start another database read.
    func bind(dataController: DataController, permissionStore: PermissionStore = .shared) {
        let newContainerID = dataController.modelContext.map { ObjectIdentifier($0.container) }
        guard self.dataController !== dataController || permissions !== permissionStore
            || containerID != newContainerID else { return }
        observers.removeAll()
        self.dataController = dataController
        permissions = permissionStore
        containerID = newContainerID
        requestProvider = { [weak dataController, weak permissionStore] in
            guard let dataController, let permissionStore else { return nil }
            return ReviewSnapshotRequest.capture(dataController: dataController, permissionStore: permissionStore)
        }
        reader = { [weak dataController, weak permissionStore] request in
            guard let dataController, let permissionStore else { return nil }
            @MainActor func isCurrent() -> Bool {
                ReviewSnapshotRequest.capture(dataController: dataController, permissionStore: permissionStore)?.scope == request.scope
            }
            guard isCurrent() else { return nil }
            // Explicit rollback only. A missing/cancelled actor while the flag
            // is enabled must remain unavailable, never fall back onto main.
            if !request.scope.usesDataActor {
                guard let context = dataController.modelContext else { return nil }
                let companyID = request.scope.companyID
                let tasks = try context.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate {
                    $0.companyId == companyID && $0.deletedAt == nil
                }))
                let projects = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate {
                    $0.companyId == companyID && $0.deletedAt == nil
                }))
                return ReviewSnapshotCalculator.compute(tasks: tasks, projects: projects, request: request)
            }
            guard let actor = await dataController.readyDataActor(),
                  !Task.isCancelled, dataController.dataActor === actor, isCurrent() else { return nil }
            let result = try await actor.reviewSnapshot(for: request)
            guard !Task.isCancelled, dataController.dataActor === actor, isCurrent() else { return nil }
            return result
        }
        // @Published emits before the value is installed. Read the resolved
        // user/permissions on the next actor turn, never from willSet.
        dataController.$currentUser.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.scopeDidChange() }
        }.store(in: &observers)
        dataController.$dataActor.dropFirst().sink { [weak self] _ in
            // A new startup may reuse the same container/account. Actor
            // identity retires that startup's cached and in-flight counts too.
            Task { @MainActor [weak self] in self?.scopeDidChange() }
        }.store(in: &observers)
        permissionStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.scopeDidChange() }
        }.store(in: &observers)
        dataController.$scheduledTasksDidChange.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.invalidate() }
        }.store(in: &observers)
        // Project/task inbound changes already feed scheduledTasksDidChange.
        // Company settings need their own narrow threshold invalidation.
        NotificationCenter.default.publisher(for: .inboundDataMerged)
            .filter { ($0.userInfo?[InboundChangeSignal.entityNamesKey] as? [String])?.contains("Company") == true }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scopeDidChange() }
            .store(in: &observers)
        if let context = dataController.modelContext {
            NotificationCenter.default.publisher(for: ModelContext.didSave, object: context)
                .sink { [weak self] notification in
                    let keys = [ModelContext.NotificationKey.insertedIdentifiers,
                                .updatedIdentifiers, .deletedIdentifiers]
                    let names = Set(keys.flatMap {
                        notification.userInfo?[$0.rawValue] as? [PersistentIdentifier] ?? []
                    }.map(\.entityName))
                    Task { @MainActor [weak self] in
                        if names.contains("Company") { self?.scopeDidChange() }
                    }
                }.store(in: &observers)
        }
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scopeDidChange() }
            .store(in: &observers)
        scopeDidChange()
    }

    /// Cheap render-time guard: no company/table lookup. It closes the window
    /// between a user/permission publication and its coalesced refresh callback.
    func visibleSnapshot(dataController: DataController, permissionStore: PermissionStore) -> ReviewSnapshot? {
        guard let snapshot, let context = dataController.modelContext,
              snapshot.scope.containerID == ObjectIdentifier(context.container),
              snapshot.scope.userID == dataController.currentUser?.id,
              snapshot.scope.companyID == dataController.currentUser?.companyId,
              snapshot.scope.access == ReviewSnapshotAccess(permissionStore: permissionStore),
              snapshot.scope.usesDataActor == FeatureFlags.useDataActor,
              snapshot.scope.actorID == (FeatureFlags.useDataActor ? dataController.dataActor.map { ObjectIdentifier($0) } : nil),
              snapshot.scope.calendar == Calendar.current,
              snapshot.scope.day == Calendar.current.startOfDay(for: Date()) else { return nil }
        return snapshot
    }

    /// Invalidating during a read makes that result obsolete. A burst becomes
    /// one follow-up read, never an overlapping scan or an intermediate publish.
    func invalidate() {
        revision &+= 1
        dirty = true
        refreshMonitor.signal()
    }

    func scopeDidChange() {
        let request = requestProvider()
        replaceScopeIfNeeded(request?.scope)
        if dirty { refreshMonitor.signal() }
    }

    private func replaceScopeIfNeeded(_ newScope: ReviewSnapshotScope?) {
        guard scope != newScope else { return }
        scope = newScope
        revision &+= 1
        dirty = true
        snapshot = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        isUnavailable = false
        work?.cancel()
        work = nil
        workID = nil
        isLoading = false
    }

    /// Concurrent callers join the same task. A failed/unavailable read never
    /// substitutes zero and never hands stale values to a notification caller.
    func value() async -> ReviewSnapshot? {
        let request = requestProvider()
        replaceScopeIfNeeded(request?.scope)
        guard let request else { return nil }
        if !dirty, let snapshot, request.now >= snapshot.nextEligibilityChangeAt {
            revision &+= 1
            dirty = true
        }
        if !dirty, let snapshot { return snapshot }
        if let work { return await work.value }
        let id = UUID()
        workID = id
        isLoading = true
        isUnavailable = false
        let task = Task { @MainActor [weak self] () -> ReviewSnapshot? in
            guard let self else { return nil }
            defer {
                if self.workID == id {
                    self.work = nil
                    self.workID = nil
                    self.isLoading = false
                }
            }
            while !Task.isCancelled, self.workID == id {
                guard let request = self.requestProvider() else {
                    self.replaceScopeIfNeeded(nil)
                    return nil
                }
                guard request.scope == self.scope else {
                    self.replaceScopeIfNeeded(request.scope)
                    self.refreshMonitor.signal()
                    return nil
                }
                let revision = self.revision
                do {
                    let result = try await self.reader(request)
                    guard !Task.isCancelled, self.workID == id else { return nil }
                    let currentScope = self.requestProvider()?.scope
                    guard currentScope == request.scope else {
                        self.replaceScopeIfNeeded(currentScope)
                        self.refreshMonitor.signal()
                        return nil
                    }
                    if revision != self.revision { continue }
                    guard let result, result.scope == request.scope else {
                        self.isUnavailable = true
                        return nil
                    }
                    self.dirty = false
                    self.snapshot = result
                    self.scheduleExpiry(for: result)
                    return result
                } catch {
                    guard !Task.isCancelled, self.workID == id else { return nil }
                    if revision != self.revision { continue }
                    self.isUnavailable = true
                    return nil
                }
            }
            return nil
        }
        work = task
        return await task.value
    }

    private func scheduleExpiry(for snapshot: ReviewSnapshot) {
        expiryTimer?.invalidate()
        guard dataController != nil, snapshot.nextEligibilityChangeAt != .distantFuture else { return }
        // RunLoop default mode defers refresh until a finger gesture ends.
        let timer = Timer(fire: snapshot.nextEligibilityChangeAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.invalidate() }
        }
        expiryTimer = timer
        RunLoop.main.add(timer, forMode: .default)
    }

    func isCurrent(_ snapshot: ReviewSnapshot) -> Bool {
        guard let request = requestProvider() else { return false }
        return !dirty && self.snapshot == snapshot && request.scope == snapshot.scope
            && request.now < snapshot.nextEligibilityChangeAt
    }

    /// Retain a one-shot report when its read/transport was superseded for
    /// the same account. A stable read failure gets no automatic retry, and
    /// an old account's request cannot authorize reporting for its replacement.
    private func reportWasSuperseded(
        scope requestedScope: ReviewSnapshotScope,
        revision requestedRevision: UInt64,
        snapshot: ReviewSnapshot?
    ) -> Bool {
        guard let current = requestProvider(),
              current.scope.containerID == requestedScope.containerID,
              current.scope.companyID == requestedScope.companyID,
              current.scope.userID == requestedScope.userID else { return false }
        if current.scope != requestedScope || revision != requestedRevision { return true }
        return snapshot.map { current.now >= $0.nextEligibilityChangeAt } ?? false
    }

    /// Only one three-stack report is in flight. A newer demand runs afterward,
    /// so an older network completion cannot overwrite newer counts. Check
    /// identity before every RPC as auth can change across any suspension.
    @discardableResult
    func report(syncer: ReviewStackSyncing) -> Task<Void, Never> {
        reportPending = true
        if let reportWork { return reportWork }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.reportWork = nil }
            while self.reportPending && !Task.isCancelled {
                self.reportPending = false
                guard let request = self.requestProvider() else { continue }
                self.replaceScopeIfNeeded(request.scope)
                let requestedRevision = self.revision
                let result = await self.value()
                guard let snapshot = result, self.isCurrent(snapshot) else {
                    if self.reportWasSuperseded(scope: request.scope, revision: requestedRevision, snapshot: result) {
                        self.reportPending = true
                    }
                    continue
                }
                // Demands arriving while we awaited this read are served by
                // this value; only demands during transport need another pass.
                self.reportPending = false
                let reportingRevision = self.revision
                await ReviewThresholdService.syncAll(
                    taskReviewCount: snapshot.counts.taskReviewCount,
                    paymentReviewCount: snapshot.counts.paymentReviewCount,
                    unscheduledReviewCount: snapshot.counts.unscheduledReviewCount,
                    syncer: syncer, isCurrent: { self.isCurrent(snapshot) }
                )
                if self.reportWasSuperseded(scope: snapshot.scope, revision: reportingRevision, snapshot: snapshot) {
                    self.reportPending = true
                }
            }
        }
        reportWork = task
        return task
    }
}
