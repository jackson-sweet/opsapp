//
//  InventoryModeTests.swift
//  OPSTests
//
//  Phase 6 inventory-mode toggle: DTO parsing, off-confirmation gate, and
//  on/off commit behavior.
//

import XCTest
@testable import OPS

final class InventoryModeTests: XCTestCase {

    // MARK: - Mode parsing

    func testInventoryModeParsesServerValues() {
        XCTAssertEqual(InventoryMode(serverValue: "tracked"), .tracked)
        XCTAssertEqual(InventoryMode(serverValue: "TRACKED"), .tracked)
        XCTAssertEqual(InventoryMode(serverValue: "off"), .off)
        // Unknown and nil must resolve to off — never silently enable tracking.
        XCTAssertEqual(InventoryMode(serverValue: "garbage"), .off)
        XCTAssertEqual(InventoryMode(serverValue: nil), .off)
        XCTAssertTrue(InventoryMode.tracked.isTracked)
        XCTAssertFalse(InventoryMode.off.isTracked)
    }

    // MARK: - DTO decoding against the live RPC/table shape

    func testSetInventoryModeResponseDecodesLiveRPCShape() throws {
        let json = """
        {
          "ok": true,
          "company_id": "company-1",
          "inventory_mode": "off",
          "previous_inventory_mode": "tracked",
          "updated_by": "user-1",
          "released_demands": 3,
          "release_snapshots": 2
        }
        """
        let dto = try JSONDecoder().decode(
            SetInventoryModeResponseDTO.self,
            from: Data(json.utf8)
        )
        XCTAssertTrue(dto.ok)
        XCTAssertEqual(dto.mode, .off)
        XCTAssertEqual(dto.previousMode, .tracked)
        XCTAssertEqual(dto.releasedDemands, 3)
        XCTAssertEqual(dto.releaseSnapshots, 2)
    }

    func testCompanyInventorySettingsDecodesLiveTableShape() throws {
        let json = """
        {
          "company_id": "company-1",
          "inventory_mode": "tracked",
          "enabled_at": "2026-05-29T00:00:00Z",
          "disabled_at": null,
          "updated_by": "user-1",
          "created_at": "2026-05-29T00:00:00Z",
          "updated_at": "2026-05-29T00:00:00Z"
        }
        """
        let dto = try JSONDecoder().decode(
            CompanyInventorySettingsDTO.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(dto.mode, .tracked)
        XCTAssertNil(dto.disabledAt)
    }

    // MARK: - View model toggle behavior

    @MainActor
    func testTurningOnAppliesImmediatelyWithoutConfirmation() async {
        let client = StubInventoryModeClient(initialMode: .off)
        let vm = InventoryModeViewModel(client: client)
        await vm.load()
        XCTAssertEqual(vm.mode, .off)

        vm.handleToggle(requestedOn: true)
        await vm.waitUntilIdle()

        XCTAssertFalse(vm.showingDisableConfirmation, "Turning on must not prompt confirmation.")
        XCTAssertEqual(client.lastSetMode, .tracked)
        XCTAssertEqual(vm.mode, .tracked)
    }

    @MainActor
    func testTurningOffRoutesThroughConfirmationBeforeCommitting() async {
        let client = StubInventoryModeClient(initialMode: .tracked)
        let vm = InventoryModeViewModel(client: client)
        await vm.load()

        vm.handleToggle(requestedOn: false)

        XCTAssertTrue(vm.showingDisableConfirmation, "Turning off must prompt confirmation first.")
        XCTAssertNil(client.lastSetMode, "No write may happen before the user confirms.")
        XCTAssertEqual(vm.mode, .tracked, "Mode stays tracked until confirmed.")
    }

    @MainActor
    func testConfirmingDisableCommitsOff() async {
        let client = StubInventoryModeClient(initialMode: .tracked)
        let vm = InventoryModeViewModel(client: client)
        await vm.load()

        vm.handleToggle(requestedOn: false)
        vm.confirmDisable()
        await vm.waitUntilIdle()

        XCTAssertFalse(vm.showingDisableConfirmation)
        XCTAssertEqual(client.lastSetMode, .off)
        XCTAssertEqual(vm.mode, .off)
    }

    @MainActor
    func testCancellingDisableLeavesTrackingOn() async {
        let client = StubInventoryModeClient(initialMode: .tracked)
        let vm = InventoryModeViewModel(client: client)
        await vm.load()

        vm.handleToggle(requestedOn: false)
        vm.cancelDisable()

        XCTAssertFalse(vm.showingDisableConfirmation)
        XCTAssertNil(client.lastSetMode)
        XCTAssertEqual(vm.mode, .tracked)
    }

    @MainActor
    func testWriteFailureSurfacesErrorAndReReadsServerTruth() async {
        let client = StubInventoryModeClient(initialMode: .off)
        client.failNextSet = true
        let vm = InventoryModeViewModel(client: client)
        await vm.load()

        vm.handleToggle(requestedOn: true)
        await vm.waitUntilIdle()

        XCTAssertNotNil(vm.actionError, "A failed write must surface an error.")
        // After failure the VM re-reads — stub still reports the original off mode.
        XCTAssertEqual(vm.mode, .off)
    }

    // MARK: - Read resilience (retry)

    @MainActor
    func testReadFailureLeavesControlNonInteractive() async {
        // A failed read must NOT enable blind toggling while the mode is unknown.
        let client = StubInventoryModeClient(initialMode: .tracked)
        client.failNextFetch = true
        let vm = InventoryModeViewModel(client: client)
        await vm.load()

        XCTAssertEqual(vm.loadState, .failed("read failed"))
        XCTAssertFalse(vm.isInteractive, "A failed read must leave the toggle locked.")
    }

    @MainActor
    func testRetryAfterReadFailureRecoversToLoaded() async {
        // RETRY re-runs load(); a transient read failure must not brick the
        // control. After one failed fetch the next load() succeeds and the
        // toggle becomes interactive again.
        let client = StubInventoryModeClient(initialMode: .tracked)
        client.failNextFetch = true
        let vm = InventoryModeViewModel(client: client)

        await vm.load()
        XCTAssertEqual(vm.loadState, .failed("read failed"))
        XCTAssertFalse(vm.isInteractive)

        // Simulate the RETRY button: re-run load() against a now-healthy read.
        await vm.load()

        XCTAssertEqual(vm.loadState, .loaded, "RETRY must recover to .loaded.")
        XCTAssertTrue(vm.isInteractive, "After a successful retry the toggle unlocks.")
        XCTAssertEqual(vm.mode, .tracked, "Recovered mode reflects server truth.")
    }
}

// MARK: - Test double

@MainActor
private final class StubInventoryModeClient: InventoryModeClient {
    private(set) var fetchedMode: InventoryMode
    private(set) var lastSetMode: InventoryMode?
    var failNextSet = false
    var failNextFetch = false

    init(initialMode: InventoryMode) {
        self.fetchedMode = initialMode
    }

    func fetchInventoryMode() async throws -> InventoryMode {
        if failNextFetch {
            failNextFetch = false
            throw NSError(
                domain: "test",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "read failed"]
            )
        }
        return fetchedMode
    }

    func setInventoryMode(_ mode: InventoryMode) async throws -> SetInventoryModeResponseDTO {
        if failNextSet {
            failNextSet = false
            throw NSError(domain: "test", code: 1)
        }
        lastSetMode = mode
        fetchedMode = mode
        return SetInventoryModeResponseDTO(
            ok: true,
            companyId: "company-1",
            inventoryMode: mode.rawValue,
            previousInventoryMode: (mode == .tracked ? InventoryMode.off : .tracked).rawValue,
            updatedBy: "user-1",
            releasedDemands: mode == .off ? 1 : 0,
            releaseSnapshots: mode == .off ? 1 : 0
        )
    }
}

private extension InventoryModeViewModel {
    /// Polls the published `isSaving` flag until the detached commit Task has
    /// finished publishing its final state, so assertions read settled values.
    func waitUntilIdle() async {
        for _ in 0..<200 {
            if !isSaving { return }
            await Task.yield()
        }
    }
}
