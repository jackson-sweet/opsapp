import XCTest
@testable import OPS

final class StorageProfilerBudgetTests: XCTestCase {
    func testBackgroundBudgetSnapshotReflectsPersistedSettingWithoutMainActorInstance() async throws {
        let suite = "StorageProfilerBudgetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Int64(321_000_000), forKey: "photoStorage.budgetBytes")
        let value = await Task.detached {
            StorageProfiler.budgetSnapshot(defaults: UserDefaults(suiteName: suite)!)
        }.value
        XCTAssertEqual(value, 321_000_000)
        defaults.set(0, forKey: "photoStorage.budgetBytes")
        XCTAssertGreaterThan(StorageProfiler.budgetSnapshot(defaults: defaults), 0)
    }
}
