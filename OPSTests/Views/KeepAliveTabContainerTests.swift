//
//  KeepAliveTabContainerTests.swift
//  OPSTests
//
//  Pins the three contracts MainTabView's keep-alive tab container rests on.
//  The container itself cannot be hosted headlessly — it needs DataController,
//  AppState, PermissionStore, LocationManager and a live SwiftData stack — so
//  these tests exercise the shared machinery it is built out of, using the REAL
//  `\.isActiveTab` key, the REAL `onReceiveWhileActive` modifier and the REAL
//  `AppHeaderHeightKey`, wired exactly as the container wires them:
//
//    1. `\.isActiveTab` defaults to true, so everything mounted outside the
//       container (sheets, pushed screens, previews) behaves as it always has.
//    2. A slot that is offset off-screen and marked inactive keeps its subtree
//       and therefore its `@State` — that is the whole point of keep-alive, and
//       the thing the old `.id(selectedTab)` router destroyed on every switch.
//    3. Several `AppHeader`-shaped emitters are alive at once now, and the key
//       reduces with `max`. Only the ACTIVE one may report its real height, or
//       the tallest header ever mounted pins the status band for the session.
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

/// Shared, test-owned record of what the hosted slots did. A class so the
/// SwiftUI value types can report into it without owning it.
@MainActor
private final class SlotLedger {
    /// Live `onAppear` / `onDisappear` balance per slot.
    private(set) var mounted: Set<Int> = []
    /// Every `onAppear` ever seen, in order — a re-mount shows up as a repeat.
    private(set) var appearances: [Int] = []
    /// Notifications a slot actually handled.
    private(set) var handled: [Int] = []

    func didAppear(_ slot: Int) {
        mounted.insert(slot)
        appearances.append(slot)
    }

    func didDisappear(_ slot: Int) {
        mounted.remove(slot)
    }

    func didHandle(_ slot: Int) {
        handled.append(slot)
    }
}

private extension Notification.Name {
    static let keepAliveTabProbe = Notification.Name("KeepAliveTabContainerTests.probe")
}

/// One slot: carries `@State` the test can mutate, reports its lifecycle, and
/// answers a broadcast through the real `onReceiveWhileActive` gate.
private struct ProbeSlot: View {
    let index: Int
    let ledger: SlotLedger
    /// Bumped from outside via `counters`; held in `@State` so its survival
    /// proves the subtree was never rebuilt.
    @State private var localCounter = 0
    @Binding var counters: [Int: Int]

    var body: some View {
        Color.clear
            .onAppear {
                ledger.didAppear(index)
                // Re-seeded only on a genuine (re)mount — if the slot were torn
                // down and rebuilt this would erase the test's mutation.
                localCounter = 0
                counters[index] = 0
            }
            .onDisappear { ledger.didDisappear(index) }
            .onReceiveWhileActive(NotificationCenter.default.publisher(for: .keepAliveTabProbe)) { _ in
                ledger.didHandle(index)
            }
            .onChange(of: counters[index] ?? 0) { _, newValue in
                localCounter = newValue
            }
            .accessibilityLabel("slot-\(index)-\(localCounter)")
    }
}

/// The container mechanics MainTabView uses, reduced to what is testable:
/// mount on first visit, never unmount, park inactive slots one width to the
/// side, and publish `\.isActiveTab` per slot.
private struct ProbeContainer: View {
    let ledger: SlotLedger
    @Binding var selected: Int
    @Binding var mounted: Set<Int>
    @Binding var counters: [Int: Int]
    let width: CGFloat

    var body: some View {
        ZStack {
            ForEach(mounted.sorted(), id: \.self) { index in
                ProbeSlot(index: index, ledger: ledger, counters: $counters)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.isActiveTab, index == selected)
                    .offset(x: index == selected ? 0 : (index < selected ? -width : width))
                    .allowsHitTesting(index == selected)
                    .accessibilityHidden(index != selected)
            }
        }
        .frame(width: width, height: 200)
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

/// Two tab roots, both mounted, both using the REAL `trackScreen` modifier.
/// Only the active one may claim the bug-report breadcrumb.
private struct ScreenTrackingHarness: View {
    @Binding var selected: Int
    let names: [Int: String]

    var body: some View {
        ZStack {
            ForEach(names.keys.sorted(), id: \.self) { index in
                Color.clear
                    .trackScreen(names[index] ?? "")
                    .environment(\.isActiveTab, index == selected)
            }
        }
        .frame(width: 393, height: 200)
    }
}

private struct HeaderBandHarness: View {
    @Binding var selected: Int
    /// index -> header height, all mounted at once.
    let heights: [Int: CGFloat]
    let report: (CGFloat) -> Void

    var body: some View {
        ZStack {
            ForEach(heights.keys.sorted(), id: \.self) { index in
                VStack {
                    HeaderProbe(height: heights[index] ?? 0)
                    Spacer()
                }
                .environment(\.isActiveTab, index == selected)
            }
        }
        .frame(width: 393, height: 400)
        .onPreferenceChange(AppHeaderHeightKey.self) { report($0) }
    }
}

@MainActor
final class KeepAliveTabContainerTests: XCTestCase {

    /// iPhone 17 logical width (pt) — the slide distance the container parks at.
    private let deviceWidth: CGFloat = 393

    // MARK: - Hosting

    /// Hosts `view` in the app host's key window, restoring the original root
    /// on teardown. Returns the controller so the test can drive updates.
    private func host<V: View>(_ view: V) throws -> UIHostingController<V> {
        let window = try AppHostWindow.acquire()
        let previousRoot = window.rootViewController
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: deviceWidth, height: 400)
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

    // MARK: - 1. Environment default

    func testIsActiveTabDefaultsToTrueOutsideTheContainer() throws {
        var observed: Bool?
        _ = try host(ActivationReader { observed = $0 })
        settle(until: { observed != nil }, "ActivationReader must report")
        XCTAssertEqual(
            observed, true,
            "Anything mounted outside the tab container — sheets, pushed screens, previews, tests — must read as active, or every per-visit side effect silently stops firing there."
        )
    }

    func testIsActiveTabIsFalseForAParkedSlot() throws {
        var observed: [Bool] = []
        _ = try host(
            ZStack {
                ActivationReader { observed.append($0) }.environment(\.isActiveTab, true)
                ActivationReader { observed.append($0) }.environment(\.isActiveTab, false)
            }
        )
        settle(until: { observed.count == 2 }, "Both readers must report")
        XCTAssertEqual(observed.sorted(by: { $0 && !$1 }), [true, false])
    }

    // MARK: - 2. Keep-alive

    func testParkedSlotKeepsItsStateAcrossASwitch() throws {
        let ledger = SlotLedger()
        var selected = 0
        var mounted: Set<Int> = [0]
        var counters: [Int: Int] = [:]

        let controller = try host(
            ProbeContainer(
                ledger: ledger,
                selected: Binding(get: { selected }, set: { selected = $0 }),
                mounted: Binding(get: { mounted }, set: { mounted = $0 }),
                counters: Binding(get: { counters }, set: { counters = $0 }),
                width: deviceWidth
            )
        )

        settle(until: { ledger.mounted == [0] }, "Slot 0 mounts on first visit")

        // Operator does something on tab 0 that lives in view state.
        counters[0] = 7
        controller.view.setNeedsLayout()
        settle(until: { counters[0] == 7 }, "Slot 0 state accepted")

        // Switch to tab 1 (first visit → mounts) and back.
        selected = 1
        mounted.insert(1)
        controller.rootView = ProbeContainer(
            ledger: ledger,
            selected: Binding(get: { selected }, set: { selected = $0 }),
            mounted: Binding(get: { mounted }, set: { mounted = $0 }),
            counters: Binding(get: { counters }, set: { counters = $0 }),
            width: deviceWidth
        )
        controller.view.layoutIfNeeded()
        settle(until: { ledger.mounted.contains(1) }, "Slot 1 mounts on its first visit")

        XCTAssertTrue(
            ledger.mounted.contains(0),
            "Slot 0 must still be mounted while parked — an unmount here is exactly the teardown that made every tab switch cold-rebuild its whole tab."
        )
        XCTAssertEqual(
            counters[0], 7,
            "Parked slot lost its state — it was torn down and rebuilt, which is the regression this container exists to prevent."
        )
        XCTAssertEqual(
            ledger.appearances.filter { $0 == 0 }.count, 1,
            "Slot 0 appeared more than once — a re-appear means a re-mount, and every mount-once side effect (service wiring, first data load) would run again."
        )
    }

    // MARK: - 3. Broadcast gating

    func testOnlyTheActiveSlotAnswersABroadcast() throws {
        let ledger = SlotLedger()
        var selected = 0
        var mounted: Set<Int> = [0, 1]
        var counters: [Int: Int] = [:]

        func rebuild() -> ProbeContainer {
            ProbeContainer(
                ledger: ledger,
                selected: Binding(get: { selected }, set: { selected = $0 }),
                mounted: Binding(get: { mounted }, set: { mounted = $0 }),
                counters: Binding(get: { counters }, set: { counters = $0 }),
                width: deviceWidth
            )
        }

        let controller = try host(rebuild())
        settle(until: { ledger.mounted == [0, 1] }, "Both slots mount")

        NotificationCenter.default.post(name: .keepAliveTabProbe, object: nil)
        settle(until: { !ledger.handled.isEmpty }, "A slot must answer")

        XCTAssertEqual(
            ledger.handled, [0],
            "Both mounted slots answered one broadcast. `ShowCalendarTaskDetails` is answered by Home AND Schedule, so an ungated handler presents the same task twice."
        )

        selected = 1
        controller.rootView = rebuild()
        controller.view.layoutIfNeeded()
        settle(until: { true }, "flush")

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
        var reported: CGFloat = 0
        var selected = 0

        // Tab 0 has the SHORT header, tab 1 the TALL one. Both are mounted.
        let heights: [Int: CGFloat] = [0: short, 1: tall]
        let controller = try host(
            HeaderBandHarness(
                selected: Binding(get: { selected }, set: { selected = $0 }),
                heights: heights,
                report: { reported = $0 }
            )
        )
        settle(until: { reported > 0 }, "The band height must be reported")
        XCTAssertEqual(
            reported, short, accuracy: 0.5,
            "A parked tab's taller header claimed the band. With every visited tab mounted and the key reducing with `max`, that would push the sync band down the screen for the rest of the session."
        )

        selected = 1
        controller.rootView = HeaderBandHarness(
            selected: Binding(get: { selected }, set: { selected = $0 }),
            heights: heights,
            report: { reported = $0 }
        )
        controller.view.layoutIfNeeded()
        settle(until: { abs(reported - tall) < 0.5 }, "The band must follow the newly active header")
        XCTAssertEqual(reported, tall, accuracy: 0.5)
    }

    // MARK: - 5. Bug-report screen breadcrumb

    func testTheScreenBreadcrumbFollowsTheActiveTab() throws {
        let names: [Int: String] = [0: "ProbeScreenA", 1: "ProbeScreenB"]
        var selected = 0

        let controller = try host(
            ScreenTrackingHarness(
                selected: Binding(get: { selected }, set: { selected = $0 }),
                names: names
            )
        )
        settle(
            until: { BugReportCaptureService.shared.currentScreenName == "ProbeScreenA" },
            "The active tab must claim the breadcrumb on mount"
        )
        XCTAssertEqual(
            BugReportCaptureService.shared.currentScreenName, "ProbeScreenA",
            "A parked tab claimed the screen name. `trackScreen` is onAppear-based on six tab roots, so with keep-alive it fires once per mount — a bug filed later would carry the wrong screen."
        )

        selected = 1
        controller.rootView = ScreenTrackingHarness(
            selected: Binding(get: { selected }, set: { selected = $0 }),
            names: names
        )
        controller.view.layoutIfNeeded()
        settle(
            until: { BugReportCaptureService.shared.currentScreenName == "ProbeScreenB" },
            "The breadcrumb must follow the tab switch"
        )
        XCTAssertEqual(
            BugReportCaptureService.shared.currentScreenName, "ProbeScreenB",
            "The breadcrumb did not follow the switch — a bug report filed here would name the tab the operator left."
        )

        // And back, to prove it is not a one-way latch.
        selected = 0
        controller.rootView = ScreenTrackingHarness(
            selected: Binding(get: { selected }, set: { selected = $0 }),
            names: names
        )
        controller.view.layoutIfNeeded()
        settle(
            until: { BugReportCaptureService.shared.currentScreenName == "ProbeScreenA" },
            "The breadcrumb must follow every switch, not just the first"
        )
        XCTAssertEqual(BugReportCaptureService.shared.currentScreenName, "ProbeScreenA")
    }
}
#endif
