//
//  CalendarMirrorService.swift
//  OPS
//
//  One-way mirror from OPS schedule rows to a dedicated "OPS" calendar in
//  the user's iPhone Calendar. iOS 17+ EventKit, full access permission,
//  reconcile-and-revert drift handling.
//

import Foundation
import EventKit
import SwiftData
import Combine
import UIKit
import BackgroundTasks

@MainActor
final class CalendarMirrorService: ObservableObject {
    static let shared = CalendarMirrorService()

    // MARK: - State

    @Published private(set) var isEnabled: Bool
    @Published private(set) var authorizationStatus: EKAuthorizationStatus

    private let store: EKEventStore
    private let siteVisitLeadResolver = CalendarSiteVisitLeadResolver()
    private var cancellables = Set<AnyCancellable>()

    private let enabledKey = "ops.calendar.mirror.enabled"
    private let calendarIdKey = "ops.calendar.mirror.calendarId"
    private let hasShownPromptKey = "ops.calendar.mirror.hasShownPrompt"

    static let backgroundTaskId = "com.ops.calendar.mirror.refresh"

    // MARK: - Init

    private init() {
        self.store = EKEventStore()
        self.isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        subscribeToEventStoreChanges()
        subscribeToBecomeActive()
    }

    // MARK: - Public surface

    var hasShownPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: hasShownPromptKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasShownPromptKey) }
    }

    private var currentUserId: String? {
        let id = UserDefaults.standard.string(forKey: "currentUserId")
        return (id?.isEmpty == false) ? id : nil
    }

    func requestAccessIfNeeded() async -> Bool {
        let current = EKEventStore.authorizationStatus(for: .event)
        self.authorizationStatus = current
        if current == .fullAccess { return true }
        if current == .denied || current == .restricted { return false }
        do {
            let granted = try await store.requestFullAccessToEvents()
            self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return false
        }
    }

    func enable() async throws {
        let granted = await requestAccessIfNeeded()
        guard granted else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            self.isEnabled = false
            return
        }
        _ = try ensureCalendar()
        UserDefaults.standard.set(true, forKey: enabledKey)
        self.isEnabled = true
        await reconcileAll()
        scheduleNextRefresh()
    }

    func disable() async {
        deleteCalendarIfPresent()
        UserDefaults.standard.set(false, forKey: enabledKey)
        self.isEnabled = false
        clearAllMapRows()
    }

    /// Mirror or refresh the EKEvent for an OPS row. No-op when disabled or
    /// when the row is no longer eligible.
    func mirrorEvent(opsId: String, source: MirrorSource) async {
        await mirrorEvent(
            opsId: opsId,
            source: source,
            prefetchedSiteVisitDetails: nil
        )
    }

    private func mirrorEvent(
        opsId: String,
        source: MirrorSource,
        prefetchedSiteVisitDetails: [String: CalendarSiteVisitLeadDetails]?
    ) async {
        guard isEnabled, authorizationStatus == .fullAccess else { return }
        guard let context = ModelContainerHolder.mainContext else { return }
        guard let currentUserId else { return }

        let calendar: EKCalendar
        do { calendar = try ensureCalendar() } catch { return }

        if !sourceIsEligible(opsId: opsId, source: source, currentUserId: currentUserId, context: context) {
            await unmirrorEvent(opsId: opsId)
            return
        }

        guard let payload = await buildPayload(
            opsId: opsId,
            source: source,
            currentUserId: currentUserId,
            prefetchedSiteVisitDetails: prefetchedSiteVisitDetails,
            context: context
        ) else {
            await unmirrorEvent(opsId: opsId)
            return
        }

        let descriptor = FetchDescriptor<CalendarMirrorMap>(predicate: #Predicate { $0.opsId == opsId })
        let existing = try? context.fetch(descriptor).first

        if let row = existing, let ek = store.event(withIdentifier: row.ekEventIdentifier) {
            if CalendarMirrorEventMapping.needsUpdate(payload: payload, event: ek, contentHash: row.contentHash) {
                apply(payload: payload, to: ek, calendar: calendar)
                try? store.save(ek, span: .thisEvent, commit: true)
                row.contentHash = payload.canonicalHash
                row.lastMirroredAt = Date()
                try? context.save()
            }
        } else {
            // existing row but EKEvent vanished → treat as missing-map → recreate
            if let row = existing {
                context.delete(row)
                try? context.save()
            }
            let ek = EKEvent(eventStore: store)
            apply(payload: payload, to: ek, calendar: calendar)
            do {
                try store.save(ek, span: .thisEvent, commit: true)
                let row = CalendarMirrorMap(
                    opsId: payload.opsId,
                    ekEventIdentifier: ek.eventIdentifier,
                    sourceType: source,
                    contentHash: payload.canonicalHash
                )
                context.insert(row)
                try? context.save()
            } catch {
                // Swallow; reconcile retries on next pass.
            }
        }
    }

    /// Remove the EKEvent + map row for an OPS row (soft-delete / no-longer-eligible).
    func unmirrorEvent(opsId: String) async {
        guard let context = ModelContainerHolder.mainContext else { return }
        let descriptor = FetchDescriptor<CalendarMirrorMap>(predicate: #Predicate { $0.opsId == opsId })
        guard let row = try? context.fetch(descriptor).first else { return }
        if let ek = store.event(withIdentifier: row.ekEventIdentifier) {
            try? store.remove(ek, span: .thisEvent, commit: true)
        }
        context.delete(row)
        try? context.save()
    }

    /// Full sync. Runs on foreground, .EKEventStoreChanged (debounced), and
    /// opportunistic BGAppRefreshTask.
    func reconcileAll() async {
        guard isEnabled, authorizationStatus == .fullAccess else { return }
        guard let context = ModelContainerHolder.mainContext else { return }
        guard let currentUserId else { return }

        let calendar: EKCalendar
        do { calendar = try ensureCalendar() } catch { return }

        let (lower, upper) = CalendarMirrorEligibility.windowBounds()

        // Opportunities are intentionally REST-backed instead of SwiftData
        // models. Resolve every eligible appointment in one request per
        // company, then reuse the result through drift repair and backfill.
        let visitDescriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate { $0.bookedAt != nil && $0.deletedAt == nil }
        )
        let visits = (try? context.fetch(visitDescriptor)) ?? []
        let eligibleVisits = visits.filter {
            CalendarMirrorEligibility.isEligible(visit: $0, currentUserId: currentUserId)
        }
        let siteVisitDetails = await resolveSiteVisitLeadDetails(
            for: eligibleVisits,
            currentUserId: currentUserId
        )

        // 1. Iterate map rows; revert drift, remove stale.
        let allMap = (try? context.fetch(FetchDescriptor<CalendarMirrorMap>())) ?? []
        var liveOpsIds = Set<String>()

        for row in allMap {
            guard let source = row.source else {
                context.delete(row); continue
            }
            let stillEligible = sourceIsEligible(opsId: row.opsId, source: source, currentUserId: currentUserId, context: context)
            let ek = store.event(withIdentifier: row.ekEventIdentifier)

            if !stillEligible {
                if let ek { try? store.remove(ek, span: .thisEvent, commit: true) }
                context.delete(row)
                continue
            }

            guard let payload = await buildPayload(
                opsId: row.opsId,
                source: source,
                currentUserId: currentUserId,
                prefetchedSiteVisitDetails: siteVisitDetails,
                context: context
            ) else {
                if let ek { try? store.remove(ek, span: .thisEvent, commit: true) }
                context.delete(row)
                continue
            }

            if let ek {
                if CalendarMirrorEventMapping.needsUpdate(payload: payload, event: ek, contentHash: row.contentHash) {
                    apply(payload: payload, to: ek, calendar: calendar)
                    try? store.save(ek, span: .thisEvent, commit: true)
                    row.contentHash = payload.canonicalHash
                    row.lastMirroredAt = Date()
                }
            } else {
                let new = EKEvent(eventStore: store)
                apply(payload: payload, to: new, calendar: calendar)
                do {
                    try store.save(new, span: .thisEvent, commit: true)
                    row.ekEventIdentifier = new.eventIdentifier
                    row.contentHash = payload.canonicalHash
                    row.lastMirroredAt = Date()
                } catch {
                    context.delete(row)
                    continue
                }
            }
            liveOpsIds.insert(row.opsId)
        }

        // 2. Backfill: any eligible source row with no map entry.
        let userEvents = (try? context.fetch(FetchDescriptor<CalendarUserEvent>())) ?? []
        for e in userEvents where CalendarMirrorEligibility.isEligible(event: e, currentUserId: currentUserId) {
            if liveOpsIds.contains(e.id) { continue }
            await mirrorEvent(
                opsId: e.id,
                source: .calendarUserEvent,
                prefetchedSiteVisitDetails: siteVisitDetails
            )
        }
        let tasks = (try? context.fetch(FetchDescriptor<ProjectTask>())) ?? []
        for t in tasks where CalendarMirrorEligibility.isEligible(task: t, currentUserId: currentUserId) {
            if liveOpsIds.contains(t.id) { continue }
            await mirrorEvent(
                opsId: t.id,
                source: .projectTask,
                prefetchedSiteVisitDetails: siteVisitDetails
            )
        }
        for v in eligibleVisits {
            if liveOpsIds.contains(v.id) { continue }
            await mirrorEvent(
                opsId: v.id,
                source: .siteVisit,
                prefetchedSiteVisitDetails: siteVisitDetails
            )
        }

        // 3. Orphan sweep — events in OPS calendar with no map entry.
        let predicate = store.predicateForEvents(withStart: lower, end: upper, calendars: [calendar])
        let events = store.events(matching: predicate)
        let knownIds = Set(((try? context.fetch(FetchDescriptor<CalendarMirrorMap>())) ?? []).map { $0.ekEventIdentifier })
        for ek in events where !knownIds.contains(ek.eventIdentifier) {
            // Try to recover via url; otherwise delete.
            if let url = ek.url, url.scheme == "ops", url.host == "event" {
                let pathTrim = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
                let id = pathTrim
                let desc = FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == id })
                if (try? context.fetch(desc).first) != nil {
                    let row = CalendarMirrorMap(
                        opsId: id,
                        ekEventIdentifier: ek.eventIdentifier,
                        sourceType: .calendarUserEvent,
                        contentHash: ""  // forces next reconcile to refresh
                    )
                    context.insert(row)
                    continue
                }
            }
            try? store.remove(ek, span: .thisEvent, commit: true)
        }

        try? context.save()
    }

    func handleLogout() async {
        await disable()
        UserDefaults.standard.removeObject(forKey: hasShownPromptKey)
    }

    func handleCompanySwitch() async {
        await handleLogout()
    }

    // MARK: - Background refresh

    func scheduleNextRefresh() {
        guard isEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    // MARK: - Calendar lifecycle

    /// Returns the OPS calendar. Creates it if missing.
    @discardableResult
    func ensureCalendar() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: calendarIdKey),
           let cal = store.calendar(withIdentifier: id) {
            return cal
        }
        let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .exchange })
            ?? store.sources.first(where: { $0.sourceType == .local })
        guard let source else { throw CalendarMirrorError.noUsableSource }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "OPS"
        cal.source = source
        cal.cgColor = UIColor(OPSStyle.Colors.opsAccent).cgColor
        try store.saveCalendar(cal, commit: true)
        UserDefaults.standard.set(cal.calendarIdentifier, forKey: calendarIdKey)
        return cal
    }

    private func deleteCalendarIfPresent() {
        if let id = UserDefaults.standard.string(forKey: calendarIdKey),
           let cal = store.calendar(withIdentifier: id) {
            try? store.removeCalendar(cal, commit: true)
        }
        UserDefaults.standard.removeObject(forKey: calendarIdKey)
    }

    private func clearAllMapRows() {
        guard let context = ModelContainerHolder.mainContext else { return }
        let descriptor = FetchDescriptor<CalendarMirrorMap>()
        if let rows = try? context.fetch(descriptor) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    // MARK: - Helpers

    private func apply(payload: MirroredEventPayload, to ek: EKEvent, calendar: EKCalendar) {
        ek.calendar = calendar
        CalendarMirrorEventMapping.apply(payload: payload, to: ek)
    }

    private func buildPayload(
        opsId: String,
        source: MirrorSource,
        currentUserId: String,
        prefetchedSiteVisitDetails: [String: CalendarSiteVisitLeadDetails]?,
        context: ModelContext
    ) async -> MirroredEventPayload? {
        switch source {
        case .calendarUserEvent:
            let descriptor = FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == opsId })
            guard let event = try? context.fetch(descriptor).first else { return nil }
            return CalendarMirrorContent.payload(for: event)
        case .projectTask:
            let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == opsId })
            guard let task = try? context.fetch(descriptor).first else { return nil }
            let projectDisplay = projectDisplayLabel(for: task)
            let taskTypeDisplay = task.taskType?.display ?? "Task"
            let address = task.project?.address
            return CalendarMirrorContent.payload(
                for: task,
                projectDisplayName: projectDisplay,
                taskTypeDisplay: taskTypeDisplay,
                address: address
            )
        case .siteVisit:
            let descriptor = FetchDescriptor<SiteVisit>(predicate: #Predicate { $0.id == opsId })
            guard let visit = try? context.fetch(descriptor).first else { return nil }
            let leadDetails: CalendarSiteVisitLeadDetails?
            if let prefetchedSiteVisitDetails {
                leadDetails = prefetchedSiteVisitDetails[siteVisitLeadKey(for: visit)]
            } else if let opportunityId = visit.opportunityId {
                // Visit-keyed brief: an assignee holds no opportunities grant,
                // and an opportunities read would authoritatively wipe the
                // brief-derived names Schedule cached for them.
                let resolved = await siteVisitLeadResolver.refreshBriefs(
                    visits: [CalendarSiteVisitBriefRequest(siteVisitId: visit.id, opportunityId: opportunityId)],
                    userId: currentUserId,
                    companyId: visit.companyId
                )
                leadDetails = resolved.detailsByOpportunityId[canonicalIdentifier(opportunityId)]
            } else {
                leadDetails = nil
            }
            let presentation = CalendarSiteVisitPresentation(
                visit: visit,
                leadDetails: leadDetails
            )
            return CalendarMirrorContent.payload(
                for: visit,
                presentation: presentation
            )
        }
    }

    private func sourceIsEligible(opsId: String, source: MirrorSource, currentUserId: String, context: ModelContext) -> Bool {
        switch source {
        case .calendarUserEvent:
            let descriptor = FetchDescriptor<CalendarUserEvent>(predicate: #Predicate { $0.id == opsId })
            guard let event = try? context.fetch(descriptor).first else { return false }
            return CalendarMirrorEligibility.isEligible(event: event, currentUserId: currentUserId)
        case .projectTask:
            let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == opsId })
            guard let task = try? context.fetch(descriptor).first else { return false }
            return CalendarMirrorEligibility.isEligible(task: task, currentUserId: currentUserId)
        case .siteVisit:
            let descriptor = FetchDescriptor<SiteVisit>(predicate: #Predicate { $0.id == opsId })
            guard let visit = try? context.fetch(descriptor).first else { return false }
            return CalendarMirrorEligibility.isEligible(visit: visit, currentUserId: currentUserId)
        }
    }

    private func resolveSiteVisitLeadDetails(
        for visits: [SiteVisit],
        currentUserId: String
    ) async -> [String: CalendarSiteVisitLeadDetails] {
        let visitsByCompany = Dictionary(grouping: visits) {
            canonicalIdentifier($0.companyId)
        }
        var resolvedByVisitKey: [String: CalendarSiteVisitLeadDetails] = [:]

        for companyId in visitsByCompany.keys.sorted() where !companyId.isEmpty {
            let companyVisits = visitsByCompany[companyId] ?? []
            let leadLinkedVisits = companyVisits.filter {
                !($0.opportunityId.map(canonicalIdentifier) ?? "").isEmpty
            }
            guard !leadLinkedVisits.isEmpty else { continue }

            let companyDetails = await siteVisitLeadResolver.refreshBriefs(
                visits: leadLinkedVisits.map {
                    CalendarSiteVisitBriefRequest(siteVisitId: $0.id, opportunityId: $0.opportunityId)
                },
                userId: currentUserId,
                companyId: companyId
            ).detailsByOpportunityId
            for (opportunityId, details) in companyDetails {
                resolvedByVisitKey[siteVisitLeadKey(
                    opportunityId: opportunityId,
                    companyId: companyId
                )] = details
            }
        }

        return resolvedByVisitKey
    }

    private func siteVisitLeadKey(for visit: SiteVisit) -> String {
        siteVisitLeadKey(
            opportunityId: visit.opportunityId ?? "",
            companyId: visit.companyId
        )
    }

    private func siteVisitLeadKey(opportunityId: String, companyId: String) -> String {
        "\(canonicalIdentifier(companyId))|\(canonicalIdentifier(opportunityId))"
    }

    private func canonicalIdentifier(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func projectDisplayLabel(for task: ProjectTask) -> String {
        if let p = task.project, !p.title.isEmpty {
            return p.title
        }
        return "Project"
    }

    // MARK: - Subscriptions

    private func subscribeToEventStoreChanges() {
        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.reconcileAll()
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToBecomeActive() {
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAuthorizationStatus()
                    if self?.isEnabled == true, self?.authorizationStatus == .fullAccess {
                        await self?.reconcileAll()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func refreshAuthorizationStatus() {
        let s = EKEventStore.authorizationStatus(for: .event)
        self.authorizationStatus = s
        if s != .fullAccess, isEnabled {
            UserDefaults.standard.set(false, forKey: enabledKey)
            self.isEnabled = false
        }
    }
}

/// The in-memory EventKit boundary shared by immediate writes and reconciliation.
/// It never requests access or saves an event; the service owns those effects.
@MainActor
enum CalendarMirrorEventMapping {
    static func apply(payload: MirroredEventPayload, to event: EKEvent) {
        event.title = payload.title
        event.notes = payload.body
        event.location = payload.location
        event.url = payload.url
        event.isAllDay = payload.isAllDay
        event.startDate = payload.startDate
        event.endDate = payload.endDate
    }

    static func needsUpdate(payload: MirroredEventPayload, event: EKEvent, contentHash: String) -> Bool {
        contentHash != payload.canonicalHash
            || event.title != payload.title
            || event.startDate != payload.startDate
            || event.endDate != payload.endDate
            || event.isAllDay != payload.isAllDay
            || (event.notes ?? "") != payload.body
            || (event.location ?? "") != (payload.location ?? "")
    }
}

enum CalendarMirrorError: Error {
    case noUsableSource
    case calendarMissing
    case notAuthorized
}
