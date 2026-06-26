import DeckKit
import XCTest
@testable import OPS

@MainActor
final class OPSDeckRuntimeFactoryTests: XCTestCase {
    func testMakeBuildsOPSRuntimeContextAndAdapters() {
        let design = DeckDesign(
            companyId: "company-1",
            projectId: "project-1",
            drawingDataJSON: DeckDrawingData().toJSON()
        )

        let runtime = OPSDeckRuntimeFactory.make(
            deckDesign: design,
            modelContext: nil,
            syncEngine: nil,
            projectName: "Alpha"
        )

        XCTAssertEqual(
            runtime.context,
            DeckRuntimeContext(
                companyId: "company-1",
                projectId: "project-1",
                projectName: "Alpha",
                appSurface: .ops
            )
        )
        XCTAssertNotNil(runtime.store)
        XCTAssertTrue(runtime.syncQueue is OPSDeckSyncQueue)
    }
}
