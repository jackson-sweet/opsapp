//
//  ProductPickerSheet.swift
//  OPS
//
//  Bottom sheet to select a product from the catalog to add as a line item.
//  Configurable products (with options) hand off to LineItemEditSheet via
//  the selectedProduct binding so the host can present the configuration
//  step. Flat products take the direct-create fast path.
//

import SwiftUI
import SwiftData

struct ProductPickerSheet: View {
    let estimateId: String
    @ObservedObject var viewModel: EstimateViewModel
    @Binding var selectedProduct: Product?
    @EnvironmentObject private var dataController: DataController

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allOptions: [ProductOption]

    @State private var searchText = ""
    @State private var products: [Product] = []
    @State private var isLoading = true

    private var filteredProducts: [Product] {
        if searchText.isEmpty { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func optionCount(for product: Product) -> Int {
        allOptions.filter { $0.productId == product.id }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    TextField("Search products...", text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2)

                Divider()
                    .background(OPSStyle.Colors.separator)
                    .padding(.top, OPSStyle.Layout.spacing2)

                if isLoading {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                } else if filteredProducts.isEmpty {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        Spacer()
                        Image(systemName: OPSStyle.Icons.productTag)
                            .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text(products.isEmpty ? "NO PRODUCTS IN CATALOG" : "NO MATCHES")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredProducts) { product in
                                Button {
                                    handleSelection(product)
                                } label: {
                                    productRow(product)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if product.id != filteredProducts.last?.id {
                                    Divider().background(OPSStyle.Colors.separator)
                                }
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle("SELECT FROM CATALOG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .task {
                await loadProducts()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(OPSStyle.Layout.largeCornerRadius)
        .presentationDragIndicator(.visible)
    }

    private func productRow(_ product: Product) -> some View {
        let count = optionCount(for: product)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text("\(product.type.rawValue.uppercased()) · \(product.basePrice, format: .currency(code: "USD"))/\(product.pricingUnit.rawValue)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    if count > 0 {
                        Text("· \(count) OPTION\(count == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            Spacer()
            Image(systemName: count > 0 ? "slider.horizontal.3" : "plus.circle.fill")
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private func handleSelection(_ product: Product) {
        if optionCount(for: product) > 0 {
            selectedProduct = product
            dismiss()
            return
        }
        Task {
            await viewModel.addLineItem(
                estimateId: estimateId,
                description: product.name,
                type: product.type,
                quantity: 1,
                unitPrice: product.basePrice,
                isOptional: false,
                productId: product.id,
                taskTypeId: product.taskTypeId,
                unit: product.pricingUnit.rawValue
            )
            if viewModel.error == nil { dismiss() }
        }
    }

    private func loadProducts() async {
        guard let companyId = dataController.currentUser?.companyId else {
            isLoading = false
            return
        }
        let descriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.companyId == companyId && $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        if let local = try? modelContext.fetch(descriptor), !local.isEmpty {
            products = local
            isLoading = false
            return
        }
        let repo = ProductRepository(companyId: companyId)
        do {
            let dtos = try await repo.fetchAll()
            products = dtos.map { $0.toModel() }
        } catch {
            // Silently fail — user can still add custom line items
        }
        isLoading = false
    }
}
