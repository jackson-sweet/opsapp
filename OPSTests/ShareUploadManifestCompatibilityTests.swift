//
//  ShareUploadManifestCompatibilityTests.swift
//  OPSTests
//
//  Regression coverage for share jobs written by the shipped background-upload
//  format before the durable queue migration.
//

import XCTest
@testable import OPS

final class ShareUploadManifestCompatibilityTests: XCTestCase {

    func testLegacyCompletedUploadPreservesItsPublicURL() throws {
        let job = try decodeLegacy(state: "s3Complete")

        XCTAssertEqual(
            job.uploadedURL,
            "https://files.opsapp.co/share/original.jpg",
            "A completed job from the shipped manifest must finalize its existing object, not upload a duplicate."
        )
    }

    func testLegacyInFlightUploadRetriesLocalBytesInsteadOfFinalizingAnUnconfirmedURL() throws {
        let job = try decodeLegacy(state: "uploadingS3")

        XCTAssertNil(
            job.uploadedURL,
            "Presign assigned a public URL before the background PUT completed; an in-flight job must retry its local bytes."
        )
    }

    func testLegacyPendingUploadIgnoresAStalePublicURLFromAnEarlierFailedPUT() throws {
        let job = try decodeLegacy(state: "pendingPresign")

        XCTAssertNil(
            job.uploadedURL,
            "The shipped failure path retained s3PublicUrl while resetting state; pending work must not finalize that stale URL."
        )
    }

    private func decodeLegacy(state: String) throws -> ShareUploadJob {
        let json = """
        {
          "id": "2C20ED29-F328-49CB-A5DB-A45D83FB5938",
          "fileName": "2C20ED29-F328-49CB-A5DB-A45D83FB5938.jpg",
          "projectId": "B7EB718E-357D-45F9-A19D-68B2350F6544",
          "projectTitle": "580 Beach Dr",
          "companyId": "0288D8A7-782D-47D4-A0AA-C90344FAD14F",
          "uploadedBy": "3E9AB568-45B0-4765-BB69-9A61EB6B1A53",
          "createdAt": "2026-07-23T16:36:14Z",
          "state": "\(state)",
          "s3PublicUrl": "https://files.opsapp.co/share/original.jpg",
          "s3UploadUrl": "https://s3.example.com/signed-put",
          "attempts": 1
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShareUploadJob.self, from: Data(json.utf8))
    }
}
