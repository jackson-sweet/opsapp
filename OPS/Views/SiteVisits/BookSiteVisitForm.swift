//
//  BookSiteVisitForm.swift
//  OPS
//
//  The booking sheet's decision core — pure state, no SwiftUI, no network —
//  so validation, the untouched-heads-up rule, and reschedule's
//  send-only-what-changed contract are provable in isolation.
//
//  Two contract details live here and nowhere else:
//  • An untouched HEADS-UP row means NO per-booking override — every assignee
//    keeps their own default lead. Only a deliberate tap pins one.
//  • Reschedule sends nil for every unchanged field (the RPC's NULL-keeps
//    contract), so a crew-only change never re-validates a past time.
//

import Foundation

struct BookSiteVisitForm: Equatable {

    // MARK: - Mode

    /// The open booking a reschedule edits. Values are the server's current
    /// truth; intents diff against them.
    struct BookingSnapshot: Equatable {
        let siteVisitId: String
        let scheduledAt: Date
        let durationMinutes: Int
        let assigneeIds: [String]
        let reminderLeadMinutes: Int?
    }

    enum Mode: Equatable {
        case create
        case reschedule(BookingSnapshot)
    }

    // MARK: - Intents

    struct CreateIntent: Equatable {
        let scheduledAt: Date
        let durationMinutes: Int
        /// nil = booker only; the server defaults assignees to the actor.
        let assigneeIds: [String]?
        /// nil = no per-booking override.
        let reminderLeadMinutes: Int?
    }

    struct RescheduleIntent: Equatable {
        let siteVisitId: String
        let scheduledAt: Date?
        let durationMinutes: Int?
        let assigneeIds: [String]?
        let reminderOverride: SiteVisitReminderOverride

        var hasChanges: Bool {
            scheduledAt != nil
                || durationMinutes != nil
                || assigneeIds != nil
                || reminderOverride != .keep
        }
    }

    // MARK: - State

    let mode: Mode
    let bookerId: String

    private(set) var scheduledAt: Date
    private(set) var durationMinutes: Int
    private(set) var assigneeIds: Set<String>
    private(set) var headsUpMinutes: Int
    private(set) var headsUpTouched: Bool

    static let durationPresets = [30, 60, 90, 120, 240]
    static let headsUpPresets = [15, 30, 60, 120]

    // MARK: - Construction

    static func create(
        bookerId: String,
        defaultHeadsUpMinutes: Int,
        startingAt: Date
    ) -> BookSiteVisitForm {
        BookSiteVisitForm(
            mode: .create,
            bookerId: bookerId.lowercased(),
            scheduledAt: startingAt,
            durationMinutes: 60,
            assigneeIds: [bookerId.lowercased()],
            headsUpMinutes: defaultHeadsUpMinutes,
            headsUpTouched: false
        )
    }

    static func reschedule(
        existing: BookingSnapshot,
        bookerId: String,
        defaultHeadsUpMinutes: Int
    ) -> BookSiteVisitForm {
        BookSiteVisitForm(
            mode: .reschedule(existing),
            bookerId: bookerId.lowercased(),
            scheduledAt: existing.scheduledAt,
            durationMinutes: existing.durationMinutes,
            assigneeIds: Set(existing.assigneeIds.map { $0.lowercased() }),
            headsUpMinutes: existing.reminderLeadMinutes ?? defaultHeadsUpMinutes,
            headsUpTouched: false
        )
    }

    // MARK: - Mutations

    mutating func setDateAndTime(_ date: Date) {
        scheduledAt = date
    }

    mutating func selectDuration(_ minutes: Int) {
        durationMinutes = minutes
    }

    /// WHO'S GOING can never be empty — deselecting the last member falls
    /// back to the booker, so there is no dead state and no error to explain.
    mutating func setAssignees(_ ids: Set<String>) {
        let canonical = Set(ids.map { $0.lowercased() })
        assigneeIds = canonical.isEmpty ? [bookerId] : canonical
    }

    mutating func selectHeadsUp(_ minutes: Int) {
        headsUpMinutes = minutes
        headsUpTouched = true
    }

    /// The settings default arrives async so the sheet never blocks on the
    /// network. It lands only while the row is untouched, and never displaces
    /// an existing per-booking override.
    mutating func seedDefaultHeadsUp(_ minutes: Int) {
        guard !headsUpTouched else { return }
        if case .reschedule(let existing) = mode, existing.reminderLeadMinutes != nil {
            return
        }
        headsUpMinutes = minutes
    }

    // MARK: - Derived

    func mergedDate() -> Date { scheduledAt }

    /// A provided time must be in the future. In reschedule mode an untouched
    /// time is never sent, so it never needs to pass this check.
    func isValid(now: Date) -> Bool {
        if case .reschedule(let existing) = mode, scheduledAt == existing.scheduledAt {
            return true
        }
        return scheduledAt > now
    }

    var durationOptions: [Int] {
        options(presets: Self.durationPresets, current: durationMinutes)
    }

    var headsUpOptions: [Int] {
        options(presets: Self.headsUpPresets, current: headsUpMinutes)
    }

    private func options(presets: [Int], current: Int) -> [Int] {
        Array(Set(presets + [current])).sorted()
    }

    static func durationLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0, minutes >= 60, minutes / 60 <= 8 {
            return "\(minutes / 60) HR"
        }
        return "\(minutes) MIN"
    }

    static func headsUpLabel(_ minutes: Int) -> String {
        durationLabel(minutes)
    }

    // MARK: - Intents

    func createIntent() -> CreateIntent {
        let sorted = assigneeIds.sorted()
        return CreateIntent(
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            assigneeIds: sorted == [bookerId] ? nil : sorted,
            reminderLeadMinutes: headsUpTouched ? headsUpMinutes : nil
        )
    }

    func rescheduleIntent() -> RescheduleIntent {
        guard case .reschedule(let existing) = mode else {
            preconditionFailure("rescheduleIntent() requires reschedule mode")
        }
        let sorted = assigneeIds.sorted()
        let originalSorted = existing.assigneeIds.map { $0.lowercased() }.sorted()
        let reminder: SiteVisitReminderOverride =
            headsUpTouched && headsUpMinutes != existing.reminderLeadMinutes
                ? .set(headsUpMinutes)
                : .keep
        return RescheduleIntent(
            siteVisitId: existing.siteVisitId,
            scheduledAt: scheduledAt == existing.scheduledAt ? nil : scheduledAt,
            durationMinutes: durationMinutes == existing.durationMinutes ? nil : durationMinutes,
            assigneeIds: sorted == originalSorted ? nil : sorted,
            reminderOverride: reminder
        )
    }
}
