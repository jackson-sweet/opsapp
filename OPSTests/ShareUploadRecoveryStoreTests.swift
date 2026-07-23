//
//  ShareUploadRecoveryStoreTests.swift
//  OPSTests
//
//  A manifest acknowledgement can be lost after the selected JPEGs are staged.
//  The independent batch record must retain enough routing metadata for the app
//  to drain those files even when no manifest row is readable.
//

import XCTest
@testable import OPS

final class ShareUploadRecoveryStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testCommittedBatchReconstructsJobsWithoutAManifest() throws {
        let jobs = try stagedJobs()

        XCTAssertEqual(
            ShareUploadRecoveryStore.save(
                jobs,
                inboxDirectoryURL: directory,
                batchId: "71B69A69-8915-41A6-B132-685EBCB54C07"
            ),
            .committed
        )

        XCTAssertEqual(
            ShareUploadManifestStore.recoverableJobs(
                manifestURL: directory.appendingPathComponent("missing-manifest.json"),
                inboxDirectoryURL: directory
            ).map(\.id),
            jobs.map(\.id)
        )
    }

    func testLostWriteAcknowledgementIsRecoveredByReadingTheBatchRecord() throws {
        enum Fault: Error { case acknowledgementLost }
        let jobs = try stagedJobs()

        let result = ShareUploadRecoveryStore.save(
            jobs,
            inboxDirectoryURL: directory,
            batchId: "71B69A69-8915-41A6-B132-685EBCB54C07",
            writer: { data, url in
                try data.write(to: url, options: .atomic)
                throw Fault.acknowledgementLost
            }
        )

        XCTAssertEqual(result, .committed)
        XCTAssertEqual(
            ShareUploadRecoveryStore.jobs(
                inboxDirectoryURL: directory
            ).map(\.id),
            jobs.map(\.id)
        )
    }

    func testDefinitePreCommitFailureAllowsAVisibleRetry() throws {
        enum Fault: Error { case diskUnavailable }
        let jobs = try stagedJobs()

        let result = ShareUploadRecoveryStore.save(
            jobs,
            inboxDirectoryURL: directory,
            batchId: "71B69A69-8915-41A6-B132-685EBCB54C07",
            writer: { _, _ in throw Fault.diskUnavailable }
        )

        XCTAssertEqual(result, .rejected)
        XCTAssertTrue(
            jobs.allSatisfy {
                FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent($0.fileName).path
                )
            },
            "The store reports policy; the controller decides when a definite failure is safe to roll back."
        )
    }

    func testCompletedFilesRetireTheirRecoveryBatch() throws {
        let jobs = try stagedJobs()
        XCTAssertEqual(
            ShareUploadRecoveryStore.save(
                jobs,
                inboxDirectoryURL: directory,
                batchId: "71B69A69-8915-41A6-B132-685EBCB54C07"
            ),
            .committed
        )

        for job in jobs {
            try FileManager.default.removeItem(
                at: directory.appendingPathComponent(job.fileName)
            )
        }
        ShareUploadRecoveryStore.cleanupCompletedBatches(
            inboxDirectoryURL: directory
        )

        XCTAssertTrue(
            ShareUploadRecoveryStore.jobs(
                inboxDirectoryURL: directory
            ).isEmpty
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testManifestAndRecoveryCaptureTimeConflictIsParked() throws {
        let id = "34F5B3D8-9D8D-4CE1-9467-CBA35133890F"
        let recoveryJob = job(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_785_700_574.75)
        )
        try Data([0xff, 0xd8, 0xff, 0xd9]).write(
            to: directory.appendingPathComponent(recoveryJob.fileName),
            options: .atomic
        )
        XCTAssertEqual(
            ShareUploadRecoveryStore.save(
                [recoveryJob],
                inboxDirectoryURL: directory,
                batchId: "71B69A69-8915-41A6-B132-685EBCB54C07"
            ),
            .committed,
            "Subsecond precision lost by ISO-8601 storage must still read back as the same stable job."
        )

        let manifestURL = directory.appendingPathComponent("manifest.json")
        XCTAssertEqual(
            ShareUploadManifestStore.append(
                [
                    job(
                        id: id,
                        createdAt: Date(timeIntervalSince1970: 1_785_700_575.10)
                    ),
                ],
                manifestURL: manifestURL
            ),
            .committed
        )

        XCTAssertTrue(
            ShareUploadManifestStore.recoverableJobs(
                manifestURL: manifestURL,
                inboxDirectoryURL: directory
            ).isEmpty,
            "One job ID bound to different capture seconds must be parked instead of sent into a permanent server identity conflict."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(recoveryJob.fileName).path
            ),
            "A routing conflict must preserve the source JPEG for operator recovery."
        )
    }

    private func stagedJobs() throws -> [ShareUploadJob] {
        let jobs = [
            job(id: "34F5B3D8-9D8D-4CE1-9467-CBA35133890F"),
            job(id: "BD8EA30C-AD29-4B83-BF7E-56051447F35D"),
        ]
        for job in jobs {
            try Data([0xff, 0xd8, 0xff, 0xd9]).write(
                to: directory.appendingPathComponent(job.fileName),
                options: .atomic
            )
        }
        return jobs
    }

    private func job(
        id: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_785_700_574.75)
    ) -> ShareUploadJob {
        ShareUploadJob(
            id: id,
            fileName: "\(id).jpg",
            projectId: "B7EB718E-357D-45F9-A19D-68B2350F6544",
            projectTitle: "580 Beach Dr",
            companyId: "3EEC649E-598D-4EA5-A916-80B89B7DA0F4",
            uploadedBy: "1D6C2CDA-0B5D-40C4-B1B0-C10A248388A8",
            createdAt: createdAt
        )
    }
}
