import XCTest
@testable import OPS

final class MapboxConfigTests: XCTestCase {
    func testHostedXCTestUsesFallbackTokenWhenInfoPlistTokenIsUnresolvedPlaceholder() {
        let token = MapboxConfig.resolvedPublicToken(
            infoPlistToken: "$(MBX_ACCESS_TOKEN)",
            environment: [:],
            isRunningUnderXCTest: true
        )

        XCTAssertEqual(token, "pk.ops-hosted-xctest")
    }

    func testHostedXCTestEnvironmentTokenOverridesFallbackToken() {
        let token = MapboxConfig.resolvedPublicToken(
            infoPlistToken: "$(MBX_ACCESS_TOKEN)",
            environment: ["OPS_HOSTED_XCTEST_MBX_ACCESS_TOKEN": "pk.test.override"],
            isRunningUnderXCTest: true
        )

        XCTAssertEqual(token, "pk.test.override")
    }

    func testProductionConfigurationDoesNotUseFallbackToken() {
        let token = MapboxConfig.resolvedPublicToken(
            infoPlistToken: "$(MBX_ACCESS_TOKEN)",
            environment: [:],
            isRunningUnderXCTest: false
        )

        XCTAssertNil(token)
    }
}
