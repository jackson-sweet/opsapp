//
//  ComparableJobLengthTests.swift
//  OPSTests
//
//  Coverage for the duration suggestion: the pure size-band + median core,
//  the store gather that feeds it, and the weekend-aware span walk the
//  suggestion chip uses to turn a length into an end date.
//
//  Most of what these tests assert is the engine REFUSING to answer. That is
//  the point — a length stated from two jobs, or from a deck twice the size,
//  would be a number with nothing behind it, and the chip earns its trust by
//  staying quiet in exactly those cases.
//

import SwiftData
import XCTest
@testable import OPS

final class ComparableJobLengthTests: XCTestCase {

    private typealias Comp = (areaSqFt: Double, days: Int)

    private let calendar = Calendar.current
    private let companyId = "company-1"
    private let deckingTypeId = "type-decking"
    private let targetProjectId = "project-target"

    /// A fixed "today" so nothing here depends on the day the suite runs.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 29))!
    }

    private func daysFromNow(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    // MARK: - Pure core: size band

    func testTheSizeBandIncludesItsBoundaryAndNothingBeyondIt() {
        // 520 / 400 is exactly the 1.3 cap — in band by a hair.
        let atCap: [Comp] = [
            (areaSqFt: 520, days: 2),
            (areaSqFt: 520, days: 2),
            (areaSqFt: 520, days: 2)
        ]
        XCTAssertEqual(
            ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: atCap),
            2
        )

        // 521 / 400 clears it. An out-of-band job is not weak evidence — it is
        // no evidence, so the answer goes away rather than lean on it.
        let pastCap: [Comp] = [
            (areaSqFt: 521, days: 2),
            (areaSqFt: 521, days: 2),
            (areaSqFt: 521, days: 2)
        ]
        XCTAssertNil(
            ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: pastCap)
        )

        // Symmetric: the comp being the smaller of the pair is the same fact
        // about how alike the two decks are.
        let smallerComps: [Comp] = [
            (areaSqFt: 400, days: 2),
            (areaSqFt: 400, days: 2),
            (areaSqFt: 400, days: 2)
        ]
        XCTAssertEqual(
            ComparableJobLength.suggestedDays(targetAreaSqFt: 520, comparables: smallerComps),
            2
        )
        XCTAssertNil(
            ComparableJobLength.suggestedDays(targetAreaSqFt: 521, comparables: smallerComps)
        )
    }

    func testOutOfBandJobsCannotRescueAThinPool() {
        // Two real comps, and ten jobs on decks nothing like this one. Size is
        // what makes a comp a comp, so the ten are worth exactly as much as none.
        var thin: [Comp] = [(areaSqFt: 400, days: 2), (areaSqFt: 420, days: 2)]
        for _ in 0..<10 { thin.append((areaSqFt: 900, days: 6)) }

        XCTAssertNil(ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: thin))

        // One more in-band job is the whole difference between an anecdote and
        // a pattern — and the ten barns still have no say in the answer.
        var unlocked = thin
        unlocked.append((areaSqFt: 410, days: 2))
        XCTAssertEqual(
            ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: unlocked),
            2
        )
    }

    // MARK: - Pure core: median

    func testOddCountTakesTheMiddleJob() {
        let three: [Comp] = [
            (areaSqFt: 400, days: 1),
            (areaSqFt: 410, days: 2),
            (areaSqFt: 420, days: 3)
        ]
        XCTAssertEqual(
            ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: three),
            2
        )

        // One nine-day outlier cannot drag the answer the way a mean would.
        let withOutlier: [Comp] = [
            (areaSqFt: 400, days: 1),
            (areaSqFt: 405, days: 2),
            (areaSqFt: 410, days: 2),
            (areaSqFt: 415, days: 3),
            (areaSqFt: 420, days: 9)
        ]
        XCTAssertEqual(
            ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: withOutlier),
            2
        )
    }

    func testAnEvenSplitRoundsUpBecauseCrewsOverrun() {
        XCTAssertEqual(ComparableJobLength.roundedMedian(of: [1, 2]), 2)
        XCTAssertEqual(ComparableJobLength.roundedMedian(of: [1, 1, 2, 3]), 2)
        XCTAssertEqual(ComparableJobLength.roundedMedian(of: [2, 4]), 3)
        // An even split landing on a whole number needs no rounding at all.
        XCTAssertEqual(ComparableJobLength.roundedMedian(of: [2, 2]), 2)
        XCTAssertEqual(ComparableJobLength.roundedMedian(of: [3]), 3)
        // Order of arrival never matters.
        XCTAssertEqual(ComparableJobLength.roundedMedian(of: [3, 1, 2, 1]), 2)
        XCTAssertNil(ComparableJobLength.roundedMedian(of: []))

        // Through the full core, where the minimum-three gate also applies.
        let four: [Comp] = [
            (areaSqFt: 400, days: 1),
            (areaSqFt: 405, days: 1),
            (areaSqFt: 410, days: 2),
            (areaSqFt: 415, days: 3)
        ]
        XCTAssertEqual(
            ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: four),
            2
        )
    }

    // MARK: - Pure core: nothing to reason from

    func testAnUnmeasurableTargetOrAnEmptyHistoryProposesNothing() {
        let sound: [Comp] = [
            (areaSqFt: 400, days: 2),
            (areaSqFt: 400, days: 2),
            (areaSqFt: 400, days: 2)
        ]
        // No measurable deck on the job being scheduled.
        XCTAssertNil(ComparableJobLength.suggestedDays(targetAreaSqFt: 0, comparables: sound))
        // Never done this kind of work before.
        XCTAssertNil(ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: []))

        // Comps whose own decks cannot be measured are not comps.
        let unmeasured: [Comp] = [
            (areaSqFt: 0, days: 2),
            (areaSqFt: 0, days: 2),
            (areaSqFt: 0, days: 2)
        ]
        XCTAssertNil(ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: unmeasured))

        // Nor are jobs claiming to have taken no days.
        let zeroDay: [Comp] = [
            (areaSqFt: 400, days: 0),
            (areaSqFt: 400, days: 0),
            (areaSqFt: 400, days: 0)
        ]
        XCTAssertNil(ComparableJobLength.suggestedDays(targetAreaSqFt: 400, comparables: zeroDay))
    }

    // MARK: - Fixture sanity

    /// Every band assertion below rests on the staged drawings really being
    /// the size they claim, so that gets proven on its own before it is used.
    func testTheStagedDrawingMeasuresTheAreaItClaims() throws {
        let drawing = try XCTUnwrap(DeckDrawingData.fromJSON(rectangleDrawingJSON(areaSqFt: 400)))
        XCTAssertEqual(
            drawing.totalRealWorldArea(scaleFactor: drawing.effectiveScaleFactor) / 144.0,
            400,
            accuracy: 0.01
        )
    }

    // MARK: - Gather: the happy path

    func testFinishedInBandJobsSetTheLengthAndOutOfBandOnesDoNot() throws {
        let context = try makeContext()
        stageTargetDeck(in: context, areaSqFt: 400)

        // 380 / 420 / 440 sqft all sit within 1.3× of 400. Days 2, 2, 3.
        stageComp(in: context, name: "a", areaSqFt: 380, dayCount: 2, endingDaysFromNow: -40)
        stageComp(in: context, name: "b", areaSqFt: 420, dayCount: 2, endingDaysFromNow: -30)
        stageComp(in: context, name: "c", areaSqFt: 440, dayCount: 3, endingDaysFromNow: -20)
        // A barn of a deck that took a week. Out of band, so it is not part of
        // the answer — counted, it would make the median 3 instead of 2.
        stageComp(in: context, name: "d", areaSqFt: 900, dayCount: 7, endingDaysFromNow: -10)

        XCTAssertEqual(resolve(in: context), 2)
    }

    func testASameDayJobCountsAsOneDay() throws {
        let context = try makeContext()
        stageTargetDeck(in: context, areaSqFt: 400)
        for (index, name) in ["a", "b", "c"].enumerated() {
            stageComp(
                in: context,
                name: name,
                areaSqFt: 400,
                dayCount: 1,
                endingDaysFromNow: -30 + index
            )
        }

        XCTAssertEqual(resolve(in: context), 1)
    }

    // MARK: - Gather: honesty gates

    func testAJobOnAProjectWithNoDeckProposesNothing() throws {
        let context = try makeContext()
        // Three flawless comps, and no drawing on the job being scheduled.
        // Without a size there is no premise to reason from.
        stageComp(in: context, name: "a", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -40)
        stageComp(in: context, name: "b", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -30)
        stageComp(in: context, name: "c", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -20)

        XCTAssertNil(resolve(in: context))
    }

    func testAnUnmeasurableTargetDrawingProposesNothing() throws {
        let context = try makeContext()
        // A drawing exists but nothing in it closes, so it has no area — the
        // same silence as no drawing at all, for the same reason.
        let empty = DeckDesign(
            id: "design-target-empty",
            companyId: companyId,
            projectId: targetProjectId,
            drawingDataJSON: DeckDrawingData().toJSON()
        )
        empty.updatedAt = daysFromNow(-1)
        context.insert(empty)
        stageComp(in: context, name: "a", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -40)
        stageComp(in: context, name: "b", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -30)
        stageComp(in: context, name: "c", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -20)

        XCTAssertNil(resolve(in: context))
    }

    func testJobsStillOnTheCalendarAreNeverEvidence() throws {
        let context = try makeContext()
        stageTargetDeck(in: context, areaSqFt: 400)

        // Two jobs that actually ran, three that are still somebody's plan.
        stageComp(in: context, name: "ran-a", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -40)
        stageComp(in: context, name: "ran-b", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -30)
        stageComp(in: context, name: "plan-a", areaSqFt: 400, dayCount: 5, endingDaysFromNow: 10)
        stageComp(in: context, name: "plan-b", areaSqFt: 400, dayCount: 5, endingDaysFromNow: 20)
        // Ends today: the crew is still on it, so it has not run yet either.
        stageComp(in: context, name: "running", areaSqFt: 400, dayCount: 5, endingDaysFromNow: 0)

        // Five in-band jobs on file, only two of them finished. Echoing plans
        // back would let one optimistic estimate become the company's standard.
        XCTAssertNil(resolve(in: context))

        // A third finished job is what unlocks it — and the answer comes from
        // the finished three alone, never the five-day plans.
        stageComp(in: context, name: "ran-c", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -20)
        XCTAssertEqual(resolve(in: context), 2)
    }

    func testCancelledAndDeletedJobsAreNotEvidence() throws {
        let context = try makeContext()
        stageTargetDeck(in: context, areaSqFt: 400)

        stageComp(in: context, name: "ran", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -40)
        // A cancelled job never happened; its dates are a plan nobody ran.
        stageComp(
            in: context,
            name: "cancelled",
            areaSqFt: 400,
            dayCount: 2,
            endingDaysFromNow: -30,
            status: .cancelled
        )
        // A soft-deleted row is a tombstone, not a job.
        stageComp(
            in: context,
            name: "deleted",
            areaSqFt: 400,
            dayCount: 2,
            endingDaysFromNow: -20,
            taskDeletedAt: daysFromNow(-5)
        )

        XCTAssertNil(resolve(in: context))
    }

    func testDeletedDesignsAreIgnored() throws {
        let context = try makeContext()
        stageTargetDeck(in: context, areaSqFt: 400)

        stageComp(in: context, name: "a", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -40)
        stageComp(in: context, name: "b", areaSqFt: 400, dayCount: 2, endingDaysFromNow: -30)
        // This job ran, but its only drawing has been deleted — so there is no
        // size to band it by, and it drops out of the pool.
        stageComp(
            in: context,
            name: "c",
            areaSqFt: 400,
            dayCount: 2,
            endingDaysFromNow: -20,
            designDeletedAt: daysFromNow(-5)
        )

        XCTAssertNil(resolve(in: context))
    }

    func testTheLatestDesignWinsPerProject() throws {
        // Each comp project was drawn as a barn first and corrected to a 400
        // sqft deck later. Reading the latest drawing puts all three in band.
        let corrected = try makeContext()
        stageTargetDeck(in: corrected, areaSqFt: 400)
        for (index, name) in ["a", "b", "c"].enumerated() {
            stageComp(
                in: corrected,
                name: name,
                areaSqFt: 400,
                dayCount: 2,
                endingDaysFromNow: -40 + index,
                supersededAreaSqFt: 900
            )
        }
        XCTAssertEqual(resolve(in: corrected), 2)

        // The mirror image: each project's latest word is that it IS a barn, so
        // nothing is in band and there is no answer to give.
        let enlarged = try makeContext()
        stageTargetDeck(in: enlarged, areaSqFt: 400)
        for (index, name) in ["a", "b", "c"].enumerated() {
            stageComp(
                in: enlarged,
                name: name,
                areaSqFt: 900,
                dayCount: 2,
                endingDaysFromNow: -40 + index,
                supersededAreaSqFt: 400
            )
        }
        XCTAssertNil(resolve(in: enlarged))
    }

    func testAnotherCompanysAndAnotherTypesHistoryAreInvisible() throws {
        let otherCompany = try makeContext()
        stageTargetDeck(in: otherCompany, areaSqFt: 400)
        for (index, name) in ["a", "b", "c"].enumerated() {
            stageComp(
                in: otherCompany,
                name: name,
                areaSqFt: 400,
                dayCount: 2,
                endingDaysFromNow: -40 + index,
                taskCompanyId: "company-2"
            )
        }
        XCTAssertNil(resolve(in: otherCompany))

        let otherType = try makeContext()
        stageTargetDeck(in: otherType, areaSqFt: 400)
        for (index, name) in ["a", "b", "c"].enumerated() {
            stageComp(
                in: otherType,
                name: name,
                areaSqFt: 400,
                dayCount: 2,
                endingDaysFromNow: -40 + index,
                taskTypeId: "type-framing"
            )
        }
        // Framing days say nothing about decking days.
        XCTAssertNil(resolve(in: otherType))
    }

    func testAPriorJobOnThisVerySameDeckIsTheBestCompOfAll() throws {
        let context = try makeContext()
        stageTargetDeck(in: context, areaSqFt: 400)

        // Three finished runs of this task type on the target project itself.
        // Identical deck, so identically in band — nothing about sharing the
        // project disqualifies them, and the closest comp there is is one.
        let offsets = [-60, -45, -30]
        for (index, offset) in offsets.enumerated() {
            stageJob(
                in: context,
                projectId: targetProjectId,
                idSuffix: "self-\(index)",
                dayCount: index == 2 ? 3 : 2,
                endingDaysFromNow: offset
            )
        }

        XCTAssertEqual(resolve(in: context), 2)
    }

    // MARK: - Suggested span (SchedulingEngine.spanEnd)
    //
    // The span walk lives on `SchedulingEngine`, beside the weekend rule it
    // shares, but it exists for the chip tap — so its coverage sits here with
    // the rest of the feature rather than a file away from it.

    func testSuggestedSpanStepsOverTheWeekendOnlyWhenTheCompanyDoes() {
        let friday = nextFriday(from: now)
        let saturday = calendar.date(byAdding: .day, value: 1, to: friday)!
        let monday = calendar.date(byAdding: .day, value: 3, to: friday)!
        XCTAssertTrue(calendar.isDateInWeekend(saturday), "fixture must be a weekend day")
        XCTAssertFalse(calendar.isDateInWeekend(monday), "fixture must be a working day")

        // Two days of work from Friday: the crew is back Monday, so that is
        // when the job ends. A calendar square is not a working day.
        XCTAssertEqual(
            SchedulingEngine.spanEnd(start: friday, days: 2, skipWeekends: true, calendar: calendar),
            monday
        )
        // A company that works weekends means exactly that.
        XCTAssertEqual(
            SchedulingEngine.spanEnd(start: friday, days: 2, skipWeekends: false, calendar: calendar),
            saturday
        )
    }

    func testASingleDaySpanNeverLeavesItsOwnDay() {
        let friday = nextFriday(from: now)
        XCTAssertEqual(
            SchedulingEngine.spanEnd(start: friday, days: 1, skipWeekends: true, calendar: calendar),
            friday
        )
        XCTAssertEqual(
            SchedulingEngine.spanEnd(start: friday, days: 1, skipWeekends: false, calendar: calendar),
            friday
        )
        // A nonsense length holds its day rather than walking backwards.
        XCTAssertEqual(
            SchedulingEngine.spanEnd(start: friday, days: 0, skipWeekends: true, calendar: calendar),
            friday
        )
    }

    func testALongerSpanKeepsSkippingEveryWeekendItCrosses() {
        let monday = calendar.date(byAdding: .day, value: 3, to: nextFriday(from: now))!
        XCTAssertFalse(calendar.isDateInWeekend(monday), "fixture must be a working day")

        // A full working week ends Friday.
        XCTAssertEqual(
            SchedulingEngine.spanEnd(start: monday, days: 5, skipWeekends: true, calendar: calendar),
            calendar.date(byAdding: .day, value: 4, to: monday)!
        )
        // A sixth working day is the following Monday, not Saturday.
        XCTAssertEqual(
            SchedulingEngine.spanEnd(start: monday, days: 6, skipWeekends: true, calendar: calendar),
            calendar.date(byAdding: .day, value: 7, to: monday)!
        )
        // Straight calendar days when the company works through.
        XCTAssertEqual(
            SchedulingEngine.spanEnd(start: monday, days: 6, skipWeekends: false, calendar: calendar),
            calendar.date(byAdding: .day, value: 5, to: monday)!
        )
    }

    // MARK: - Fixtures

    private func resolve(in context: ModelContext) -> Int? {
        ComparableJobLength.resolveSuggestedDays(
            taskTypeId: deckingTypeId,
            projectId: targetProjectId,
            companyId: companyId,
            in: context,
            calendar: calendar,
            now: now
        )
    }

    /// The first Friday at or after `date`, so the weekend assertions are about
    /// the rule rather than about one page of one calendar.
    private func nextFriday(from date: Date) -> Date {
        var day = calendar.startOfDay(for: date)
        while calendar.component(.weekday, from: day) != 6 {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return day
    }

    /// A rectangular deck of a known real-world size, serialized exactly the
    /// way the builder saves one. One canvas point per inch, so the drawing's
    /// numbers are the deck's numbers: 240 × 240 is 20' × 20', i.e. 400 sqft.
    private func rectangleDrawingJSON(areaSqFt: Double) -> String {
        let width = 240.0
        let depth = areaSqFt * 144.0 / width
        let corners: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: width, y: 0),
            CGPoint(x: width, y: depth),
            CGPoint(x: 0, y: depth)
        ]

        var drawing = DeckDrawingData()
        drawing.scaleFactor = 1
        drawing.vertices = corners.enumerated().map { index, point in
            DeckVertex(id: "v\(index)", position: point)
        }
        drawing.edges = corners.indices.map { index in
            DeckEdge(
                id: "e\(index)",
                startVertexId: "v\(index)",
                endVertexId: "v\((index + 1) % corners.count)"
            )
        }
        return drawing.toJSON()
    }

    private func stageTargetDeck(in context: ModelContext, areaSqFt: Double) {
        stageDesign(
            in: context,
            id: "design-target",
            projectId: targetProjectId,
            areaSqFt: areaSqFt,
            updatedAt: daysFromNow(-1)
        )
    }

    /// One finished job of this type on its own project, with a deck to size it
    /// by. `supersededAreaSqFt` adds an older drawing on the same project so
    /// latest-wins can be put on trial.
    private func stageComp(
        in context: ModelContext,
        name: String,
        areaSqFt: Double,
        dayCount: Int,
        endingDaysFromNow: Int,
        status: TaskStatus = .completed,
        taskCompanyId: String? = nil,
        taskTypeId: String? = nil,
        taskDeletedAt: Date? = nil,
        designDeletedAt: Date? = nil,
        supersededAreaSqFt: Double? = nil
    ) {
        let projectId = "project-\(name)"

        if let supersededAreaSqFt {
            stageDesign(
                in: context,
                id: "design-\(name)-old",
                projectId: projectId,
                areaSqFt: supersededAreaSqFt,
                updatedAt: daysFromNow(-365)
            )
        }
        stageDesign(
            in: context,
            id: "design-\(name)",
            projectId: projectId,
            areaSqFt: areaSqFt,
            updatedAt: daysFromNow(-90),
            deletedAt: designDeletedAt
        )

        stageJob(
            in: context,
            projectId: projectId,
            idSuffix: name,
            dayCount: dayCount,
            endingDaysFromNow: endingDaysFromNow,
            status: status,
            taskCompanyId: taskCompanyId,
            taskTypeId: taskTypeId,
            deletedAt: taskDeletedAt
        )
    }

    private func stageJob(
        in context: ModelContext,
        projectId: String,
        idSuffix: String,
        dayCount: Int,
        endingDaysFromNow: Int,
        status: TaskStatus = .completed,
        taskCompanyId: String? = nil,
        taskTypeId: String? = nil,
        deletedAt: Date? = nil
    ) {
        let task = ProjectTask(
            id: "task-\(idSuffix)",
            projectId: projectId,
            taskTypeId: taskTypeId ?? deckingTypeId,
            companyId: taskCompanyId ?? companyId,
            status: status
        )
        let end = daysFromNow(endingDaysFromNow)
        task.endDate = end
        task.startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: end)!
        task.duration = dayCount
        task.deletedAt = deletedAt
        context.insert(task)
    }

    @discardableResult
    private func stageDesign(
        in context: ModelContext,
        id: String,
        projectId: String,
        areaSqFt: Double,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) -> DeckDesign {
        let design = DeckDesign(
            id: id,
            companyId: companyId,
            projectId: projectId,
            title: "Deck",
            drawingDataJSON: rectangleDrawingJSON(areaSqFt: areaSqFt)
        )
        design.updatedAt = updatedAt
        design.deletedAt = deletedAt
        context.insert(design)
        return design
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            SyncOperation.self,
            CalendarUserEvent.self,
            DeckDesign.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)]
        )
        return ModelContext(container)
    }
}
