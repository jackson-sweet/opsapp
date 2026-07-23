//
//  ShareUploadRecoveryStore.swift
//  Shared between the OPS app and OPSShareExtension.
//
//  Every accepted share gets an independent, atomic batch record beside its
//  staged JPEGs. The ordinary manifest remains the fast mutable queue, while
//  this record is the durable recovery ledger: if the manifest write is lost or
//  corrupt, the app can still reconstruct the exact project, company, uploader,
//  capture timestamp, and stable server job ID for every photo.
//

import Foundation
import os

private struct ShareUploadRecoveryBatch: Codable {
    let version: Int
    let id: String
    let createdAt: Date
    let jobs: [ShareUploadJob]
}

enum ShareUploadRecoveryStore {
    enum SaveResult: Equatable {
        case committed
        case rejected
        case uncertain
    }

    private static let currentVersion = 1
    private static let filePrefix = "share-recovery-"
    private static let fileSuffix = ".json"
    private static let log = Logger(
        subsystem: "co.opsapp.ops.share",
        category: "recovery"
    )

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Persists a complete share batch as one atomic record. The record is read
    /// back even after a thrown write so a lost acknowledgement can be recovered
    /// without telling the controller to discard already-durable source bytes.
    static func save(
        _ jobs: [ShareUploadJob],
        inboxDirectoryURL: URL? = AppGroupConfig.inboxDirectoryURL,
        batchId: String = UUID().uuidString,
        writer: (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        }
    ) -> SaveResult {
        guard let inboxDirectoryURL,
              UUID(uuidString: batchId) != nil,
              isValidBatch(jobs) else {
            return .rejected
        }

        do {
            try FileManager.default.createDirectory(
                at: inboxDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            log.error(
                "recovery directory creation failed: \(error.localizedDescription, privacy: .public)"
            )
            return .rejected
        }

        let batch = ShareUploadRecoveryBatch(
            version: currentVersion,
            id: batchId,
            createdAt: Date(),
            jobs: jobs
        )
        let data: Data
        do {
            data = try encoder.encode(batch)
        } catch {
            log.error(
                "recovery batch encoding failed: \(error.localizedDescription, privacy: .public)"
            )
            return .rejected
        }

        let recordURL = inboxDirectoryURL.appendingPathComponent(
            "\(filePrefix)\(batchId)\(fileSuffix)",
            isDirectory: false
        )
        var writerReturned = false
        var writerError: Error?
        do {
            try writer(data, recordURL)
            writerReturned = true
        } catch {
            writerError = error
        }

        do {
            let stored = try decodeBatch(at: recordURL)
            if sameStableBatch(stored, batch) {
                return .committed
            }
            log.error(
                "recovery record \(batchId, privacy: .public) did not match its staged batch"
            )
            return .uncertain
        } catch {
            if let writerError {
                log.error(
                    "recovery write rejected for \(batchId, privacy: .public): \(writerError.localizedDescription, privacy: .public)"
                )
            } else {
                log.error(
                    "recovery readback failed for \(batchId, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            // A writer that threw before creating the unique record is a
            // definite pre-commit failure. Once it returned, or once a record
            // exists but cannot be decoded, the only safe answer is uncertain.
            if !writerReturned,
               !FileManager.default.fileExists(atPath: recordURL.path) {
                return .rejected
            }
            return .uncertain
        }
    }

    /// Every valid recovery job whose JPEG is still present. Corrupt/conflicting
    /// records are preserved for diagnosis and omitted rather than misrouted.
    static func jobs(
        inboxDirectoryURL: URL? = AppGroupConfig.inboxDirectoryURL
    ) -> [ShareUploadJob] {
        guard let inboxDirectoryURL else { return [] }

        var byId: [String: ShareUploadJob] = [:]
        var conflicted = Set<String>()
        for recordURL in recordURLs(in: inboxDirectoryURL) {
            let batch: ShareUploadRecoveryBatch
            do {
                batch = try decodeBatch(at: recordURL)
            } catch {
                log.error(
                    "recovery record preserved after decode failure at \(recordURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                continue
            }
            guard batch.version == currentVersion,
                  UUID(uuidString: batch.id) != nil,
                  isValidBatch(batch.jobs) else {
                log.error(
                    "recovery record preserved after validation failure at \(recordURL.lastPathComponent, privacy: .public)"
                )
                continue
            }

            for job in batch.jobs {
                let fileURL = inboxDirectoryURL.appendingPathComponent(
                    job.fileName,
                    isDirectory: false
                )
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    continue
                }
                if let existing = byId[job.id],
                   !sameStableJob(existing, job) {
                    conflicted.insert(job.id)
                    continue
                }
                byId[job.id] = job
            }
        }

        for id in conflicted {
            byId.removeValue(forKey: id)
            log.error(
                "recovery job \(id, privacy: .public) omitted because records disagree on routing"
            )
        }
        return byId.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    /// Removes a batch record only after none of its referenced JPEGs remains.
    /// Completed photos therefore cannot be resurrected, while any still-queued
    /// sibling keeps the complete atomic batch record intact.
    static func cleanupCompletedBatches(
        inboxDirectoryURL: URL? = AppGroupConfig.inboxDirectoryURL
    ) {
        guard let inboxDirectoryURL else { return }
        for recordURL in recordURLs(in: inboxDirectoryURL) {
            do {
                let batch = try decodeBatch(at: recordURL)
                let hasRemainingFile = batch.jobs.contains { job in
                    FileManager.default.fileExists(
                        atPath: inboxDirectoryURL
                            .appendingPathComponent(job.fileName)
                            .path
                    )
                }
                if !hasRemainingFile {
                    try FileManager.default.removeItem(at: recordURL)
                }
            } catch {
                // A corrupt record may be the only routing evidence left. Never
                // delete it automatically.
                log.error(
                    "recovery cleanup preserved \(recordURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private static func recordURLs(in directory: URL) -> [URL] {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            return []
        }
        return contents
            .filter {
                $0.lastPathComponent.hasPrefix(filePrefix)
                    && $0.lastPathComponent.hasSuffix(fileSuffix)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func decodeBatch(
        at url: URL
    ) throws -> ShareUploadRecoveryBatch {
        try decoder.decode(
            ShareUploadRecoveryBatch.self,
            from: Data(contentsOf: url)
        )
    }

    private static func isValidBatch(_ jobs: [ShareUploadJob]) -> Bool {
        guard !jobs.isEmpty,
              Set(jobs.map(\.id)).count == jobs.count else {
            return false
        }
        return jobs.allSatisfy { job in
            UUID(uuidString: job.id) != nil
                && UUID(uuidString: job.projectId) != nil
                && UUID(uuidString: job.companyId) != nil
                && UUID(uuidString: job.uploadedBy) != nil
                && !job.fileName.isEmpty
                && (job.fileName as NSString).lastPathComponent == job.fileName
        }
    }

    private static func sameStableBatch(
        _ lhs: ShareUploadRecoveryBatch,
        _ rhs: ShareUploadRecoveryBatch
    ) -> Bool {
        guard lhs.version == rhs.version,
              lhs.id == rhs.id,
              lhs.jobs.count == rhs.jobs.count else {
            return false
        }
        return zip(lhs.jobs, rhs.jobs).allSatisfy {
            sameStableJob($0.0, $0.1)
        }
    }

    private static func sameStableJob(
        _ lhs: ShareUploadJob,
        _ rhs: ShareUploadJob
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.fileName == rhs.fileName
            && lhs.projectId == rhs.projectId
            && lhs.projectTitle == rhs.projectTitle
            && lhs.companyId == rhs.companyId
            && lhs.uploadedBy == rhs.uploadedBy
            && lhs.createdAt.timeIntervalSince1970.rounded(.down)
                == rhs.createdAt.timeIntervalSince1970.rounded(.down)
    }
}
