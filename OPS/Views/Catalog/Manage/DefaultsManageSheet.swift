//
//  DefaultsManageSheet.swift
//  OPS
//
//  Per-company default Product per Deck Builder component_type. Drives the
//  one-click drawing → estimate adapter. The mapping table is keyed by
//  (company_id, component_type), so each row in this sheet upserts that
//  pair via CompanyDefaultProductRepository.
//

import SwiftUI
import SwiftData

struct DefaultsManageSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allProducts: [Product]
    @Query private var allDefaults: [CompanyDefaultProduct]

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyProducts: [Product] {
        allProducts
            .filter { $0.companyId == companyId && $0.isActive }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private var defaultsByType: [DesignComponentType: CompanyDefaultProduct] {
        var result: [DesignComponentType: CompanyDefaultProduct] = [:]
        for d in allDefaults where d.companyId == companyId {
            result[d.componentType] = d
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                if companyProducts.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(DesignComponentType.allCases, id: \.rawValue) { type in
                                DefaultRow(
                                    componentType: type,
                                    selectedProductId: defaultsByType[type]?.productId,
                                    products: companyProducts,
                                    onSelect: { newId in
                                        Task { await assign(componentType: type, productId: newId) }
                                    },
                                    onClear: {
                                        Task { await clear(componentType: type) }
                                    }
                                )
                            }
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.errorText)
                                    .padding(.top, OPSStyle.Layout.spacing2)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .catalogNavigationTitle("DEFAULTS")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// NO PRODUCTS YET")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Add a product before mapping defaults.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func assign(componentType: DesignComponentType, productId: String) async {
        guard !companyId.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let repo = CompanyDefaultProductRepository(companyId: companyId)
        let dto = UpsertCompanyDefaultProductDTO(
            companyId: companyId,
            componentType: componentType.rawValue,
            productId: productId
        )
        do {
            let result = try await repo.upsert(dto)
            applyDTOToLocal(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func clear(componentType: DesignComponentType) async {
        guard !companyId.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let repo = CompanyDefaultProductRepository(companyId: companyId)
        do {
            try await repo.remove(componentType: componentType.rawValue)
            // Mirror local removal
            let descriptor = FetchDescriptor<CompanyDefaultProduct>(
                predicate: #Predicate { $0.companyId == companyId && $0.componentType == componentType }
            )
            if let existing = (try? modelContext.fetch(descriptor))?.first {
                modelContext.delete(existing)
                try? modelContext.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDTOToLocal(_ dto: CompanyDefaultProductDTO) {
        guard let type = DesignComponentType(rawValue: dto.componentType) else { return }
        let descriptor = FetchDescriptor<CompanyDefaultProduct>(
            predicate: #Predicate { $0.companyId == dto.companyId && $0.componentType == type }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.productId = dto.productId
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        try? modelContext.save()
    }
}

private struct DefaultRow: View {
    let componentType: DesignComponentType
    let selectedProductId: String?
    let products: [Product]
    let onSelect: (String) -> Void
    let onClear: () -> Void

    private var selectedProductName: String {
        if let id = selectedProductId,
           let product = products.first(where: { $0.id == id }) {
            return product.name
        }
        return "—"
    }

    var body: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(componentType.displayName.uppercased())
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(selectedProductName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(selectedProductId == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                ForEach(products) { product in
                    Button {
                        onSelect(product.id)
                    } label: {
                        Label(product.name, systemImage: product.id == selectedProductId ? "checkmark" : "")
                    }
                }
                if selectedProductId != nil {
                    Divider()
                    Button(role: .destructive) {
                        onClear()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .accessibilityLabel("Set default for \(componentType.displayName)")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

// MARK: - DesignComponentType display extension

private extension DesignComponentType {
    var displayName: String {
        switch self {
        case .railing:    return "Railing"
        case .deckBoard:  return "Deck board"
        case .stairSet:   return "Stair set"
        case .gate:       return "Gate"
        case .postSet:    return "Post set"
        }
    }
}
