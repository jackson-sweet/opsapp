//
//  ProductPickerSheet.swift
//  OPS
//
//  Bottom sheet to select a product from the catalog to add as a line item.
//

import SwiftUI

struct ProductPickerSheet: View {
    let estimateId: String
    @ObservedObject var viewModel: EstimateViewModel
    @EnvironmentObject private var dataController: DataController

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var products: [Product] = []
    @State private var isLoading = true

    private var filteredProducts: [Product] {
        if searchText.isEmpty { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    TextField("Search products...", text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2)

                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.top, OPSStyle.Layout.spacing2)

                // Product list
                if isLoading {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                } else if filteredProducts.isEmpty {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        Spacer()
                        Image(systemName: OPSStyle.Icons.productTag)
                            .font(.system(size: 40))
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
                                    addFromProduct(product)
                                } label: {
                                    productRow(product)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if product.id != filteredProducts.last?.id {
                                    Divider().background(Color.white.opacity(0.1))
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("\(product.type.rawValue.uppercased()) · \(product.defaultPrice, format: .currency(code: "USD"))/\(product.unit ?? "ea")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .font(.system(size: 20))
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    private func addFromProduct(_ product: Product) {
        Task {
            await viewModel.addLineItem(
                estimateId: estimateId,
                description: product.name,
                type: product.type,
                quantity: 1,
                unitPrice: product.defaultPrice,
                isOptional: false,
                productId: product.id
            )
            if viewModel.error == nil { dismiss() }
        }
    }

    private func loadProducts() async {
        guard let companyId = dataController.currentUser?.companyId else {
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
