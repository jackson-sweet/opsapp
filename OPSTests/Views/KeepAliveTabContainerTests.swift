//
//  KeepAliveTabContainerTests.swift
//  OPSTests
//
//  Behavioral pins for the keep-alive tab container and the machinery the tab
//  roots hang off it. Everything here drives the REAL production types — the
//  real `KeepAliveTabContainer`, the real `\.isActiveTab` key, the real
//  `onReceiveWhileActive` modifier, the real `AppHeaderHeightKey`, the real
//  `trackScreen`. Only the tab CONTENT is a probe, because MainTabView's own
//  roots need DataController, AppState, PermissionStore, LocationManager and a
//  live SwiftData stack that cannot be stood up headlessly.
//
//  A local re-implementation of the container was tried first and deliberately
//  thrown away: a replica drifts from production wiring silently, and the
//  keep-alive and gating tests would have gone on passing against it while the
//  shipped container regressed.
//
//  Sections:
//    1. Environment — `\.isActiveTab` defaults true (so sheets, pushed screens,
//       previews and tests behave as they always have) and reads false for a
//       parked slot.
//    2. Keep-alive — a parked slot keeps its subtree, and therefore its
//       `@State`, and never re-appears. This is the whole point of the
//       container and exactly what the old `.id(selectedTab)` router destroyed.
//    3. Broadcast gating — several tabs answer the same notification now
//       (`ShowCalendarTaskDetails` is posted by Home's carousel AND the calendar
//       grids, and answered by both Home and Schedule), so only the tab on
//       screen may act.
//    4. Header band — many `AppHeader`s are alive at once and the preference
//       key reduces with `max`, so only the ACTIVE header may report its real
//       height or the tallest one ever mounted pins the band for the session.
//    5. Bug-report breadcrumb — `trackScreen` is mount-based on six tab roots,
//       so the screen a filed bug names has to follow activation, not mount.
//
//  Hosted in the app host's key window per house rules (see AppHostWindow) and
//  settled on observed state, never on a fixed sleep.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/KeepAliveTabContainerTests \
//          -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-sim
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

/// Test-owned record of what the hosted slots did. A class so the SwiftUI value
/// types can report into it without owning it.
@MainActor
private final class SlotLedger {
    /// Live `onAppear` / `onDisappear` balance per slot.
    private(set) var mounted: Set<Int> = []
    /// Every `onAppear` ever seen, in order — a rebuild shows up as a repeat.
    private(set) var appearances: [Int] = []
    /// Latest activation count each slot reported.
    private(set) var activations: [Int: Int] = [:]
    /// Notifications a slot actually handled.
    private(set) var handled: [Int] = []

    func didAppear(_ slot: Int) {
        mounted.insert(slot)
        appearances.append(slot)
    }

    func didDisappear(_ slot: Int) { mounted.remove(slot) }
    func record(slot: Int, activations count: Int) { activations[slot] = count }
    func didHandle(_ slot: Int) { handled.append(slot) }
}

private extension Notification.Name {
    static let keepAliveTabProbe = Notification.Name("KeepAliveTabContainerTests.probe")
}

/// Stand-in for a tab root: reports its lifecycle, counts its own activations
/// in `@State`, and answers a broadcast through the real activation gate.
private struct ProbeSlot: View {
    let index: Int
    let ledger: SlotLedger
    @Environment(\.isActiveTab) private var isActiveTab
    /// Survives only as long as the subtree does. A slot torn down and rebuilt
    /// silently resets this — which is the regression under test.
    @State private var activations = 0

    var body: some View {
        Color.clear
            .onAppear {
                ledger.didAppear(index)
                // Mount and activation coincide on a tab's first visit — the
                // same pattern every real tab root uses.
                if isActiveTab {
                    activations += 1
                    ledger.record(slot: index, activations: activations)
                }
            }
            .onDisappear { ledger.didDisappear(index) }
            .onChange(of: isActiveTab) { _, active in
                guard active else { return }
                activations += 1
                ledger.record(slot: index, activations: activations)
            }
            .onReceiveWhileActive(NotificationCenter.default.publisher(for: .keepAliveTabProbe)) { _ in
                ledger.didHandle(index)
            }
    }
}

/// Reads `\.isActiveTab` out of whatever environment it is placed in.
private struct ActivationReader: View {
    @Environment(\.isActiveTab) private var isActiveTab
    let report: (Bool) -> Void

    var body: some View {
        Color.clear.onAppear { report(isActiveTab) }
    }
}

/// An `AppHeader`-shaped emitter: same `.background(GeometryReader)` publish,
/// same active gate. Height is fixed so the assertion is exact.
private struct HeaderProbe: View {
    let height: CGFloat
    @Environment(\.isActiveTab) private var isActiveTab

    var body: some View {
        Color.clear
            .frame(height: height)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AppHeaderHeightKey.self,
                        value: isActiveTab ? proxy.size.height : AppHeaderHeightKey.defaultValue
                    )
                }
            )
    }
}

@MainActor
final class KeepAliveTabContainerTests: XCTestCase {

    /// iPhone 17 logical size (pt).
    private let deviceWidth: CGFloat = 393
    private let deviceHeight: CGFloat = 400

    // MARK: - Hosting

    /// Hosts `view` in the app host's key window, restoring the original root
    /// on teardown.
    private func host<V: View>(_ view: V) throws -> UIHostingController<V> {
        let window = try AppHostWindow.acquire()
        let previousRoot = window.rootViewController
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: deviceWidth, height: deviceHeight)
        window.rootViewController = controller
        window.layoutIfNeeded()
        addTeardownBlock { @MainActor in
            window.rootViewController = previousRoot
        }
        return controller
    }

    /// Pumps the run loop until `condition` holds, or fails. Never a fixed
    /// sleep — see the harness notes in TabBarSnapshotTests.
    private func settle(
        until condition: () -> Bool,
        timeout: TimeInterval = 2,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    // MARK: - Real container driver

    /// Selection state the way MainTabView keeps it: `selected`, `previous` and
    /// the mounted set all move together, in one transaction.
    private struct Selection {
        var selected = 0
        var previous = 0
        var mounted: Set<Int> = [0]

        mutating func select(_ index: Int) {
            guard index != selected else { return }
            previous = selected
            mounted.insert(index)
            selected = index
        }
    }

    /// Builds the REAL container over probe slots for the given selection.
    private func container(
        _ selection: Selection,
        ledger: SlotLedger
    ) -> some View {
        KeepAliveTabContainer(
            selected: selection.selected,
            previous: selection.previous,
            mounted: selection.mounted.sorted()
        ) { index in
            ProbeSlot(index: index, ledger: ledger)
        }
        .frame(width: deviceWidth, height: deviceHeight)
    }

    // MARK: - 1. Environment

    func testIsActiveTabDefaultsToTrueOutsideTheContainer() throws {
        var observed: Bool?
        _ = try host(ActivationReader { observed = $0 })
        settle(until: { observed != nil }, "ActivationReader must report")
        XCTAssertEqual(
            observed, true,
            "Anything mounted outside the tab container — sheets, pushed screens, previews, tests — must read as active, or every per-visit side effect silently stops firing there."
        )
    }

    func testTheContainerMarksExactlyTheSelectedSlotActive() throws {
        let ledger = SlotLedger()
        var selection = Selection()
        selection.select(1)

        _ = try host(container(selection, ledger: ledger))
        settle(until: { ledger.mounted == [0, 1] }, "Both slots must mount")

        // Only the selected slot reports an activation transition; the parked
        // one was built already inactive and never transitions.
        settle(until: { ledger.activations[1] != nil }, "The selected slot must activate")
        XCTAssertNil(
            ledger.activations[0],
            "A parked slot reported itself active — every per-visit side effect in that tab would fire off screen."
        )
    }

    // MARK: - 2. Keep-alive

    func testAParkedSlotKeepsItsStateAcrossSwitches() throws {
        let ledger = SlotLedger()
        var selection = Selection()

        let controller = try host(container(selection, ledger: ledger))
        settle(until: { ledger.mounted == [0] }, "Slot 0 mounts on first visit")

        // Two full round trips. Slot 0's counter lives in `@State`, so a slot
        // that survives reaches 3 (one mount + two returns); a slot rebuilt on
        // each return silently resets and reaches 1.
        for trip in 1...2 {
            selection.select(1)
            controller.rootView = container(selection, ledger: ledger)
            controller.view.layoutIfNeeded()
            settle(until: { ledger.activations[1] == trip }, "Slot 1 must come on screen (trip \(trip))")

            selection.select(0)
            controller.rootView = container(selection, ledger: ledger)
            controller.view.layoutIfNeeded()
            settle(until: { ledger.activations[0] == trip + 1 }, "Slot 0 must come back on screen (trip \(trip))")
        }

        XCTAssertEqual(
            ledger.activations[0], 3,
            "The parked slot lost its `@State` between visits — it was torn down and rebuilt, which is exactly the teardown this container exists to prevent."
        )
        XCTAssertTrue(
            ledger.mounted.contains(1),
            "Slot 1 must stay mounted while parked; unmounting it is the cold-rebuild the old router did on every switch."
        )
        XCTAssertEqual(
            ledger.appearances.filter { $0 == 0 }.count, 1,
            "Slot 0 appeared more than once — a re-appear means a re-mount, and every mount-once side effect (service wiring, first data load) would run again."
        )
        XCTAssertEqual(
            ledger.appearances.filter { $0 == 1 }.count, 1,
            "Slot 1 appeared more than once — it must mount on its first visit and never again."
        )
    }

    // MARK: - 3. Broadcast gating

    func testOnlyTheActiveSlotAnswersABroadcast() throws {
        let ledger = SlotLedger()
        var selection = Selection()
        selection.select(1)
        selection.select(0) // both mounted, 0 on screen

        let controller = try host(container(selection, ledger: ledger))
        settle(until: { ledger.mounted == [0, 1] }, "Both slots mount")

        NotificationCenter.default.post(name: .keepAliveTabProbe, object: nil)
        settle(until: { !ledger.handled.isEmpty }, "A slot must answer")
        XCTAssertEqual(
            ledger.handled, [0],
            "Both mounted slots answered one broadcast. `ShowCalendarTaskDetails` is answered by Home AND Schedule, so an ungated handler presents the same task twice."
        )

        selection.select(1)
        controller.rootView = container(selection, ledger: ledger)
        controller.view.layoutIfNeeded()
        settle(until: { ledger.activations[1] == 1 }, "Slot 1 must come on screen")

        NotificationCenter.default.post(name: .keepAliveTabProbe, object: nil)
        settle(until: { ledger.handled.count == 2 }, "The newly active slot must answer")
        XCTAssertEqual(ledger.handled, [0, 1])
    }

    // MARK: - 4. Header band preference

    func testAppHeaderHeightKeyReducesWithMax() {
        var value = AppHeaderHeightKey.defaultValue
        AppHeaderHeightKey.reduce(value: &value) { AppHeaderHeightKey.defaultValue + 40 }
        AppHeaderHeightKey.reduce(value: &value) { AppHeaderHeightKey.defaultValue + 10 }
        XCTAssertEqual(
            value, AppHeaderHeightKey.defaultValue + 40,
            "The key reduces with max — which is precisely why inactive headers must report the floor rather than their real height."
        )
    }

    func testActiveHeaderWinsOverATallerParkedHeader() throws {
        let short = AppHeaderHeightKey.defaultValue
        let tall = AppHeaderHeightKey.defaultValue + 60
        let heights: [Int: CGFloat] = [0: short, 1: tall]
        var reported: CGFloat = 0
        var selection = Selection()
        selection.select(1)
        selection.select(0) // both mounted, the SHORT header on screen

        func harness(_ selection: Selection) -> some View {
            KeepAliveTabContainer(
                selected: selection.selected,
                previous: selection.previous,
                mounted: selection.mounted.sorted()
            ) { index in
                VStack {
                    HeaderProbe(height: heights[index] ?? 0)
                    Spacer()
                }
            }
            .frame(width: deviceWidth, height: deviceHeight)
            .onPreferenceChange(AppHeaderHeightKey.self) { reported = $0 }
        }

        let controller = try host(harness(selection))
        settle(until: { reported > 0 }, "The band height must be reported")
        XCTAssertEqual(
            reported, short, accuracy: 0.5,
            "A parked tab's taller header claimed the band. With every visited tab mounted and the key reducing with `max`, that would push the sync band down the screen for the rest of the session."
        )

        selection.select(1)
        controller.rootView = harness(selection)
        controller.view.layoutIfNeeded()
        settle(until: { abs(reported - tall) < 0.5 }, "The band must follow the newly active header")
        XCTAssertEqual(reported, tall, accuracy: 0.5)
    }

    // MARK: - 5. Bug-report screen breadcrumb

    func testTheScreenBreadcrumbFollowsTheActiveTab() throws {
        let names: [Int: String] = [0: "ProbeScreenA", 1: "ProbeScreenB"]
        var selection = Selection()

        func harness(_ selection: Selection) -> some View {
            KeepAliveTabContainer(
                selected: selection.selected,
                previous: selection.previous,
                mounted: selection.mounted.sorted()
            ) { index in
                Color.clear.trackScreen(names[index] ?? "")
            }
            .frame(width: deviceWidth, height: deviceHeight)
        }

        let controller = try host(harness(selection))
        settle(
            until: { BugReportCaptureService.shared.currentScreenName == "ProbeScreenA" },
            "The active tab must claim the breadcrumb on mount"
        )

        // Switch, and back, so this cannot pass as a one-way latch.
        for expected in ["ProbeScreenB", "ProbeScreenA"] {
            selection.select(expected == "ProbeScreenB" ? 1 : 0)
            controller.rootView = harness(selection)
            controller.view.layoutIfNeeded()
            settle(
                until: { BugReportCaptureService.shared.currentScreenName == expected },
                "The breadcrumb must follow every switch"
            )
            XCTAssertEqual(
                BugReportCaptureService.shared.currentScreenName, expected,
                "The breadcrumb did not follow the switch. `trackScreen` is onAppear-based on six tab roots, so with keep-alive a bug filed here would name whichever tab the operator opened first."
            )
        }
    }
}
#endif
