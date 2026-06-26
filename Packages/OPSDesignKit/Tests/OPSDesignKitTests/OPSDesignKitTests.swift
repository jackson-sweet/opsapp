import XCTest
@testable import OPSDesignKit

final class OPSDesignKitTests: XCTestCase {
    func testPublicModuleVersionIsAvailable() {
        XCTAssertFalse(OPSDesignKitModule.version.isEmpty)
    }

    func testCoreStyleTokensAreAvailable() {
        XCTAssertNotNil(OPSStyle.Colors.opsAccent)
        XCTAssertNotNil(OPSStyle.Typography.button)
        XCTAssertGreaterThan(OPSStyle.Layout.touchTargetStandard, 0)
    }
}
