import Foundation

enum SupplierBillCacheError: Error, Equatable, LocalizedError {
    case invalidCompany
    case identityMismatch
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidCompany:
            return "Supplier bills require an active company."
        case .identityMismatch:
            return "Saved supplier bills do not match the active company."
        case .persistenceFailed:
            return "Saved supplier bills could not be read on this device."
        }
    }
}

@MainActor
final class SupplierBillCache {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
    }

    func saveBills(_ bills: [SupplierBillIntake], companyId: String) throws {
        let companyId = try normalizedCompanyId(companyId)
        guard bills.allSatisfy({ $0.companyId == companyId }) else {
            throw SupplierBillCacheError.identityMismatch
        }
        try persist(bills, to: billsURL(companyId: companyId))
    }

    func loadBills(companyId: String) throws -> [SupplierBillIntake] {
        let companyId = try normalizedCompanyId(companyId)
        let url = billsURL(companyId: companyId)
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        let bills: [SupplierBillIntake] = try load([SupplierBillIntake].self, from: url)
        guard bills.allSatisfy({ $0.companyId == companyId }) else {
            throw SupplierBillCacheError.identityMismatch
        }
        return bills
    }

    func saveDetail(_ detail: SupplierBillIntakeDetail, companyId: String) throws {
        let companyId = try normalizedCompanyId(companyId)
        guard detail.intake.companyId == companyId else {
            throw SupplierBillCacheError.identityMismatch
        }
        try persist(
            detail,
            to: detailURL(intakeId: detail.intake.id, companyId: companyId)
        )
    }

    func loadDetail(intakeId: String, companyId: String) throws -> SupplierBillIntakeDetail? {
        let companyId = try normalizedCompanyId(companyId)
        let url = detailURL(intakeId: intakeId, companyId: companyId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let detail: SupplierBillIntakeDetail = try load(SupplierBillIntakeDetail.self, from: url)
        guard detail.intake.companyId == companyId,
              detail.intake.id == intakeId else {
            throw SupplierBillCacheError.identityMismatch
        }
        return detail
    }

    private func persist<Value: Encodable>(_ value: Value, to url: URL) throws {
        do {
            try ensureDirectory()
            let data = try encoder.encode(value)
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch let error as SupplierBillCacheError {
            throw error
        } catch {
            throw SupplierBillCacheError.persistenceFailed
        }
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        do {
            return try decoder.decode(type, from: Data(contentsOf: url))
        } catch {
            throw SupplierBillCacheError.persistenceFailed
        }
    }

    private func ensureDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } catch {
            throw SupplierBillCacheError.persistenceFailed
        }
    }

    private func normalizedCompanyId(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw SupplierBillCacheError.invalidCompany }
        return normalized
    }

    private func billsURL(companyId: String) -> URL {
        directoryURL.appendingPathComponent("bills-\(safeKey(companyId)).json", isDirectory: false)
    }

    private func detailURL(intakeId: String, companyId: String) -> URL {
        directoryURL.appendingPathComponent(
            "detail-\(safeKey(companyId))-\(safeKey(intakeId)).json",
            isDirectory: false
        )
    }

    private func safeKey(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("OPS", isDirectory: true)
            .appendingPathComponent("SupplierBills", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
    }
}
