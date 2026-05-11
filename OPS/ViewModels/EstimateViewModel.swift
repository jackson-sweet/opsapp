//
//  EstimateViewModel.swift
//  OPS
//
//  ViewModel for Estimates — reads from SwiftData (populated via InboundProcessor),
//  performs server mutations (line items, status changes), and refreshes local records.
//

import SwiftUI
import SwiftData

@MainActor
class EstimateViewModel: ObservableObject {
    @Published var estimates: [Estimate] = []
    @Published var selectedFilter: EstimateFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private var repository: EstimateRepository?
    private var modelContext: ModelContext?

    enum EstimateFilter: String, CaseIterable {
        case all      = "ALL"
        case draft    = "DRAFT"
        case sent     = "SENT"
        case approved = "APPROVED"
    }

    var filteredEstimates: [Estimate] {
        var result = estimates
        switch selectedFilter {
        case .all:      break
        case .draft:    result = result.filter { $0.status == .draft }
        case .sent:     result = result.filter { $0.status == .sent || $0.status == .viewed }
        case .approved: result = result.filter { $0.status == .approved }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.estimateNumber.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    func setup(companyId: String, modelContext: ModelContext) {
        self.repository = EstimateRepository(companyId: companyId)
        self.modelContext = modelContext
        reloadFromLocal()
    }

    /// Runs on the main thread (SwiftData's ModelContext is not thread-safe).
    /// Capped to 500 most-recent estimates to bound worst-case hitch on large histories.
    func reloadFromLocal() {
        guard let ctx = modelContext else { return }
        var descriptor = FetchDescriptor<Estimate>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        estimates = (try? ctx.fetch(descriptor)) ?? []
    }

    /// Legacy entry point — preserved for existing callers. Now just re-reads local state.
    func loadEstimates() async {
        reloadFromLocal()
    }

    func lineItems(for estimateId: String) -> [EstimateLineItem] {
        guard let ctx = modelContext else { return [] }
        let descriptor = FetchDescriptor<EstimateLineItem>(
            predicate: #Predicate { $0.estimateId == estimateId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return (try? ctx.fetch(descriptor)) ?? []
    }

    func createEstimate(title: String, companyId: String, opportunityId: String? = nil, clientId: String? = nil) async -> Estimate? {
        guard let repo = repository, let ctx = modelContext else { return nil }
        let dto = CreateEstimateDTO(
            companyId: companyId,
            opportunityId: opportunityId,
            clientId: clientId,
            title: title
        )
        do {
            let created = try await repo.create(dto)
            let est = created.toModel()
            est.lastSyncedAt = Date()
            ctx.insert(est)
            if let lineItems = created.lineItems {
                for liDTO in lineItems {
                    ctx.insert(liDTO.toModel())
                }
            }
            try ctx.save()
            reloadFromLocal()
            return est
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func addLineItem(
        estimateId: String,
        description: String,
        type: LineItemType,
        quantity: Double,
        unitPrice: Double,
        isOptional: Bool,
        productId: String? = nil,
        taskTypeId: String? = nil,
        unit: String? = nil,
        configuredOptionsJSON: String? = nil,
        resolvedUnitPrice: Double? = nil,
        resolvedOptionsLabel: String? = nil
    ) async {
        guard let repo = repository else { return }
        let existing = lineItems(for: estimateId)
        let sortOrder = existing.count
        let configuredOptions = configuredOptionsJSON.map { RawJSONColumn(rawJSONString: $0) }
        let dto = CreateLineItemDTO(
            estimateId: estimateId,
            productId: productId,
            name: nil,
            description: description,
            quantity: quantity,
            unitPrice: unitPrice,
            unit: unit,
            sortOrder: sortOrder,
            isOptional: isOptional,
            taskTypeId: taskTypeId,
            type: type.rawValue,
            category: nil,
            parentLineItemId: nil,
            configuredOptions: configuredOptions,
            resolvedUnitPrice: resolvedUnitPrice,
            resolvedOptionsLabel: resolvedOptionsLabel
        )
        do {
            _ = try await repo.addLineItem(dto)
            await refreshEstimate(estimateId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateLineItem(id: String, estimateId: String, description: String?, quantity: Double?, unitPrice: Double?, isOptional: Bool?) async {
        guard let repo = repository else { return }
        let dto = UpdateLineItemDTO(
            description: description,
            quantity: quantity,
            unitPrice: unitPrice,
            isOptional: isOptional
        )
        do {
            _ = try await repo.updateLineItem(id, fields: dto)
            await refreshEstimate(estimateId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteLineItem(id: String, estimateId: String) async {
        guard let repo = repository else { return }
        do {
            try await repo.deleteLineItem(id)
            await refreshEstimate(estimateId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateTitle(estimateId: String, title: String) async {
        guard let repo = repository, let ctx = modelContext else { return }
        do {
            try await repo.updateTitle(estimateId, title: title)
            let descriptor = FetchDescriptor<Estimate>(
                predicate: #Predicate { $0.id == estimateId }
            )
            if let existing = try ctx.fetch(descriptor).first {
                existing.title = title
                try ctx.save()
            }
            reloadFromLocal()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sendEstimate(_ estimate: Estimate) async {
        await updateStatus(estimate, to: .sent)
    }

    func markApproved(_ estimate: Estimate) async {
        await updateStatus(estimate, to: .approved)
    }

    func convertToInvoice(_ estimate: Estimate) async {
        guard let repo = repository else { return }
        do {
            _ = try await repo.convertToInvoice(estimateId: estimate.id)
            estimate.status = .converted
            await refreshEstimate(estimate.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Create an invoice from selected line items at specified percentages.
    func createProgressInvoice(
        from estimate: Estimate,
        lineItemSelections: [(lineItemId: String, percentage: Double)]
    ) async -> Bool {
        guard let repo = repository else { return false }
        do {
            _ = try await repo.createProgressInvoice(
                estimateId: estimate.id,
                lineItemSelections: lineItemSelections
            )
            await refreshEstimate(estimate.id)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Targeted refresh from server — used for Spotlight taps on stale local copies.
    func refreshFromServer(estimateId: String) async {
        await refreshEstimate(estimateId)
    }

    private func updateStatus(_ estimate: Estimate, to status: EstimateStatus) async {
        guard let repo = repository else { return }
        let originalStatus = estimate.status
        estimate.status = status
        do {
            let updated = try await repo.updateStatus(estimate.id, status: status)
            estimate.status = EstimateStatus(rawValue: updated.status) ?? status
            await refreshEstimate(estimate.id)
        } catch {
            estimate.status = originalStatus
            self.error = error.localizedDescription
        }
    }

    private func refreshEstimate(_ estimateId: String) async {
        guard let repo = repository, let ctx = modelContext else { return }
        do {
            let dto = try await repo.fetchOne(estimateId)
            let descriptor = FetchDescriptor<Estimate>(
                predicate: #Predicate { $0.id == estimateId }
            )
            if let existing = try ctx.fetch(descriptor).first {
                let fresh = dto.toModel()
                existing.status = fresh.status
                existing.subtotal = fresh.subtotal
                existing.taxAmount = fresh.taxAmount
                existing.total = fresh.total
                existing.title = fresh.title
                existing.updatedAt = fresh.updatedAt
                existing.lastSyncedAt = Date()
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                ctx.insert(model)
            }

            // Refresh line items: insert new ones, remove any that the server dropped
            let freshLineItemIds: Set<String> = Set((dto.lineItems ?? []).map { $0.id })
            if let lineItems = dto.lineItems {
                for liDTO in lineItems {
                    let liId = liDTO.id
                    let liDescriptor = FetchDescriptor<EstimateLineItem>(
                        predicate: #Predicate { $0.id == liId }
                    )
                    if try ctx.fetch(liDescriptor).first == nil {
                        ctx.insert(liDTO.toModel())
                    }
                }
            }
            // Delete any local line items that are no longer on the server
            let localDescriptor = FetchDescriptor<EstimateLineItem>(
                predicate: #Predicate { $0.estimateId == estimateId }
            )
            let local = (try? ctx.fetch(localDescriptor)) ?? []
            for item in local where !freshLineItemIds.contains(item.id) {
                ctx.delete(item)
            }

            try ctx.save()
            reloadFromLocal()
        } catch {
            // Silently fail on refresh
        }
    }
}
