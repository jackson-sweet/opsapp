//
//  EstimateViewModel.swift
//  OPS
//
//  ViewModel for Estimates — manages estimate list, filtering, line items, and status actions.
//

import SwiftUI

@MainActor
class EstimateViewModel: ObservableObject {
    @Published var estimates: [Estimate] = []
    @Published var selectedFilter: EstimateFilter = .all
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private var repository: EstimateRepository?
    private var lineItemDTOs: [String: [EstimateLineItemDTO]] = [:]

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

    func setup(companyId: String) {
        repository = EstimateRepository(companyId: companyId)
    }

    func loadEstimates() async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await repo.fetchAll()
            estimates = dtos.map { dto in
                let est = dto.toModel()
                lineItemDTOs[est.id] = dto.lineItems
                return est
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func lineItems(for estimateId: String) -> [EstimateLineItem] {
        lineItemDTOs[estimateId]?.map { $0.toModel() } ?? []
    }

    func createEstimate(title: String, companyId: String, opportunityId: String? = nil, clientId: String? = nil) async -> Estimate? {
        guard let repo = repository else { return nil }
        let dto = CreateEstimateDTO(
            companyId: companyId,
            opportunityId: opportunityId,
            clientId: clientId,
            title: title
        )
        do {
            let created = try await repo.create(dto)
            let est = created.toModel()
            lineItemDTOs[est.id] = created.lineItems
            estimates.insert(est, at: 0)
            return est
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func addLineItem(estimateId: String, description: String, type: LineItemType, quantity: Double, unitPrice: Double, isOptional: Bool, productId: String? = nil) async {
        guard let repo = repository else { return }
        let sortOrder = (lineItemDTOs[estimateId]?.count ?? 0)
        let dto = CreateLineItemDTO(
            estimateId: estimateId,
            productId: productId,
            description: description,
            quantity: quantity,
            unitPrice: unitPrice,
            sortOrder: sortOrder,
            isOptional: isOptional,
            taskTypeId: nil,
            type: type.rawValue
        )
        do {
            let created = try await repo.addLineItem(dto)
            if lineItemDTOs[estimateId] == nil { lineItemDTOs[estimateId] = [] }
            lineItemDTOs[estimateId]?.append(created)
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
            let updated = try await repo.updateLineItem(id, fields: dto)
            if let idx = lineItemDTOs[estimateId]?.firstIndex(where: { $0.id == id }) {
                lineItemDTOs[estimateId]?[idx] = updated
            }
            await refreshEstimate(estimateId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteLineItem(id: String, estimateId: String) async {
        guard let repo = repository else { return }
        do {
            try await repo.deleteLineItem(id)
            lineItemDTOs[estimateId]?.removeAll { $0.id == id }
            await refreshEstimate(estimateId)
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
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func updateStatus(_ estimate: Estimate, to status: EstimateStatus) async {
        guard let repo = repository else { return }
        let originalStatus = estimate.status
        estimate.status = status
        do {
            let updated = try await repo.updateStatus(estimate.id, status: status)
            estimate.status = EstimateStatus(rawValue: updated.status) ?? status
            lineItemDTOs[estimate.id] = updated.lineItems
        } catch {
            estimate.status = originalStatus
            self.error = error.localizedDescription
        }
    }

    private func refreshEstimate(_ estimateId: String) async {
        guard let repo = repository else { return }
        do {
            let allDTOs = try await repo.fetchAll()
            if let dto = allDTOs.first(where: { $0.id == estimateId }),
               let idx = estimates.firstIndex(where: { $0.id == estimateId }) {
                let refreshed = dto.toModel()
                lineItemDTOs[estimateId] = dto.lineItems
                estimates[idx] = refreshed
            }
        } catch {
            // Silently fail on refresh — estimate is still locally updated
        }
    }
}
