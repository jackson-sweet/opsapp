//
//  ScheduleDragSessionHoverTests.swift
//  OPSTests
//
//  Hover ownership and deferred-end behavior for the Schedule's reschedule drag.
//
//  The two deferred-end cases used to arm a 10ms delay, sleep 30ms on the wall
//  clock, and assert — which is a race the machine wins. Under full-suite load
//  the deferred task had not run when the 30ms elapsed and the clear assertion
//  failed (bug e0f6915d; proven: failed in a loaded full-suite run, passed 6/6
//  when the suite ran alone). `ScheduleDragSession` now takes an injectable
//  sleeper, so these tests decide when the delay "elapses" and then await the
//  exact task instead of sleeping past it and hoping. No wall-clock waits
//  remain in this file — the same seam, for the same reason, that de-flaked
//  InboundChangeRouterTests.
//

import XCTest
@testable import OPS

/// Hand-fired stand-in for the deferred end's sleep. Records what delay the
/// session asked for, holds the deferred task suspended until the test says the
/// delay is over, and never consults a real clock.
@MainActor
private final class ManualDeferredEndClock {
    private(set) var requestedDelays: [Duration] = []
    private var sleeper: CheckedContinuation<Void, Never>?

    /// True once the deferred task has actually reached the sleep.
    var isArmed: Bool { sleeper != nil }

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            requestedDelays.append(duration)
            sleeper = continuation
        }
    }

    /// The delay elapses. A no-op when nothing is armed — callers gate on
    /// `isArmed` first, so a silent no-op here cannot mask a missed arm.
    func elapse() {
        let continuation = sleeper
        sleeper = nil
        continuation?.resume()
    }
}

final class ScheduleDragSessionHoverTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @MainActor
    func testRefreshHoverUpdatesDateTargetAndReportsChange() {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let source = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)

        session.begin(payload)
        let changed = session.refreshHover(day: monday, source: source, calendar: calendar)

        XCTAssertTrue(changed)
        XCTAssertEqual(session.hoverSource, source)
        XCTAssertTrue(calendar.isDate(session.hoveredDate!, inSameDayAs: monday))
    }

    @MainActor
    func testRefreshHoverDoesNotReportChangeForSameDate() {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let source = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)

        session.begin(payload)
        _ = session.refreshHover(day: monday, source: source, calendar: calendar)
        let changed = session.refreshHover(day: monday, source: source, calendar: calendar)

        XCTAssertFalse(changed)
    }

    @MainActor
    func testOldDayExitDoesNotClearNewDayHover() {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let tuesday = makeDate(2026, 6, 23)
        let mondaySource = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)
        let tuesdaySource = ScheduleDragHoverSource.dayCell(for: tuesday, calendar: calendar)

        session.begin(payload)
        session.updateHover(day: monday, source: mondaySource)
        session.updateHover(day: tuesday, source: tuesdaySource)
        session.clearHover(source: mondaySource)

        XCTAssertEqual(session.hoverSource, tuesdaySource)
        XCTAssertTrue(calendar.isDate(session.hoveredDate!, inSameDayAs: tuesday))
    }

    @MainActor
    func testDayExitDoesNotClearWeekEdgeHoverForSameDate() {
        let session = ScheduleDragSession()
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let daySource = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)
        let edgeSource = ScheduleDragHoverSource.weekRowEdge(.previous)

        session.begin(payload)
        session.updateHover(day: monday, source: daySource)
        session.updateHover(day: monday, source: edgeSource)
        session.clearHover(source: daySource)

        XCTAssertEqual(session.hoverSource, edgeSource)
        XCTAssertTrue(calendar.isDate(session.hoveredDate!, inSameDayAs: monday))
    }

    @MainActor
    func testDeferredPreviewEndDoesNotClearWhileHoveringTarget() async {
        let clock = ManualDeferredEndClock()
        let session = ScheduleDragSession(sleep: { await clock.sleep($0) })
        let payload = makePayload()
        let monday = makeDate(2026, 6, 22)
        let source = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)

        session.begin(payload)
        session.updateHover(day: monday, source: source)
        session.endWhenOffGrid(after: .milliseconds(10))

        await awaitArmed(clock)
        XCTAssertEqual(clock.requestedDelays, [.milliseconds(10)])
        clock.elapse()
        await session.deferredEndTask?.value

        XCTAssertEqual(session.active?.id, payload.id)
        XCTAssertEqual(session.hoverSource, source)
        XCTAssertTrue(calendar.isDate(session.hoveredDate!, inSameDayAs: monday))
    }

    @MainActor
    func testDeferredPreviewEndClearsWhenNoTargetOwnsHover() async {
        let clock = ManualDeferredEndClock()
        let session = ScheduleDragSession(sleep: { await clock.sleep($0) })

        session.begin(makePayload())
        session.endWhenOffGrid(after: .milliseconds(10))

        await awaitArmed(clock)
        XCTAssertEqual(clock.requestedDelays, [.milliseconds(10)])
        clock.elapse()
        await session.deferredEndTask?.value

        XCTAssertNil(session.active)
        XCTAssertNil(session.hoveredDate)
        XCTAssertNil(session.hoverSource)
    }

    /// A re-lift of the SAME item cancels the pending end. `begin` returns early
    /// for a repeat id without touching `active` or `hoverSource`, so without the
    /// cancellation check the resumed task would find exactly the state it was
    /// told to clear and wipe a live drag.
    @MainActor
    func testCancelledDeferredEndDoesNotClearAReliftedDrag() async {
        let clock = ManualDeferredEndClock()
        let session = ScheduleDragSession(sleep: { await clock.sleep($0) })
        let payload = makePayload()

        session.begin(payload)
        session.endWhenOffGrid(after: .milliseconds(10))
        await awaitArmed(clock)

        let pending = session.deferredEndTask
        session.begin(payload)          // same id — cancels, changes nothing else
        clock.elapse()
        await pending?.value

        XCTAssertEqual(session.active?.id, payload.id)
    }

    // MARK: - Bug 4baf3104 — the drag preview's lifecycle must not own the highlight

    /// The reported symptom: the selection haptic fired on every day cell while no
    /// highlight ever appeared. The haptic only needs the hover to change; the
    /// highlight used to also need `active`, which the preview teardown had cleared.
    /// A hover on a private-UTType target is itself proof the drag is live, so it
    /// alone must project a span.
    @MainActor
    func testHoverAloneProjectsASpanWhenTheLiftNeverArmedTheSession() {
        let session = ScheduleDragSession()
        let monday = makeDate(2026, 6, 22)
        let tuesday = makeDate(2026, 6, 23)

        // No `begin` — exactly the state a drag whose preview never appeared is in.
        session.updateHover(day: monday, source: .dayCell(for: monday, calendar: calendar))

        XCTAssertTrue(session.isDragInFlight)
        XCTAssertTrue(session.isInProjectedSpan(monday))
        // Span length is unknown, so it falls back to one day rather than guessing.
        XCTAssertEqual(session.projectedSpanDays, 1)
        XCTAssertFalse(session.isInProjectedSpan(tuesday))
    }

    /// A drag that travels off-grid long enough for the deferred end to fire must
    /// come back with its full span intact — the stand-down drops the visual state
    /// but keeps what was lifted, and the next hover re-arms from it synchronously.
    @MainActor
    func testHoverReArmsTheFullSpanAfterAnOffGridStandDown() async {
        let clock = ManualDeferredEndClock()
        let session = ScheduleDragSession(sleep: { await clock.sleep($0) })
        let payload = makePayload(durationDays: 3)
        let monday = makeDate(2026, 6, 22)
        let thursday = makeDate(2026, 6, 25)
        let mondaySource = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)

        session.begin(payload)
        session.updateHover(day: monday, source: mondaySource)

        // Finger leaves the grid; the preview teardown's deferred end elapses.
        session.clearHover(source: mondaySource)
        await awaitArmed(clock)
        clock.elapse()
        await session.deferredEndTask?.value

        XCTAssertNil(session.active)
        XCTAssertFalse(session.isDragInFlight, "an abandoned drag must give the badges their hit-testing back")
        XCTAssertEqual(session.lifted?.id, payload.id, "the stand-down must not forget what is in the operator's hand")

        // Finger comes back over the grid — same gesture, so the exact span returns.
        session.updateHover(day: monday, source: mondaySource)

        XCTAssertEqual(session.active?.id, payload.id)
        XCTAssertTrue(session.isDragInFlight)
        XCTAssertEqual(session.projectedSpanDays, 3)
        XCTAssertTrue(session.isInProjectedSpan(makeDate(2026, 6, 24)))
        XCTAssertFalse(session.isInProjectedSpan(thursday))
    }

    /// A committed drop is the end of the gesture: nothing may re-arm from it.
    @MainActor
    func testCommittedDropForgetsTheLift() {
        let session = ScheduleDragSession()
        let payload = makePayload(durationDays: 3)
        let monday = makeDate(2026, 6, 22)
        let source = ScheduleDragHoverSource.dayCell(for: monday, calendar: calendar)

        session.begin(payload)
        session.updateHover(day: monday, source: source)
        session.end()

        XCTAssertNil(session.lifted)
        XCTAssertFalse(session.isDragInFlight)

        // A later hover cannot resurrect the finished drag's span.
        session.updateHover(day: monday, source: source)
        XCTAssertNil(session.active)
        XCTAssertEqual(session.projectedSpanDays, 1)
    }

    /// The bounded correction path: the payload the system hands us on target entry
    /// wins, so a drag that never armed the session still gets its real span.
    @MainActor
    func testAdoptDraggedPayloadCorrectsTheSpanWhileHovering() {
        let session = ScheduleDragSession()
        let monday = makeDate(2026, 6, 22)

        session.updateHover(day: monday, source: .dayCell(for: monday, calendar: calendar))
        XCTAssertEqual(session.projectedSpanDays, 1)

        session.adoptDraggedPayload(makePayload(durationDays: 4))

        XCTAssertEqual(session.projectedSpanDays, 4)
        XCTAssertTrue(session.isInProjectedSpan(makeDate(2026, 6, 25)))
    }

    /// The adopt is asynchronous — it must never resurrect a drag that has already
    /// left the grid (or committed) by the time the item provider resolves.
    @MainActor
    func testAdoptDraggedPayloadIsIgnoredWhenNoTargetOwnsHover() {
        let session = ScheduleDragSession()

        session.adoptDraggedPayload(makePayload(durationDays: 4))

        XCTAssertNil(session.active)
        XCTAssertNil(session.lifted)
        XCTAssertFalse(session.isDragInFlight)
    }

    // MARK: - Helpers

    /// Suspends until the deferred end has reached its sleep, on scheduler turns
    /// rather than wall time — nothing here gets slower under machine load. The
    /// cap is a loud backstop for a deferred end that never arms at all, not a
    /// timeout the assertion depends on.
    @MainActor
    private func awaitArmed(
        _ clock: ManualDeferredEndClock,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if clock.isArmed { return }
            await Task.yield()
        }
        XCTFail("Deferred end never reached its sleep", file: file, line: line)
    }

    private func makePayload(durationDays: Int = 1) -> RescheduleDragPayload {
        RescheduleDragPayload(
            id: "task-1",
            kind: .task,
            title: "Install rail",
            durationDays: durationDays,
            startEpoch: makeDate(2026, 6, 22).timeIntervalSince1970
        )
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }
}
