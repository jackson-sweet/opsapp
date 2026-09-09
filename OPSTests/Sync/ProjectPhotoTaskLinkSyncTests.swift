//
//  ProjectPhotoTaskLinkSyncTests.swift
//  OPSTests
//
//  Bug a290934f — a photo may document one of the project's tasks.
//
//  The link is server-owned once it exists, so it has to travel back down all
//  THREE inbound paths or a reassignment made on the web (or on a teammate's
//  phone) silently never arrives on this device: `InboundProcessor` (legacy
//  full/delta sync), `DataActor` (the actor copy of the same merge), and
//  `RealtimeProcessor` (the live upsert). Those three merges are private, and
//  the risk they carry is precisely that they DRIFT — a field added to one and
//  forgotten in the other two reads as an intermittent sync bug months later.
//  So the copy is proven where it can be proven behaviourally (the DTO), and
//  the three-way agreement is proven at the source, the same way
//  `SwiftDataPredicateLintTests` guards its crash class.
//

import Foundation
import XCTest
@testable import OPS

final class ProjectPhotoTaskLinkSyncTests: XCTestCase {

    // MARK: - DTO

    func testDTODecodesTaskIdAndLowercasesItOnTheModel() throws {
        let json = Data("""
        {
          "id": "8f0b6f0e-1d5a-4d6a-9b3d-0c9a1f2e3d4b",
          "project_id": "e3cf8105-3e83-4126-9aa1-16ebcfd096f5",
          "company_id": "a612edc0-5c18-4c4d-af97-55b9410dd077",
          "url": "https://cdn.example/a.jpg",
          "source": "in_progress",
          "uploaded_by": "283d49df-90a1-4abb-b94c-3e9f17f02c0d",
          "task_id": "2B0004B3-4696-49C5-9C74-8BD65BC66C39",
          "is_client_visible": false
        }
        """.utf8)

        let dto = try JSONDecoder().decode(ProjectPhotoDTO.self, from: json)
        XCTAssertEqual(dto.taskId, "2B0004B3-4696-49C5-9C74-8BD65BC66C39", "The DTO carries the wire value verbatim")

        let model = dto.toModel()
        XCTAssertEqual(
            model.taskId,
            "2b0004b3-4696-49c5-9c74-8bd65bc66c39",
            "Every id comparison in the app is case-sensitive, so the link is stored lowercased"
        )
    }

    func testDTOWithNoTaskIdDecodesToAnUnlinkedPhoto() throws {
        let json = Data("""
        {
          "id": "8f0b6f0e-1d5a-4d6a-9b3d-0c9a1f2e3d4b",
          "project_id": "e3cf8105-3e83-4126-9aa1-16ebcfd096f5",
          "company_id": "a612edc0-5c18-4c4d-af97-55b9410dd077",
          "url": "https://cdn.example/a.jpg",
          "uploaded_by": "283d49df-90a1-4abb-b94c-3e9f17f02c0d"
        }
        """.utf8)

        let dto = try JSONDecoder().decode(ProjectPhotoDTO.self, from: json)
        XCTAssertNil(dto.taskId)
        XCTAssertNil(dto.toModel().taskId, "An installed photo documents no task until someone assigns one")
    }

    func testDTOEncodesTheLinkUnderTheServerColumnName() throws {
        let dto = ProjectPhotoDTO(
            id: "8f0b6f0e-1d5a-4d6a-9b3d-0c9a1f2e3d4b",
            projectId: "e3cf8105-3e83-4126-9aa1-16ebcfd096f5",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            url: "https://cdn.example/a.jpg",
            thumbnailURL: nil,
            renderedURL: nil,
            source: "in_progress",
            siteVisitId: nil,
            taskId: "2b0004b3-4696-49c5-9c74-8bd65bc66c39",
            uploadedBy: "283d49df-90a1-4abb-b94c-3e9f17f02c0d",
            caption: nil,
            isClientVisible: false,
            takenAt: nil,
            createdAt: nil,
            updatedAt: nil,
            deletedAt: nil
        )

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as? [String: Any]
        XCTAssertEqual(encoded?["task_id"] as? String, "2b0004b3-4696-49c5-9c74-8bd65bc66c39")
        XCTAssertNil(encoded?["taskId"], "The wire name is the column name")
    }

    // MARK: - Normalization

    func testTaskLinkNormalizerRejectsEverythingThatCannotMatchATask() {
        XCTAssertNil(ProjectPhotoTaskLink.canonical(nil))
        XCTAssertNil(ProjectPhotoTaskLink.canonical(""))
        XCTAssertNil(ProjectPhotoTaskLink.canonical("   "), "Transport whitespace is not a task")
        XCTAssertEqual(
            ProjectPhotoTaskLink.canonical("  2B0004B3-4696-49C5-9C74-8BD65BC66C39  "),
            "2b0004b3-4696-49c5-9c74-8bd65bc66c39"
        )
    }

    func testApplyTaskLinkIsTheOnlyWriteAndAlwaysNormalizes() {
        let photo = ProjectPhoto(
            id: "8f0b6f0e-1d5a-4d6a-9b3d-0c9a1f2e3d4b",
            projectId: "e3cf8105-3e83-4126-9aa1-16ebcfd096f5",
            companyId: "a612edc0-5c18-4c4d-af97-55b9410dd077",
            url: "https://cdn.example/a.jpg",
            uploadedBy: "283d49df-90a1-4abb-b94c-3e9f17f02c0d"
        )
        XCTAssertNil(photo.taskId)

        photo.applyTaskLink("2B0004B3-4696-49C5-9C74-8BD65BC66C39")
        XCTAssertEqual(photo.taskId, "2b0004b3-4696-49c5-9c74-8bd65bc66c39")

        photo.applyTaskLink("")
        XCTAssertNil(photo.taskId, "An empty inbound value clears the link rather than storing a value nothing can match")
    }

    // MARK: - The three inbound paths agree

    /// `InboundProcessor.mergeProjectPhoto` and `DataActor.mergeProjectPhoto`
    /// are the same merge written twice. Both gate every copy on an
    /// `acceptableFields` list, so a field missing from either list is a copy
    /// that silently never runs — no error, no crash, just a value that never
    /// arrives.
    func testBothAcceptableFieldMergesListTheTaskLink() throws {
        for path in ["Network/Sync/InboundProcessor.swift", "Utilities/DataActor.swift"] {
            let text = try Self.appSource(path)
            let merge = try XCTUnwrap(
                Self.functionBody(named: "mergeProjectPhoto", in: text),
                "\(path) must still define mergeProjectPhoto"
            )
            XCTAssertTrue(
                merge.contains("\"taskId\""),
                "\(path): mergeProjectPhoto must list taskId among its acceptable fields"
            )
            XCTAssertTrue(
                merge.contains("existing.applyTaskLink(dto.taskId)"),
                "\(path): mergeProjectPhoto must copy the task link through the normalizer"
            )
        }
    }

    /// The realtime upsert protects a pending local change from the echo of the
    /// write that caused it. Without `taskId` in that set, assigning a task and
    /// receiving the row back reverts the assignment on screen.
    func testRealtimeUpsertProtectsAPendingTaskLinkFromItsOwnEcho() throws {
        let text = try Self.appSource("Network/Sync/RealtimeProcessor.swift")
        let upsert = try XCTUnwrap(
            Self.functionBody(named: "upsertProjectPhoto", in: text),
            "RealtimeProcessor must still define upsertProjectPhoto"
        )
        XCTAssertTrue(
            upsert.contains("pendingFields.contains(\"taskId\")"),
            "upsertProjectPhoto must guard the task link with pendingFields, like every other column it copies"
        )
        XCTAssertTrue(
            upsert.contains("existing.taskId = model.taskId"),
            "upsertProjectPhoto must copy the task link from the inbound model"
        )
    }

    // MARK: - Source access

    /// The body of `func <name>(` through the matching closing brace. Brace
    /// counting is enough here: these two functions contain no string literal
    /// carrying an unbalanced brace, and a miscount could only widen the body,
    /// never hide the lines being asserted.
    static func functionBody(named name: String, in text: String) -> String? {
        guard let declaration = text.range(of: "func \(name)(") else { return nil }
        guard let open = text[declaration.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var cursor = open
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[open...cursor])
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    /// A file under the app target, resolved from this file's compile-time path
    /// so the scan follows the checkout it was built from.
    static func appSource(_ relativePath: String, from file: StaticString = #filePath) throws -> String {
        var url = URL(fileURLWithPath: "\(file)")
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("OPS.xcodeproj").path) {
                let source = url.appendingPathComponent("OPS").appendingPathComponent(relativePath)
                return try String(contentsOf: source, encoding: .utf8)
            }
        }
        throw XCTSkip("OPS.xcodeproj not found above \(file); source scan needs the checkout on disk")
    }
}
