import XCTest
@testable import OPS

@MainActor
final class CallCaptureCoordinatorTests: XCTestCase {
    override func tearDown() {
        CallCaptureCoordinator.shared.resetForTests()
        super.tearDown()
    }

    func testPresentWhileSheetIsActiveDefersNextCapture() {
        let coordinator = CallCaptureCoordinator.shared
        coordinator.resetForTests()

        coordinator.present(.capture(.fab))
        coordinator.present(.capture(.appShortcut))

        XCTAssertEqual(coordinator.activeRequest, .capture(.fab))

        coordinator.dismiss()

        XCTAssertEqual(coordinator.activeRequest, .capture(.appShortcut))
    }
}
