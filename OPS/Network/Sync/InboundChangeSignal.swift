//
//  InboundChangeSignal.swift
//  OPS
//
//  Typed "server data landed" signal connecting every inbound merge path
//  (Realtime, delta sync, full sync — actor and legacy alike) to the UI
//  surfaces that cache snapshots instead of running live @Query fetches.
//
//  Why this exists: SwiftUI @Query screens pick up in-place updates from
//  background saves natively, but snapshot caches do not. The calendar
//  (CalendarViewModel.dayTaskCache) buckets tasks per day once and only
//  rebuilds on LOCAL edit signals — so a teammate's reschedule arrived in
//  SwiftData but never repainted the schedule. This channel is the missing
//  inbound half of that invalidation contract.
//
//  Contract:
//   - Producers post via `InboundChangeSignal.post(entityNames:)` AFTER a
//     successful SwiftData save of server data. Names are SwiftData model
//     class names ("ProjectTask", "Project", …).
//   - Posting is opt-in per merge site. Realtime merges post per event;
//     batch syncs accumulate and post once after relationship linking so a
//     mid-sync repaint can never observe unlinked relationships.
//   - `InboundChangeRouter` (owned by DataController) coalesces bursts and
//     fans out to the existing refresh chains — it never adds new ones:
//       • ProjectTask / Project / TaskType → DataController.scheduledTasksDidChange
//         (ScheduleView, MonthGridView, CalendarDaySelector already observe it)
//       • CalendarUserEvent → "CalendarUserEventsDidChange" notification
//         (ScheduleView.loadUserEvents, MonthGridView, CalendarDaySelector
//         already observe it)
//       • TaskReminder → rebuild the current user's local reminder schedules
//         from the main SwiftData context after the actor save lands
//
//  Performance: trailing debounce (default 250 ms) collapses merge storms to
//  a single cache rebuild, with a max-latency bound (default 1 s) so a
//  continuous realtime stream can never starve the repaint. Rebuild cost is
//  identical to the existing pull-to-refresh path — one fetch + in-memory
//  bucketing — and only fires when calendar-relevant entities changed.
//

import Foundation
import Combine

// MARK: - Notification Name

extension Notification.Name {
    /// Posted after any inbound sync path saves server data into SwiftData.
    /// userInfo[InboundChangeSignal.entityNamesKey]: [String] — model class names.
    static let inboundDataMerged = Notification.Name("OPSInboundDataMerged")

    /// Posted after inbound photo annotation rows merge. Mounted photo
    /// surfaces use this to re-run annotation compositing for current photos.
    static let projectPhotoAnnotationsChanged = Notification.Name("OPSProjectPhotoAnnotationsChanged")
}

// MARK: - Signal

enum InboundChangeSignal {

    static let entityNamesKey = "entityNames"

    /// Announce that server rows for the given model types were just saved
    /// locally. Safe to call from any thread or actor — NotificationCenter
    /// delivery is thread-safe and the router re-dispatches onto main.
    static func post(entityNames: Set<String>) {
        guard !entityNames.isEmpty else { return }
        NotificationCenter.default.post(
            name: .inboundDataMerged,
            object: nil,
            userInfo: [entityNamesKey: Array(entityNames)]
        )
    }

    /// Supabase table name → SwiftData model class name for the tables the
    /// realtime delete path soft-deletes. Returns nil for tables that have
    /// no snapshot-cache consumer (nothing routes on them today).
    static func entityName(forTable table: String) -> String? {
        switch table {
        case "projects":                  return "Project"
        case "project_tasks":             return "ProjectTask"
        case "users":                     return "User"
        case "clients":                   return "Client"
        case "companies":                 return "Company"
        case "task_types":                return "TaskType"
        case "site_visit_types":          return "SiteVisitType"
        case "sub_clients":               return "SubClient"
        case "project_notes":             return "ProjectNote"
        case "project_photos":            return "ProjectPhoto"
        case "project_photo_annotations": return "PhotoAnnotation"
        case "deck_designs":              return "DeckDesign"
        case "site_visits":               return "SiteVisit"
        case "site_visit_artifacts":      return "SiteVisitCaptureArtifact"
        case "site_visit_checklist_answers":
            return "SiteVisitChecklistAnswer"
        case "site_visit_identity_drafts":
            return "SiteVisitIdentityDraft"
        case "calendar_user_events":      return "CalendarUserEvent"
        case "catalog_categories":        return "CatalogCategory"
        case "catalog_units":             return "CatalogUnit"
        case "catalog_tags":              return "CatalogTag"
        case "catalog_items":             return "CatalogItem"
        case "catalog_variants":          return "CatalogVariant"
        case "catalog_orders":            return "CatalogOrder"
        default:                          return nil
        }
    }
}

// MARK: - Router

/// Coalesces `.inboundDataMerged` bursts and routes them to the app's
/// existing calendar refresh chains. Owned by DataController; created on
/// main and main-confined (mirrors MainContextRefreshBridge's pattern).
///
/// Debounce semantics: trailing-edge with a max-latency bound. Each arrival
/// re-arms the flush timer; if arrivals keep coming, the max-latency clock
/// forces a flush so the UI is never starved by a continuous merge stream.
///
/// The clock and the debounce scheduler are injectable so unit tests can
/// drive time deterministically instead of racing wall-clock timers under
/// load. Production always uses the defaults — `Date` for the clock and a
/// main-queue `asyncAfter` for the flush deadline — so runtime behavior is
/// unchanged by the seam.
@MainActor
final class InboundChangeRouter {

    /// Model types whose inbound changes must repaint the schedule surfaces.
    /// TaskType is included because type renames / color changes alter task
    /// card rendering and the calendar's type filters.
    static let calendarEntityNames: Set<String> = ["ProjectTask", "Project", "TaskType"]

    static let userEventEntityName = "CalendarUserEvent"
    static let photoAnnotationEntityName = "PhotoAnnotation"
    static let taskReminderEntityName = "TaskReminder"
    static let siteVisitEntityName = "SiteVisit"

    // MARK: - Configuration

    private let debounceInterval: TimeInterval
    private let maxLatency: TimeInterval
    private let now: () -> Date
    private let scheduleFlush: (TimeInterval, DispatchWorkItem) -> Void
    private let onCalendarTasksChanged: () -> Void
    private let onUserEventsChanged: () -> Void
    private let onTaskRemindersChanged: () -> Void
    private let onSiteVisitsChanged: () -> Void

    // MARK: - State

    private var pendingEntityNames: Set<String> = []
    private var pendingFlush: DispatchWorkItem?
    private var firstAccumulatedAt: Date?
    private var cancellable: AnyCancellable?

    // MARK: - Init

    init(
        debounceInterval: TimeInterval = 0.25,
        maxLatency: TimeInterval = 1.0,
        now: @escaping () -> Date = Date.init,
        scheduleFlush: @escaping (_ delay: TimeInterval, _ work: DispatchWorkItem) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        onCalendarTasksChanged: @escaping () -> Void,
        onUserEventsChanged: @escaping () -> Void,
        onTaskRemindersChanged: @escaping () -> Void = {},
        onSiteVisitsChanged: @escaping () -> Void = {}
    ) {
        self.debounceInterval = debounceInterval
        self.maxLatency = maxLatency
        self.now = now
        self.scheduleFlush = scheduleFlush
        self.onCalendarTasksChanged = onCalendarTasksChanged
        self.onUserEventsChanged = onUserEventsChanged
        self.onTaskRemindersChanged = onTaskRemindersChanged
        self.onSiteVisitsChanged = onSiteVisitsChanged

        self.cancellable = NotificationCenter.default
            .publisher(for: .inboundDataMerged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let names = notification.userInfo?[InboundChangeSignal.entityNamesKey] as? [String],
                      !names.isEmpty else { return }
                self?.accumulate(names)
            }
    }

    deinit {
        cancellable?.cancel()
        pendingFlush?.cancel()
    }

    // MARK: - Accumulate + Flush

    private func accumulate(_ names: [String]) {
        pendingEntityNames.formUnion(names)

        if firstAccumulatedAt == nil {
            firstAccumulatedAt = now()
        }

        // Max-latency bound: a continuous stream of merges (realtime storm)
        // must not push the flush out forever.
        if let first = firstAccumulatedAt,
           now().timeIntervalSince(first) >= maxLatency {
            pendingFlush?.cancel()
            flush()
            return
        }

        pendingFlush?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        pendingFlush = work
        scheduleFlush(debounceInterval, work)
    }

    private func flush() {
        let names = pendingEntityNames
        pendingEntityNames = []
        pendingFlush = nil
        firstAccumulatedAt = nil

        guard !names.isEmpty else { return }

        if !names.isDisjoint(with: Self.calendarEntityNames) {
            onCalendarTasksChanged()
        }
        if names.contains(Self.userEventEntityName) {
            onUserEventsChanged()
        }
        if names.contains(Self.photoAnnotationEntityName) {
            NotificationCenter.default.post(name: .projectPhotoAnnotationsChanged, object: nil)
        }
        if names.contains(Self.taskReminderEntityName) {
            onTaskRemindersChanged()
        }
        if names.contains(Self.siteVisitEntityName) {
            onSiteVisitsChanged()
        }
    }
}

// MARK: - RealtimeUpdate → Entity Name

extension RealtimeUpdate {
    /// SwiftData model class name written by this update's merge. Used to
    /// post `.inboundDataMerged` after a successful realtime transaction.
    var mergedEntityName: String {
        switch self {
        case .project:               return "Project"
        case .task:                  return "ProjectTask"
        case .user:                  return "User"
        case .client:                return "Client"
        case .company:               return "Company"
        case .taskType:              return "TaskType"
        case .siteVisitType:         return "SiteVisitType"
        case .subClient:             return "SubClient"
        case .projectNote:           return "ProjectNote"
        case .projectPhoto:          return "ProjectPhoto"
        case .photoAnnotation:       return "PhotoAnnotation"
        case .deckDesign:            return "DeckDesign"
        case .siteVisit:             return "SiteVisit"
        case .siteVisitArtifact:     return "SiteVisitCaptureArtifact"
        case .siteVisitChecklistAnswer:
            return "SiteVisitChecklistAnswer"
        case .siteVisitIdentityDraft:
            return "SiteVisitIdentityDraft"
        case .catalogCategory:       return "CatalogCategory"
        case .catalogUnit:           return "CatalogUnit"
        case .catalogTag:            return "CatalogTag"
        case .catalogItem:           return "CatalogItem"
        case .catalogVariant:        return "CatalogVariant"
        case .catalogSnapshot:       return "CatalogSnapshot"
        case .catalogOrder:          return "CatalogOrder"
        case .companyDefaultProduct: return "CompanyDefaultProduct"
        case .product:               return "Product"
        case .calendarUserEvent:     return "CalendarUserEvent"
        }
    }
}
