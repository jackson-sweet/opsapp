//
//  ShareUploadManifestStoreTests.swift
//  OPSTests
//
//  Cross-process queue durability: a corrupt deployed manifest must never be
//  replaced with an empty queue, and a multi-photo share commits atomically.
//

import XCTest
@testable import OPS

final class ShareUploadManifestStoreTests: XCTestCase {

    private var directory: URL!
    private var manifestURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        manifestURL = directory.appendingPathComponent("manifest.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCorruptManifestIsPreservedInsteadOfOverwritten() throws {
        let corrupt = Data("{not-json".utf8)
        try corrupt.write(to: manifestURL, options: .atomic)

        XCTAssertEqual(
            ShareUploadManifestStore.append(
                [job(id: "34F5B3D8-9D8D-4CE1-9467-CBA35133890F")],
                manifestURL: manifestURL
            ),
            .rejected
        )
        XCTAssertEqual(try Data(contentsOf: manifestURL), corrupt)
    }

    func testMultiPhotoAppendIsAtomicAndIdempotent() throws {
        let first = job(id: "34F5B3D8-9D8D-4CE1-9467-CBA35133890F")
        let second = job(id: "BD8EA30C-AD29-4B83-BF7E-56051447F35D")

        XCTAssertEqual(
            ShareUploadManifestStore.append(
                [first, second],
                manifestURL: manifestURL
            ),
            .committed
        )
        XCTAssertEqual(
            ShareUploadManifestStore.append(
                [first, second],
                manifestURL: manifestURL
            ),
            .committed
        )

        let stored = ShareUploadManifestStore.allJobs(manifestURL: manifestURL)
        XCTAssertEqual(stored.map(\.id), [first.id, second.id])
    }

    func testPostWriteAcknowledgementLossIsRecoveredByCoordinatedRead() throws {
        enum Fault: Error { case acknowledgementLost }
        let first = job(id: "34F5B3D8-9D8D-4CE1-9467-CBA35133890F")
        let second = job(id: "BD8EA30C-AD29-4B83-BF7E-56051447F35D")

        let result = ShareUploadManifestStore.append(
            [first, second],
            manifestURL: manifestURL,
            writer: { data, url in
                try data.write(to: url, options: .atomic)
                throw Fault.acknowledgementLost
            }
        )

        XCTAssertEqual(
            result,
            .committed,
            "A coordinated retry must recognize the rows written before acknowledgement was lost."
        )
        XCTAssertEqual(
            ShareUploadManifestStore.allJobs(manifestURL: manifestURL).map(\.id),
            [first.id, second.id],
            "The recovered commit must remain readable without appending duplicate rows."
        )
    }

    private func job(id: String) -> ShareUploadJob {
        ShareUploadJob(
            id: id,
            fileName: "\(id).jpg",
            projectId: "B7EB718E-357D-45F9-A19D-68B2350F6544",
            projectTitle: "580 Beach Dr",
            companyId: "3EEC649E-598D-4EA5-A916-80B89B7DA0F4",
            uploadedBy: "1D6C2CDA-0B5D-40C4-B1B0-C10A248388A8",
            createdAt: Date(timeIntervalSince1970: 1_785_700_574)
        )
    }
}
