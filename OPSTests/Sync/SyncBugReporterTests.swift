import Foundation
import Supabase
import XCTest
@testable import OPS

final class SyncBugReporterTests: XCTestCase {
    func testPermanentRLSUsesSameFingerprintAcrossRowsAndWrappedErrors() throws {
        let capture = SyncBugReportCapture()
        let reporter = capture.reporter
        let first = PostgrestError(detail: "customer secret", hint: "token secret", code: "42501", message: "row customer-a rejected")
        let second = SyncError.apiError(PostgrestError(detail: nil, hint: nil, code: "42501", message: "row customer-b rejected"))
        for error in [first as Error, second] {
            reporter.reportPermanent(error, entityType: "projectTask", operationType: "update", identity: capture.identity)
        }
        let reports = capture.reports
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports.first, reports.last, "Row contents and wrapper type cannot split one failure into different tickets")
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.screen, "Sync.projectTask.update")
        XCTAssertEqual(report.errorCode, "PG_42501")
        XCTAssertEqual(report.metadata, ["entity_type": "projectTask", "operation_type": "update", "error_code": "PG_42501"])
        XCTAssertFalse(report.summary.contains("secret"))
        XCTAssertFalse(report.summary.contains("customer"))
    }

    func testDifferentOperationsEntitiesAndTypedErrorsStayDistinct() {
        let capture = SyncBugReportCapture()
        for (entity, operation, code) in [("projectTask", "update", "42501"), ("projectTask", "create", "42501"), ("client", "update", "42501"), ("projectTask", "update", "23514")] {
            capture.reporter.reportPermanent(PostgrestError(detail: nil, hint: nil, code: code, message: "private"), entityType: entity, operationType: operation, identity: capture.identity)
        }
        XCTAssertEqual(Set(capture.reports.map { $0.screen + ":" + $0.errorCode }).count, 4)
    }

    func testTransientAuthCancellationAndUnboundFailuresNeverReport() {
        let capture = SyncBugReportCapture()
        let errors: [Error] = [CancellationError(), URLError(.cancelled), URLError(.notConnectedToInternet), SyncError.authExpired, SyncError.serverError(statusCode: 503, message: "private"), PostgrestError(detail: nil, hint: nil, code: "40001", message: "private"), SiteVisitRepositoryError.authorization("private")]
        for error in errors {
            capture.reporter.reportPermanent(error, entityType: "projectTask", operationType: "update", identity: capture.identity)
        }
        capture.reporter.reportPermanent(SyncError.serverRowMissing(table: "private", id: "private"), entityType: "projectTask", operationType: "update", identity: nil)
        XCTAssertTrue(capture.reports.isEmpty)
    }

    func testAccountChangeDropsDelayedFailure() {
        let capture = SyncBugReportCapture()
        let original = capture.identity
        capture.identity = .init(companyID: "company-b", userID: original.userID, firebaseUserID: original.firebaseUserID)
        capture.reporter.reportPermanent(SyncError.serverEditRefused(table: "projects", id: "private"), entityType: "project", operationType: "update", identity: original)
        XCTAssertTrue(capture.reports.isEmpty)
    }

    func testUnknownInputsAndErrorCodesCannotLeakIntoReport() throws {
        let capture = SyncBugReportCapture()
        capture.reporter.reportPermanent(PostgrestError(detail: "secret detail", hint: "secret hint", code: "42501 secret", message: "secret message"), entityType: "secret customer", operationType: "secret payload", identity: capture.identity)
        let report = try XCTUnwrap(capture.reports.first)
        XCTAssertEqual(report.screen, "Sync.unknown.unknown")
        XCTAssertEqual(report.errorCode, "PERMANENT_UNCLASSIFIED")
        XCTAssertFalse(report.summary.contains("secret"))
        XCTAssertFalse(report.metadata.values.contains(where: { $0.contains("secret") }))
    }

    func testInboundTelemetryReportsPermanentFailureWithoutChangingAnalytics() async {
        let capture = SyncBugReportCapture()
        let error = PostgrestError(detail: nil, hint: nil, code: "42501", message: "private row")
        let work = SyncTelemetry.logError(entityType: "projectTask", error: error, isFullSync: true, companyId: capture.identity.companyID, userId: capture.identity.firebaseUserID, reportIdentity: capture.identity, bugReporter: capture.reporter, persistEvent: { _, _, bytes in
            let properties = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            XCTAssertEqual(properties?["event_name"] as? String, "sync_entity_failed")
            XCTAssertEqual(properties?["sync_phase"] as? String, "full")
        })
        await work.value
        XCTAssertEqual(capture.reports.count, 1)
        XCTAssertEqual(capture.reports.first?.screen, "Sync.projectTask.pull")
        XCTAssertEqual(capture.reports.first?.errorCode, "PG_42501")
    }

    func testInboundLateCompletionCannotReportAfterAccountSwitch() async {
        let capture = SyncBugReportCapture()
        let original = capture.identity
        capture.identity = .init(companyID: original.companyID, userID: original.userID, firebaseUserID: "replacement-Firebase")
        let work = SyncTelemetry.logError(entityType: "projectTask", error: SyncError.serverRowMissing(table: "private", id: "private"), isFullSync: false, companyId: original.companyID, userId: original.firebaseUserID, reportIdentity: original, bugReporter: capture.reporter, persistEvent: { _, _, _ in })
        await work.value
        XCTAssertTrue(capture.reports.isEmpty)
    }
}

/// Capture the new report boundary without contacting Supabase. Both outbound
/// actors use this same thread-safe sink so tests observe the real hook.
final class SyncBugReportCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedIdentity = AutoBugReportIdentity(companyID: "company-a", userID: "user-a", firebaseUserID: "firebase-A")
    private var storedReports: [SyncBugReporter.Report] = []
    var identity: AutoBugReportIdentity {
        get { lock.withLock { storedIdentity } }
        set { lock.withLock { storedIdentity = newValue } }
    }
    var reports: [SyncBugReporter.Report] { lock.withLock { storedReports } }
    var reporter: SyncBugReporter {
        SyncBugReporter(currentIdentity: { self.identity }, sink: { report in
            self.lock.withLock { self.storedReports.append(report) }
        })
    }
}
