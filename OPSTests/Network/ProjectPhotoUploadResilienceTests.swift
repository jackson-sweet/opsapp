//
//  ProjectPhotoUploadResilienceTests.swift
//  OPSTests
//
//  Regression coverage for the batch-photo-upload timeout / partial-failure bug:
//  uploading 10 photos at once dropped some and surfaced "request timed out".
//
//  Three units under test:
//    1. NetworkRetry            — transient retry vs permanent early-stop.
//    2. ProjectPhotoBatchUploader — per-photo isolation (one failure never
//       aborts the batch), retry, 1:1 ordered outcomes. THE core regression.
//    3. GalleryReconciler       — identity (not positional) mapping of outcomes
//       back to gallery URLs.
//
//  All run in-process with a mock uploader — no S3, no Supabase, no network.
//

import XCTest
import UIKit
@testable import OPS

final class ProjectPhotoUploadResilienceTests: XCTestCase {

    // MARK: - Fixtures

    private func img() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func ready(_ filename: String) -> ProjectPhotoBatchUploader.Input {
        .ready(PreparedProjectImage(image: img(), filename: filename, data: Data(filename.utf8)))
    }

    // MARK: - 1. NetworkRetry

    func test_networkRetry_transientThenSucceeds_stopsAtSuccess() async throws {
        var attempts = 0
        let result: String = try await NetworkRetry.run(maxAttempts: 3, baseDelaySeconds: 0) {
            attempts += 1
            if attempts < 2 { throw URLError(.timedOut) }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts, 2)
    }

    func test_networkRetry_alwaysTransient_exhaustsAttemptsThenThrows() async {
        var attempts = 0
        do {
            let _: String = try await NetworkRetry.run(maxAttempts: 3, baseDelaySeconds: 0) {
                attempts += 1
                throw URLError(.timedOut)
            }
            XCTFail("expected throw after exhausting retries")
        } catch {
            // expected
        }
        XCTAssertEqual(attempts, 3)
    }

    func test_networkRetry_permanentError_throwsImmediatelyWithoutRetry() async {
        var attempts = 0
        do {
            // UploadError.invalidURL classifies as .permanent — no point retrying.
            let _: String = try await NetworkRetry.run(maxAttempts: 5, baseDelaySeconds: 0) {
                attempts += 1
                throw UploadError.invalidURL
            }
            XCTFail("expected immediate throw on permanent error")
        } catch {
            // expected
        }
        XCTAssertEqual(attempts, 1)
    }

    // MARK: - 2. ProjectPhotoBatchUploader

    @MainActor
    func test_batch_allSucceed_returnsOrderedSuccesses() async {
        let uploader = RecordingDataUploader(plan: .alwaysSucceed)
        let batch = ProjectPhotoBatchUploader(
            uploader: uploader, folder: "projects/c/p",
            maxConcurrent: 3, maxAttempts: 3, baseDelaySeconds: 0
        )
        let outcomes = await batch.upload([ready("a.jpg"), ready("b.jpg"), ready("c.jpg")])

        XCTAssertEqual(outcomes.count, 3)
        XCTAssertEqual(outcomes.map(\.filename), ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertTrue(outcomes.allSatisfy { $0.isSuccess })
        let uploaded = await uploader.uploadedFilenames
        XCTAssertEqual(Set(uploaded), ["a.jpg", "b.jpg", "c.jpg"])
    }

    /// THE core regression: a mid-batch failure must NOT abort the rest. The old
    /// `uploadProjectImages` threw on the first failure and discarded the whole
    /// accumulator, so photos after the failure never uploaded.
    @MainActor
    func test_batch_oneFailure_doesNotAbortTheOthers() async {
        let uploader = RecordingDataUploader(plan: .failFilenames(["b.jpg"]))
        let batch = ProjectPhotoBatchUploader(
            uploader: uploader, folder: "f",
            maxConcurrent: 3, maxAttempts: 2, baseDelaySeconds: 0
        )
        let outcomes = await batch.upload([ready("a.jpg"), ready("b.jpg"), ready("c.jpg")])

        XCTAssertEqual(outcomes.count, 3)
        XCTAssertTrue(outcomes[0].isSuccess, "a.jpg should succeed")
        XCTAssertFalse(outcomes[1].isSuccess, "b.jpg should fail")
        XCTAssertTrue(outcomes[2].isSuccess, "c.jpg must STILL upload despite b.jpg failing")
        let uploaded = await uploader.uploadedFilenames
        XCTAssertTrue(uploaded.contains("a.jpg"))
        XCTAssertTrue(uploaded.contains("c.jpg"))
        XCTAssertFalse(uploaded.contains("b.jpg"))
    }

    @MainActor
    func test_batch_transientThenSucceed_retriesPerImage() async {
        let uploader = RecordingDataUploader(plan: .failThenSucceed(failCount: 1))
        let batch = ProjectPhotoBatchUploader(
            uploader: uploader, folder: "f",
            maxConcurrent: 2, maxAttempts: 3, baseDelaySeconds: 0
        )
        let outcomes = await batch.upload([ready("a.jpg"), ready("b.jpg")])

        XCTAssertTrue(outcomes.allSatisfy { $0.isSuccess })
        let attempts = await uploader.attemptCount
        XCTAssertEqual(attempts, 4, "2 images × (1 transient fail + 1 success)")
    }

    @MainActor
    func test_batch_encodingFailedInput_becomesFailureWithoutUpload() async {
        let uploader = RecordingDataUploader(plan: .alwaysSucceed)
        let batch = ProjectPhotoBatchUploader(
            uploader: uploader, folder: "f",
            maxConcurrent: 3, maxAttempts: 1, baseDelaySeconds: 0
        )
        let inputs: [ProjectPhotoBatchUploader.Input] = [
            ready("a.jpg"),
            .encodingFailed(image: img(), filename: "b.jpg"),
            ready("c.jpg")
        ]
        let outcomes = await batch.upload(inputs)

        XCTAssertEqual(outcomes.count, 3)
        XCTAssertTrue(outcomes[0].isSuccess)
        XCTAssertFalse(outcomes[1].isSuccess)
        XCTAssertTrue(outcomes[2].isSuccess)
        let uploaded = await uploader.uploadedFilenames
        XCTAssertEqual(Set(uploaded), ["a.jpg", "c.jpg"], "encoding-failed image is never uploaded")
    }

    @MainActor
    func test_batch_uploadsAll_whenConcurrencyCapBelowBatchSize() async {
        let uploader = RecordingDataUploader(plan: .alwaysSucceed)
        let batch = ProjectPhotoBatchUploader(
            uploader: uploader, folder: "f",
            maxConcurrent: 2, maxAttempts: 1, baseDelaySeconds: 0
        )
        let inputs = (0..<10).map { ready("img\($0).jpg") }
        let outcomes = await batch.upload(inputs)

        XCTAssertEqual(outcomes.count, 10)
        XCTAssertTrue(outcomes.allSatisfy { $0.isSuccess })
        let uploaded = await uploader.uploadedFilenames
        XCTAssertEqual(Set(uploaded).count, 10)
    }

    // MARK: - 3. GalleryReconciler

    private func successOutcome(_ filename: String, _ url: String) -> ProjectImageUploadOutcome {
        .success(image: img(), filename: filename, url: url)
    }

    private func failureOutcome(_ filename: String) -> ProjectImageUploadOutcome {
        .failure(image: img(), filename: filename, kind: .transient(reason: "url_-1001"), message: "Connection timed out.")
    }

    func test_reconcile_replacesSuccessByIdentity_keepsFailureLocal() {
        let current = ["https://s3/old1.jpg", "local://a", "local://b", "local://c"]
        let results: [(localURL: String, outcome: ProjectImageUploadOutcome)] = [
            ("local://a", successOutcome("a.jpg", "https://s3/a.jpg")),
            ("local://b", failureOutcome("b.jpg")),
            ("local://c", successOutcome("c.jpg", "https://s3/c.jpg"))
        ]

        let result = GalleryReconciler.reconcileDrain(currentImageURLs: current, results: results)

        // a and c swapped to remote; b's local placeholder untouched; pre-existing
        // remote URL preserved in place.
        XCTAssertEqual(result.updatedImageURLs,
                       ["https://s3/old1.jpg", "https://s3/a.jpg", "local://b", "https://s3/c.jpg"])
        XCTAssertEqual(Set(result.syncedLocalURLs), ["local://a", "local://c"])
        XCTAssertEqual(Set(result.newRemoteURLs), ["https://s3/a.jpg", "https://s3/c.jpg"])
        XCTAssertEqual(result.failedLocalURLs, ["local://b"])
    }

    func test_reconcile_doesNotMisalignWhenOrderDiffersFromGallery() {
        // Gallery order is c, a, b but results arrive a, b, c — identity mapping
        // must still pair each result with its OWN local URL (the positional bug).
        let current = ["local://c", "local://a", "local://b"]
        let results: [(localURL: String, outcome: ProjectImageUploadOutcome)] = [
            ("local://a", successOutcome("a.jpg", "https://s3/a.jpg")),
            ("local://b", successOutcome("b.jpg", "https://s3/b.jpg")),
            ("local://c", successOutcome("c.jpg", "https://s3/c.jpg"))
        ]

        let result = GalleryReconciler.reconcileDrain(currentImageURLs: current, results: results)

        XCTAssertEqual(result.updatedImageURLs,
                       ["https://s3/c.jpg", "https://s3/a.jpg", "https://s3/b.jpg"])
        XCTAssertEqual(result.failedLocalURLs, [])
    }
}

// MARK: - Mock

/// In-process single-image uploader. An `actor` so concurrent batch tasks can
/// record into it without a data race (mirrors the RecordingNotifier style in
/// DimensionedPhotoSyncManagerTests).
private actor RecordingDataUploader: ProjectImageDataUploading {

    enum Plan {
        case alwaysSucceed
        /// Throw a transient error for these filenames every time.
        case failFilenames(Set<String>)
        /// Throw `failCount` transient errors per filename, then succeed.
        case failThenSucceed(failCount: Int)
    }

    let plan: Plan
    private(set) var attemptCount = 0
    private(set) var uploadedFilenames: [String] = []
    private var failuresByFilename: [String: Int] = [:]

    init(plan: Plan) {
        self.plan = plan
    }

    func uploadImageData(_ data: Data, filename: String, folder: String) async throws -> String {
        attemptCount += 1
        switch plan {
        case .alwaysSucceed:
            uploadedFilenames.append(filename)
            return "https://s3/\(folder)/\(filename)"

        case .failFilenames(let names):
            if names.contains(filename) {
                throw URLError(.timedOut)
            }
            uploadedFilenames.append(filename)
            return "https://s3/\(folder)/\(filename)"

        case .failThenSucceed(let failCount):
            let prior = failuresByFilename[filename] ?? 0
            if prior < failCount {
                failuresByFilename[filename] = prior + 1
                throw URLError(.timedOut)
            }
            uploadedFilenames.append(filename)
            return "https://s3/\(folder)/\(filename)"
        }
    }
}
