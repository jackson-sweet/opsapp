import Foundation

enum SupplierBillCaptureResult: Equatable {
    case uploaded(SupplierBillIntakeDetail)
    case queued
    case needsAttention(String)
}

@MainActor
final class SupplierBillIntakeViewModel: ObservableObject {
    @Published private(set) var bills: [SupplierBillIntake] = []
    @Published private(set) var selectedDetail: SupplierBillIntakeDetail?
    @Published private(set) var pendingCaptureCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var isSyncing = false
    @Published private(set) var isUsingCachedData = false
    @Published var error: String?

    private let service: SupplierBillIntakeServicing
    private let queue: SupplierBillCaptureQueue
    private let cache: SupplierBillCache
    private var companyId: String?

    init() {
        service = SupplierBillIntakeService()
        queue = SupplierBillCaptureQueue()
        cache = SupplierBillCache()
    }

    init(
        service: SupplierBillIntakeServicing,
        queue: SupplierBillCaptureQueue,
        cache: SupplierBillCache? = nil
    ) {
        self.service = service
        self.queue = queue
        self.cache = cache ?? SupplierBillCache()
    }

    func setup(companyId: String) {
        let normalized = companyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if self.companyId != normalized {
            self.companyId = normalized
            selectedDetail = nil
            do {
                bills = try cache.loadBills(companyId: normalized)
                isUsingCachedData = !bills.isEmpty
            } catch {
                bills = []
                isUsingCachedData = false
                self.error = error.localizedDescription
            }
        }
        refreshPendingCount()
    }

    func load() async {
        guard let companyId else { return }
        isLoading = true
        defer { isLoading = false }

        await syncPendingCaptures()
        do {
            let loaded = try await service.list(stage: nil)
            guard loaded.allSatisfy({ $0.companyId == companyId }) else {
                throw SupplierBillIntakeServiceError.identityMismatch
            }
            bills = loaded
            try? cache.saveBills(loaded, companyId: companyId)
            isUsingCachedData = false
            error = nil
        } catch {
            isUsingCachedData = !bills.isEmpty
            if !error.isCancellation {
                self.error = error.localizedDescription
            }
        }
    }

    func loadDetail(intakeId: String) async {
        guard let companyId else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            selectedDetail = try cache.loadDetail(intakeId: intakeId, companyId: companyId)
        } catch {
            selectedDetail = nil
        }
        do {
            let detail = try await service.detail(intakeId: intakeId)
            guard detail.intake.companyId == companyId else {
                throw SupplierBillIntakeServiceError.identityMismatch
            }
            selectedDetail = detail
            try? cache.saveDetail(detail, companyId: companyId)
            upsert(detail.intake)
            error = nil
        } catch {
            if !error.isCancellation {
                self.error = error.localizedDescription
            }
        }
    }

    func clearDetail() {
        selectedDetail = nil
    }

    func capture(
        sourceURL: URL,
        originalFilename: String,
        documentKind: SupplierDocumentKind
    ) async throws -> SupplierBillCaptureResult {
        guard let companyId else {
            throw SupplierBillCaptureQueueError.invalidCompany
        }
        let item = try queue.enqueue(
            sourceURL: sourceURL,
            originalFilename: originalFilename,
            documentKind: documentKind,
            companyId: companyId
        )
        refreshPendingCount()

        do {
            let detail = try await upload(item, companyId: companyId)
            try? cache.saveDetail(detail, companyId: companyId)
            upsert(detail.intake)
            refreshPendingCount()
            error = nil
            return .uploaded(detail)
        } catch {
            // The private PDF stays in the durable queue. Losing connectivity
            // after a field capture is expected, not a failed capture.
            refreshPendingCount()
            return captureFailureResult(error)
        }
    }

    func syncPendingCaptures() async {
        guard let companyId, !isSyncing else { return }
        let pending: [QueuedSupplierBillCapture]
        do {
            pending = try queue.loadQueue(companyId: companyId)
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard !pending.isEmpty else {
            pendingCaptureCount = 0
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            refreshPendingCount()
        }
        for item in pending {
            do {
                let detail = try await upload(item, companyId: companyId)
                try? cache.saveDetail(detail, companyId: companyId)
                upsert(detail.intake)
            } catch {
                // Preserve this capture and every later one. The next app
                // refresh retries with the same stable idempotency identity.
                if !isRetryable(error) {
                    self.error = error.localizedDescription
                }
                break
            }
        }
    }

    private func upload(
        _ item: QueuedSupplierBillCapture,
        companyId: String
    ) async throws -> SupplierBillIntakeDetail {
        guard item.companyId == companyId,
              let documentURL = queue.documentURL(for: item) else {
            throw SupplierBillIntakeServiceError.identityMismatch
        }
        let detail = try await service.capture(job: item, documentURL: documentURL)
        guard detail.intake.id.lowercased() == item.id.lowercased(),
              detail.intake.companyId == companyId else {
            throw SupplierBillIntakeServiceError.identityMismatch
        }
        try queue.remove(item)
        return detail
    }

    private func upsert(_ bill: SupplierBillIntake) {
        bills.removeAll { $0.id == bill.id }
        bills.append(bill)
        bills.sort { $0.updatedAt > $1.updatedAt }
        if let companyId {
            try? cache.saveBills(bills, companyId: companyId)
        }
    }

    private func refreshPendingCount() {
        guard let companyId else {
            pendingCaptureCount = 0
            return
        }
        do {
            pendingCaptureCount = try queue.loadQueue(companyId: companyId).count
        } catch {
            pendingCaptureCount = 0
            self.error = error.localizedDescription
        }
    }

    private func captureFailureResult(_ error: Error) -> SupplierBillCaptureResult {
        isRetryable(error) ? .queued : .needsAttention(error.localizedDescription)
    }

    private func isRetryable(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let serviceError = error as? SupplierBillIntakeServiceError else { return false }
        if case .unavailable = serviceError { return true }
        return false
    }
}
