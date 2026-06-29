import XCTest
@testable import DeckKit

@MainActor
final class DeckRuntimeTests: XCTestCase {
    func testRuntimeContextEquatableIncludesAllFields() {
        let lhs = DeckRuntimeContext(
            companyId: "company-1",
            projectId: "project-1",
            projectName: "Alpha",
            appSurface: .ops
        )
        let rhs = DeckRuntimeContext(
            companyId: "company-1",
            projectId: "project-1",
            projectName: "Alpha",
            appSurface: .ops
        )
        let differentSurface = DeckRuntimeContext(
            companyId: "company-1",
            projectId: "project-1",
            projectName: "Alpha",
            appSurface: .opsDecks
        )
        let differentCompany = DeckRuntimeContext(
            companyId: "company-2",
            projectId: "project-1",
            projectName: "Alpha",
            appSurface: .ops
        )
        let differentProject = DeckRuntimeContext(
            companyId: "company-1",
            projectId: "project-2",
            projectName: "Alpha",
            appSurface: .ops
        )
        let differentProjectName = DeckRuntimeContext(
            companyId: "company-1",
            projectId: "project-1",
            projectName: "Bravo",
            appSurface: .ops
        )

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, differentCompany)
        XCTAssertNotEqual(lhs, differentProject)
        XCTAssertNotEqual(lhs, differentProjectName)
        XCTAssertNotEqual(lhs, differentSurface)
    }

    func testRuntimeUsesNoopServicesByDefault() {
        let runtime = DeckRuntime(
            context: DeckRuntimeContext(
                companyId: "company-1",
                projectId: nil,
                projectName: nil,
                appSurface: .opsDecks
            ),
            store: nil
        )

        XCTAssertTrue(runtime.syncQueue is NoopDeckSyncQueue)
        XCTAssertTrue(runtime.imageUploader is NoopDeckImageUploader)
        XCTAssertTrue(runtime.ocrService is NoopDeckOCRService)
        XCTAssertNil(runtime.codeProfile)
    }

    func testRuntimeCarriesInjectedCodeProfileForStandaloneDesigner() {
        let profile = DeckCodeProfile(
            id: "profile-runtime",
            jurisdiction: DeckJurisdiction(id: "jurisdiction-runtime"),
            rules: []
        )
        let runtime = DeckRuntime(
            context: DeckRuntimeContext(
                companyId: "company-1",
                projectId: nil,
                projectName: nil,
                appSurface: .opsDecks
            ),
            store: nil,
            codeProfile: profile
        )

        XCTAssertEqual(runtime.codeProfile, profile)
    }

    func testLightCapabilitiesAreViewerOnlyForEmbeddedOPS() {
        XCTAssertTrue(DeckCapabilities.light.contains(.materials))
        XCTAssertFalse(DeckCapabilities.light.contains(.plausibleFrame))
        XCTAssertFalse(DeckCapabilities.light.contains(.groundCover))
        XCTAssertFalse(DeckCapabilities.light.contains(.codeCompliance))
        XCTAssertEqual(DeckCapabilities.forSurface(.ops), .light)
    }

    func testFullCapabilitiesIncludeStandaloneDesignerAuthoringTools() {
        XCTAssertTrue(DeckCapabilities.full.contains(.materials))
        XCTAssertTrue(DeckCapabilities.full.contains(.plausibleFrame))
        XCTAssertTrue(DeckCapabilities.full.contains(.groundCover))
        XCTAssertTrue(DeckCapabilities.full.contains(.codeCompliance))
        XCTAssertEqual(DeckCapabilities.forSurface(.opsDecks), .full)
    }
}
