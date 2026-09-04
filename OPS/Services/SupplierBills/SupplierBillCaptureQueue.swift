import Foundation

struct QueuedSupplierBillCapture: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let companyId: String
    let documentKind: SupplierDocumentKind
    let originalFilename: String
    let storedFilename: String
    let sizeBytes: Int64
    let queuedAt: Date
}

enum SupplierBillCaptureQueueError: Error, Equatable, LocalizedError {
    case invalidPDF
    case fileTooLarge
    case queueFull
    case invalidCompany
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "Choose an original PDF invoice."
        case .fileTooLarge: return "Supplier bill PDFs must be 20 MB or smaller."
        case .queueFull: return "Sync queued supplier bills before adding another."
        case .invalidCompany: return "Supplier bills require an active company."
        case .persistenceFailed: return "The supplier bill could not be saved on this device."
        }
    }
}

@MainActor
final class SupplierBillCaptureQueue {
    private static let maxDocumentBytes: Int64 = 20 * 1_024 * 1_024
    private static let maxQueuedDocuments = 25

    private let directoryURL: URL
    private let manifestURL: URL
    private let fileManager: FileManager
    private let idProvider: () -> String
    private let dateProvider: () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        idProvider: @escaping () -> String = { UUID().uuidString },
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        manifestURL = self.directoryURL.appendingPathComponent("queue.json", isDirectory: false)
        self.idProvider = idProvider
        self.dateProvider = dateProvider
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func loadQueue() throws -> [QueuedSupplierBillCapture] {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        do {
            return try decoder.decode(
                [QueuedSupplierBillCapture].self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw SupplierBillCaptureQueueError.persistenceFailed
        }
    }

    func loadQueue(companyId: String) throws -> [QueuedSupplierBillCapture] {
        try loadQueue().filter { $0.companyId == companyId }
    }

    @discardableResult
    func enqueue(
        sourceURL: URL,
        originalFilename: String,
        documentKind: SupplierDocumentKind,
        companyId: String
    ) throws -> QueuedSupplierBillCapture {
        let companyId = companyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !companyId.isEmpty else {
            throw SupplierBillCaptureQueueError.invalidCompany
        }
        let fileData: Data
        do {
            fileData = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        } catch {
            throw SupplierBillCaptureQueueError.invalidPDF
        }
        guard fileData.count >= 5, fileData.prefix(5) == Data("%PDF-".utf8) else {
            throw SupplierBillCaptureQueueError.invalidPDF
        }
        guard Int64(fileData.count) <= Self.maxDocumentBytes else {
            throw SupplierBillCaptureQueueError.fileTooLarge
        }

        var queue = try loadQueue()
        guard queue.count < Self.maxQueuedDocuments else {
            throw SupplierBillCaptureQueueError.queueFull
        }

        let id = idProvider()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let storedFilename = "\(id).pdf"
        let item = QueuedSupplierBillCapture(
            id: id,
            companyId: companyId,
            documentKind: documentKind,
            originalFilename: Self.safeFilename(originalFilename),
            storedFilename: storedFilename,
            sizeBytes: Int64(fileData.count),
            queuedAt: dateProvider()
        )

        do {
            try ensureDirectory()
            let storedURL = directoryURL.appendingPathComponent(storedFilename, isDirectory: false)
            try fileData.write(to: storedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            queue.append(item)
            do {
                try persist(queue)
            } catch {
                try? fileManager.removeItem(at: storedURL)
                throw error
            }
            return item
        } catch let error as SupplierBillCaptureQueueError {
            throw error
        } catch {
            throw SupplierBillCaptureQueueError.persistenceFailed
        }
    }

    func documentURL(for item: QueuedSupplierBillCapture) -> URL? {
        let url = directoryURL.appendingPathComponent(item.storedFilename, isDirectory: false)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func remove(_ item: QueuedSupplierBillCapture) throws {
        var queue = try loadQueue()
        queue.removeAll { $0.id == item.id }
        do {
            try ensureDirectory()
            try persist(queue)
            if let url = documentURL(for: item) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw SupplierBillCaptureQueueError.persistenceFailed
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    private func persist(_ queue: [QueuedSupplierBillCapture]) throws {
        let data = try encoder.encode(queue)
        try data.write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("OPS", isDirectory: true)
            .appendingPathComponent("SupplierBills", isDirectory: true)
    }

    private static func safeFilename(_ filename: String) -> String {
        let leaf = URL(fileURLWithPath: filename).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return leaf.isEmpty ? "supplier-bill.pdf" : leaf
    }
}
