import CryptoKit
import XCTest
@testable import OPS

@MainActor
final class RecoveryVaultHeaderTests: XCTestCase {
    func testAuthenticatedHeadersAreScopedToExactUserAndCompany() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keyData = Data(repeating: 7, count: 32)
        try writeHeader(user: "operator", company: "company", visit: "visit-a", at: root.appendingPathComponent("a"), key: keyData)
        try writeHeader(user: "other", company: "company", visit: "visit-b", at: root.appendingPathComponent("b"), key: keyData)
        let vault = SiteVisitRecoveryVault(rootDirectory: root, keyProvider: { keyData }, mediaURLResolver: { _ in nil })
        let ids = try await vault.quarantinedVisitIds(userId: "OPERATOR", companyId: "COMPANY")
        XCTAssertEqual(ids, ["visit-a"])
    }

    func testCorruptHeaderIsAnErrorRatherThanEmptyRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data("invalid encrypted packet".utf8).write(to: root.appendingPathComponent("a/bundle.opsvault"))
        let vault = SiteVisitRecoveryVault(rootDirectory: root, keyProvider: { Data(repeating: 7, count: 32) }, mediaURLResolver: { _ in nil })
        do {
            _ = try await vault.quarantinedVisitIds(userId: "operator", companyId: "company")
            XCTFail("Unreadable protected work must preserve the previous status snapshot")
        } catch { }
    }

    func testAbsentVaultDoesNotRequestAnEncryptionKey() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = SiteVisitRecoveryVault(rootDirectory: root, keyProvider: { throw CocoaError(.fileReadNoPermission) }, mediaURLResolver: { _ in nil })
        let ids = try await vault.quarantinedVisitIds(userId: "operator", companyId: "company")
        XCTAssertTrue(ids.isEmpty)
    }

    private func writeHeader(user: String, company: String, visit: String, at root: URL, key: Data) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let json = try JSONSerialization.data(withJSONObject: ["version": 1, "identity": ["userId": user, "companyId": company], "siteVisitId": visit, "quarantineReason": "parent_deleted"])
        let sealed = try AES.GCM.seal(json, using: SymmetricKey(data: key))
        try XCTUnwrap(sealed.combined).write(to: root.appendingPathComponent("bundle.opsvault"))
    }
}
