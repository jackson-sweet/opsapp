//
//  SchedulerDayContext.swift
//  OPS
//
//  The availability engine behind the schedule sheet. Pure value logic — no
//  SwiftData, no SwiftUI — so every rule below is testable in isolation and the
//  view layer only renders what this type decides.
//
//  It answers four questions for the person picking dates:
//    1. What is already on this day?          → `signals(for:)`, `events(on:)`
//    2. What breaks if I pick this range?     → `rangeReview(start:end:)`
//    3. Where should I start?                 → `suggestion`
//    4. What does this day mean, in words?    → `interpretation(for:)`
//
//  NOTHING here blocks a date. Every signal is a guide: the dependency floor
//  dims, conflicts get named, time off is called out — and the operator still
//  picks whatever day the job actually needs.
//

import Foundation

// MARK: - Selection state machine

/// The sheet's date selection. There is exactly one commit point (footer SAVE),
/// and it reads `.range` — so the machine below is the whole contract between
/// tapping a day and being allowed to save.
enum SchedulerSelection: Equatable {
    case none
    case start(Date)
    case range(Date, Date)

    /// Restores a selection from dates already persisted on the item, so
    /// reopening the sheet shows what is scheduled today (and SAVE is
    /// immediately valid) instead of an empty picker.
    static func prefilled(
        start: Date?,
        end: Date?,
        calendar: Calendar = .current
    ) -> SchedulerSelection {
        guard let start else { return .none }
        let first = calendar.startOfDay(for: start)
        guard let end else { return .start(first) }
        let second = calendar.startOfDay(for: end)
        return .range(min(first, second), max(first, second))
    }

    /// Tap transition. `.none` → start · `.start` → range (auto-sorted, so a
    /// backwards pick is a valid range, not an error) · `.range` → restart.
    func tapping(_ day: Date, calendar: Calendar = .current) -> SchedulerSelection {
        let tapped = calendar.startOfDay(for: day)
        switch self {
        case .none:
            return .start(tapped)
        case .start(let anchor):
            let first = calendar.startOfDay(for: anchor)
            return .range(min(first, tapped), max(first, tapped))
        case .range:
            return .start(tapped)
        }
    }

    /// What the long-press day inspector's single action does from here. Only
    /// a half-made selection can be *ended*; everything else starts fresh.
    enum DayAction: Equatable {
        case useAsStart
        case useAsEnd
    }

    var dayAction: DayAction {
        if case .start = self { return .useAsEnd }
        return .useAsStart
    }

    var startDate: Date? {
        switch self {
        case .none: return nil
        case .start(let day): return day
        case .range(let start, _): return start
        }
    }

    var endDate: Date? {
        switch self {
        case .none, .start: return nil
        case .range(_, let end): return end
        }
    }

    /// Inclusive day count of a completed range; nil until one exists.
    func dayCount(calendar: Calendar = .current) -> Int? {
        guard case .range(let start, let end) = self else { return nil }
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return days + 1
    }

    /// SAVE is live only on a completed range.
    var isCommittable: Bool {
        if case .range = self { return true }
        return false
    }

    func contains(_ day: Date, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: day)
        switch self {
        case .none:
            return false
        case .start(let anchor):
            return calendar.isDate(anchor, inSameDayAs: target)
        case .range(let start, let end):
            return target >= calendar.startOfDay(for: start)
                && target <= calendar.startOfDay(for: end)
        }
    }

    func isStart(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard let start = startDate else { return false }
        return calendar.isDate(start, inSameDayAs: day)
    }

    func isEnd(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard let end = endDate else { return false }
        return calendar.isDate(end, inSameDayAs: day)
    }

    /// What a given day is *within* the selection — the day cell's whole
    /// drawing contract. A half-made selection reads as a closed cap rather
    /// than an open-ended bar: nothing has been picked on the other side yet,
    /// so promising a continuation would be a lie.
    enum DayRole: Equatable {
        case none
        case single
        case start
        case end
        case interior
    }

    func role(for day: Date, calendar: Calendar = .current) -> DayRole {
        let target = calendar.startOfDay(for: day)
        switch self {
        case .none:
            return .none
        case .start(let anchor):
            return calendar.isDate(anchor, inSameDayAs: target) ? .single : .none
        case .range(let start, let end):
            let first = calendar.startOfDay(for: start)
            let last = calendar.startOfDay(for: end)
            if first == last {
                return target == first ? .single : .none
            }
            if target == first { return .start }
            if target == last { return .end }
            return (target > first && target < last) ? .interior : .none
        }
    }

    /// Where a day sits inside a completed range: its 0-based index and the
    /// range's inclusive day count. The day cell draws its slice of one
    /// continuous curve spanning the whole selection, so it needs to know its
    /// place in the span rather than just its role in it.
    ///
    /// Purely ordinal — no weekday, no row. A span reads as one object whether
    /// it fits a week row or wraps three of them.
    func spanPosition(for day: Date, calendar: Calendar = .current) -> (index: Int, count: Int)? {
        guard case .range(let start, let end) = self else { return nil }
        let target = calendar.startOfDay(for: day)
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard target >= first, target <= last else { return nil }
        guard let index = calendar.dateComponents([.day], from: first, to: target).day,
              let span = calendar.dateComponents([.day], from: first, to: last).day else { return nil }
        return (index: index, count: span + 1)
    }
}

// MARK: - SchedulerDayContext

struct SchedulerDayContext {

    // MARK: Inputs

    /// One commitment the scheduler can see — a crew job or a block of time
    /// off. Value-typed on purpose: the engine never touches the model store,
    /// so the caller resolves names, coordinates, and crew once and the rules
    /// below stay pure.
    struct Event: Identifiable, Equatable {
        enum Kind: Equatable {
            case job
            case timeOff
        }

        let id: String
        let kind: Kind
        /// Job → the project's title. Time off → the person's first name.
        /// This is the row's headline; a bare task-type name is never enough
        /// to recognise a job you are about to collide with.
        let title: String
        /// Job → the client's name. Time off → nil.
        let subtitle: String?
        /// Job → the task's own display title, used only where the day is
        /// already identified by project (the same-project interpretation).
        let taskTitle: String?
        let projectId: String?
        let start: Date
        let end: Date
        let crewIds: Set<String>
        /// userId → first name, for the crew on this event. Resolved by the
        /// caller so attribution can name a person, not an id.
        let crewFirstNames: [String: String]
        let latitude: Double?
        let longitude: Double?

        init(
            id: String,
            kind: Kind,
            title: String,
            subtitle: String? = nil,
            taskTitle: String? = nil,
            projectId: String? = nil,
            start: Date,
            end: Date,
            crewIds: Set<String> = [],
            crewFirstNames: [String: String] = [:],
            latitude: Double? = nil,
            longitude: Double? = nil
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.taskTitle = taskTitle
            self.projectId = projectId
            self.start = start
            self.end = end
            self.crewIds = crewIds
            self.crewFirstNames = crewFirstNames
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// The thing being scheduled.
    struct Item {
        /// The task's own id when rescheduling, so it never conflicts with
        /// itself. nil for projects and unsaved drafts.
        let selfTaskId: String?
        let projectId: String?
        let crewIds: Set<String>
        let latitude: Double?
        let longitude: Double?
        let dependencies: [TaskTypeDependency]
        /// False when the item has no dates yet — the only state that earns a
        /// suggestion chip.
        let isScheduled: Bool

        init(
            selfTaskId: String? = nil,
            projectId: String? = nil,
            crewIds: Set<String> = [],
            latitude: Double? = nil,
            longitude: Double? = nil,
            dependencies: [TaskTypeDependency] = [],
            isScheduled: Bool
        ) {
            self.selfTaskId = selfTaskId
            self.projectId = projectId
            self.crewIds = crewIds
            self.latitude = latitude
            self.longitude = longitude
            self.dependencies = dependencies
            self.isScheduled = isScheduled
        }
    }

    /// A predecessor task that is BOTH a declared dependency of the item AND
    /// already on the calendar. Unscheduled prerequisites are simply absent —
    /// which is why "nothing scheduled upstream" produces no floor and no
    /// dimming anywhere.
    struct Prerequisite {
        let taskTypeId: String
        let title: String
        let start: Date
        let duration: Int

        init(taskTypeId: String, title: String, start: Date, duration: Int) {
            self.taskTypeId = taskTypeId
            self.title = title
            self.start = start
            self.duration = duration
        }
    }

    // MARK: Outputs

    /// Everything a single day cell needs to draw itself.
    struct DaySignals: Equatable {
        var thisProject = false
        var crewBusy = false
        var crewTimeOff = false
        /// Commitments on this day that touch neither the item's crew nor its
        /// project — density only, never a conflict.
        var otherCount = 0
        /// Strictly before the dependency floor. Dims; never blocks.
        var isPreFloor = false

        var isEmpty: Bool {
            !thisProject && !crewBusy && !crewTimeOff && otherCount == 0
        }
    }

    /// The one date worth proposing, and the reason it is worth proposing. A
    /// bare date is a guess; a date with a reason is an argument — and the
    /// chip says the reason out loud.
    struct Suggestion: Equatable {
        enum Reason: Equatable {
            /// A scheduled prerequisite set the earliest legal start. Carries
            /// its title so the chip can name the job being waited on.
            case afterPrerequisite(String)
            /// Nothing upstream to wait for — this is simply the first day the
            /// item's crew is actually free.
            case crewClear
        }

        let date: Date
        let reason: Reason
    }

    /// What a completed range costs.
    struct RangeReview: Equatable {
        /// Relevant commitments across the range, conflicts first.
        let rows: [Event]
        let conflictCount: Int
        /// The floor date when the picked start lands before it. Advisory —
        /// SAVE stays enabled.
        let floorViolation: Date?
    }

    // MARK: Stored

    let item: Item
    let events: [Event]
    let skipsWeekends: Bool
    /// First day the item may start given its scheduled prerequisites. nil when
    /// no prerequisite is scheduled — no floor, no dimming.
    let dependencyFloor: Date?
    /// Title of the prerequisite that set the floor, so the note can name it.
    let floorPrerequisiteTitle: String?

    private let calendar: Calendar
    /// day → commitments spanning it. Built once, in a single pass over the
    /// events, so the grid is O(events) per rebuild rather than
    /// O(cells × events × spanned days) — the blowup that made the old sheet
    /// stutter on every sync republish.
    private let eventsByDay: [Date: [Event]]

    // MARK: Init

    init(
        item: Item,
        events: [Event],
        prerequisites: [Prerequisite] = [],
        skipsWeekends: Bool = false,
        calendar: Calendar = .current
    ) {
        self.item = item
        self.skipsWeekends = skipsWeekends
        self.calendar = calendar

        // The item never competes with itself.
        let visible = events.filter { $0.id != item.selfTaskId }
        self.events = visible

        var index: [Date: [Event]] = [:]
        for event in visible {
            var cursor = calendar.startOfDay(for: event.start)
            let last = calendar.startOfDay(for: max(event.start, event.end))
            // Bounded: a commitment spanning more than two years is data
            // corruption, not a schedule — stop rather than spin.
            var guardCount = 0
            while cursor <= last && guardCount < 800 {
                index[cursor, default: []].append(event)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                guardCount += 1
            }
        }
        self.eventsByDay = index

        var floor: Date?
        var floorTitle: String?
        for dependency in item.dependencies {
            for prerequisite in prerequisites
            where prerequisite.taskTypeId == dependency.dependsOnTaskTypeId {
                let earliest = calendar.startOfDay(
                    for: dependency.earliestStart(
                        predecessorStart: prerequisite.start,
                        predecessorDuration: prerequisite.duration
                    )
                )
                if floor == nil || earliest > floor! {
                    floor = earliest
                    floorTitle = prerequisite.title
                }
            }
        }
        self.dependencyFloor = floor
        self.floorPrerequisiteTitle = floorTitle
    }

    // MARK: Day signals

    func signals(for day: Date) -> DaySignals {
        let key = calendar.startOfDay(for: day)
        var signals = DaySignals()

        for event in eventsByDay[key] ?? [] {
            let crewOverlap = intersectsItemCrew(event)
            switch event.kind {
            case .timeOff:
                if crewOverlap {
                    signals.crewTimeOff = true
                } else {
                    signals.otherCount += 1
                }
            case .job:
                let sameProject = isSameProject(event)
                if sameProject { signals.thisProject = true }
                if crewOverlap { signals.crewBusy = true }
                if !sameProject && !crewOverlap { signals.otherCount += 1 }
            }
        }

        if let floor = dependencyFloor, key < floor {
            signals.isPreFloor = true
        }
        return signals
    }

    /// A day's commitments split into what touches this job (crew or project)
    /// and everything else. The panel and day sheet lead with the first group;
    /// the rest lives under `// ELSEWHERE`.
    func events(on day: Date) -> (relevant: [Event], elsewhere: [Event]) {
        let key = calendar.startOfDay(for: day)
        var relevant: [Event] = []
        var elsewhere: [Event] = []
        for event in eventsByDay[key] ?? [] {
            if isRelevant(event) { relevant.append(event) } else { elsewhere.append(event) }
        }
        return (relevant.sorted(by: rowOrder), elsewhere.sorted { $0.start < $1.start })
    }

    // MARK: Range review

    func rangeReview(start: Date, end: Date) -> RangeReview {
        let lower = calendar.startOfDay(for: min(start, end))
        let upper = calendar.startOfDay(for: max(start, end))

        var rows: [Event] = []
        var seen = Set<String>()
        var cursor = lower
        var guardCount = 0
        while cursor <= upper && guardCount < 800 {
            for event in eventsByDay[cursor] ?? [] where isRelevant(event) {
                if seen.insert(event.id).inserted { rows.append(event) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            guardCount += 1
        }

        let ordered = rows.sorted(by: rowOrder)
        let conflicts = ordered.filter(isConflict).count
        var violation: Date?
        if let floor = dependencyFloor, lower < floor { violation = floor }

        return RangeReview(rows: ordered, conflictCount: conflicts, floorViolation: violation)
    }

    /// True when this commitment double-books the item's crew — the only thing
    /// the sheet calls a conflict. Sharing a project is normal work, not a clash.
    func isConflict(_ event: Event) -> Bool {
        intersectsItemCrew(event)
    }

    /// Who on the item's crew this commitment ties up — one name, or a count.
    func attribution(for event: Event) -> String? {
        let overlap = event.crewIds.intersection(item.crewIds)
        guard !overlap.isEmpty else { return nil }
        if overlap.count == 1, let id = overlap.first {
            return (event.crewFirstNames[id] ?? "CREW").uppercased()
        }
        return "\(overlap.count) CREW"
    }

    func isSameProject(_ event: Event) -> Bool {
        guard let projectId = item.projectId, let eventProject = event.projectId else { return false }
        return projectId == eventProject
    }

    // MARK: Suggestion

    /// How far past the baseline the walk looks before giving up. A crew booked
    /// solid for two months has no next opening worth naming, and an honest
    /// silence beats a date nobody can work.
    private static let suggestionWalkLimit = 60

    /// The one date worth proposing, found by a single forward walk.
    ///
    /// The walk starts at the dependency floor when one exists, and otherwise
    /// at tomorrow — today is already half spent. Either way it never starts
    /// earlier than tomorrow: a floor whose prerequisite already ended is
    /// history, not a constraint, and the walk never proposes a day that is
    /// gone. From there it takes the first day that is a working day AND that
    /// the item's crew is genuinely free on, so the proposal survives contact
    /// with the calendar instead of landing on a day the crew is already
    /// committed to.
    ///
    /// Offered only when the item has no dates yet — re-proposing a start for
    /// something already on the calendar is noise, not help — and only when
    /// there is something real to reason from. With neither a prerequisite nor
    /// a crew, nothing on the calendar recommends one day over another, and a
    /// suggestion without a reason is noise wearing a chip.
    var suggestion: Suggestion? {
        guard !item.isScheduled else { return nil }

        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: Date())
        ) else { return nil }

        let baseline: Date
        if let floor = dependencyFloor {
            // A prerequisite that has already finished stops being a
            // constraint and becomes history, so the floor is clamped forward.
            // An item with no crew rides this same clamp — the old floor-only
            // contract, now incapable of naming a day that is gone.
            baseline = max(calendar.startOfDay(for: floor), tomorrow)
        } else if !item.crewIds.isEmpty {
            baseline = tomorrow
        } else {
            return nil
        }

        // Naming both a prerequisite and a crew opening overloads one chip. The
        // prerequisite is the harder fact, so it is the reason given — and the
        // date genuinely is after it either way.
        let reason: Suggestion.Reason = floorPrerequisiteTitle
            .map(Suggestion.Reason.afterPrerequisite) ?? .crewClear

        var day = baseline
        for _ in 0...Self.suggestionWalkLimit {
            if isProposable(day) { return Suggestion(date: day, reason: reason) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }

    /// A day the item could actually start on: a working day, with neither the
    /// crew booked elsewhere nor any of them off. Same-project work and other
    /// crews' jobs are density, not an obstacle — they never veto a proposal.
    private func isProposable(_ day: Date) -> Bool {
        if skipsWeekends && calendar.isDateInWeekend(day) { return false }
        let signals = signals(for: day)
        return !signals.crewBusy && !signals.crewTimeOff
    }

    // MARK: Distance

    func distanceKM(to event: Event) -> Double? {
        guard let lat1 = item.latitude, let lon1 = item.longitude,
              let lat2 = event.latitude, let lon2 = event.longitude else { return nil }
        return HaversineDistance.km(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
    }

    /// Close distances earn a decimal (the difference between 2.1 and 2.8 km is
    /// a real difference to a crew); far ones round — nobody drives 12.4.
    static func distanceLabel(_ km: Double) -> String {
        km < 10
            ? String(format: "%.1f KM", km)
            : "\(Int(km.rounded())) KM"
    }

    /// Distance is only ever news about *another* site. Telling someone their
    /// own job is 0.0 km away is noise dressed as data.
    func distanceLabel(to event: Event) -> String? {
        guard !isSameProject(event), let km = distanceKM(to: event) else { return nil }
        return Self.distanceLabel(km)
    }

    // MARK: Interpretation

    /// One plain-language line explaining what a day means for this job, in
    /// priority order — time off outranks a busy crew, which outranks the
    /// dependency floor, which outranks same-project work. Two clauses maximum:
    /// a third is a paragraph, and nobody reads a paragraph on a calendar.
    func interpretation(for day: Date) -> String {
        let key = calendar.startOfDay(for: day)
        let dayEvents = eventsByDay[key] ?? []
        var clauses: [String] = []

        let timeOff = dayEvents.filter { $0.kind == .timeOff && intersectsItemCrew($0) }
        if !timeOff.isEmpty {
            let names = overlappingFirstNames(in: timeOff)
            if names.count <= 1 {
                clauses.append("\((names.first ?? "CREW").uppercased()) OFF")
            } else {
                clauses.append("\(names[0].uppercased()) + \(names.count - 1) OFF")
            }
        }

        let busy = dayEvents.filter { $0.kind == .job && intersectsItemCrew($0) }
        if clauses.count < 2, !busy.isEmpty {
            let names = overlappingFirstNames(in: busy)
            if names.count == 1, let job = busy.first {
                clauses.append("\(names[0].uppercased()) ON \(job.title.uppercased())")
            } else {
                clauses.append("\(names.count) CREW ON OTHER JOBS")
            }
        }

        if clauses.count < 2,
           let floor = dependencyFloor,
           key < floor,
           let prerequisite = floorPrerequisiteTitle {
            clauses.append("BEFORE \(prerequisite.uppercased()) ENDS · \(Self.shortDate(floor, calendar: calendar).uppercased())")
        }

        if clauses.count < 2,
           let sameProject = dayEvents.first(where: { $0.kind == .job && isSameProject($0) }) {
            let label = sameProject.taskTitle ?? sameProject.title
            clauses.append("\(label.uppercased()) · THIS PROJECT")
        }

        if clauses.isEmpty {
            // With no crew on the item there is no availability to report, so
            // claiming the crew is clear would be a lie. Report the day instead.
            return item.crewIds.isEmpty ? "NO JOBS" : "CREW CLEAR"
        }
        return clauses.prefix(2).joined(separator: " · ")
    }

    // MARK: Formatting

    static func shortDate(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    static func weekdayDate(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date)
    }

    static func monthCaption(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    // MARK: Private

    private func intersectsItemCrew(_ event: Event) -> Bool {
        guard !item.crewIds.isEmpty else { return false }
        return !event.crewIds.isDisjoint(with: item.crewIds)
    }

    private func isRelevant(_ event: Event) -> Bool {
        intersectsItemCrew(event) || isSameProject(event)
    }

    /// Conflicts first, then chronological, then by id so the order never
    /// shuffles between renders.
    private func rowOrder(_ lhs: Event, _ rhs: Event) -> Bool {
        let left = isConflict(lhs)
        let right = isConflict(rhs)
        if left != right { return left }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        return lhs.id < rhs.id
    }

    /// First names of the item's own crew tied up by these events, deduped and
    /// in a stable order.
    private func overlappingFirstNames(in events: [Event]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for event in events {
            for id in event.crewIds.sorted() where item.crewIds.contains(id) {
                guard seen.insert(id).inserted else { continue }
                names.append(event.crewFirstNames[id] ?? "CREW")
            }
        }
        return names
    }
}
