//
//  ProductsListView.swift
//  OPS
//
//  List of products in the service catalog — filter by type, create/edit/deactivate.
//

import SwiftUI

struct ProductsListView: View {
    @EnvironmentObject private var dataController: DataController

    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var selectedFilter: ProductFilter = .all
    @State private var searchText = ""
    @State private var showFormSheet = false
    @State private var editingProduct: Product? = nil
    @State private var showDeactivateConfirm = false
    @State private var deactivateTarget: Product? = nil

    private var repository: ProductRepository? {
        guard let companyId = dataController.currentUser?.companyId else { return nil }
        return ProductRepository(companyId: companyId)
    }

    enum ProductFilter: String, CaseIterable {
        case all      = "ALL"
        case labor    = "LABOR"
        case material = "MATERIAL"
        case other    = "OTHER"
    }

    private var filteredProducts: [Product] {
        var result = products
        switch selectedFilter {
        case .all:      break
        case .labor:    result = result.filter { $0.type == .labor }
        case .material: result = result.filter { $0.type == .material }
        case .other:    result = result.filter { $0.type == .other }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.productDescription ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    TextField("Search products...", text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
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

                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(ProductFilter.allCases, id: \.self) { filter in
                            filterChip(filter)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                }

                Divider().background(Color.white.opacity(0.15))

                // Content
                if isLoading {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                } else if filteredProducts.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(filteredProducts) { product in
                                productCard(product)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.top, OPSStyle.Layout.spacing2)
                        .padding(.bottom, 80)
                    }
                    .refreshable { await loadProducts() }
                }
            }

            // FAB
            Button {
                editingProduct = nil
                showFormSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetLarge, height: OPSStyle.Layout.touchTargetLarge)
                    .background(OPSStyle.Colors.primaryAccent)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .padding(OPSStyle.Layout.spacing3)
            .accessibilityLabel("New Product")
        }
        .navigationTitle("PRODUCTS & SERVICES")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFormSheet) {
            ProductFormSheet(
                editing: editingProduct,
                onSave: { await loadProducts() }
            )
        }
        .confirmationDialog("Deactivate Product?", isPresented: $showDeactivateConfirm) {
            Button("Deactivate", role: .destructive) {
                if let prod = deactivateTarget {
                    Task { await deactivateProduct(prod) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This product will be hidden from the catalog. Existing line items will not be affected.")
        }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { await loadProducts() }
    }

    // MARK: - Components

    private func productCard(_ product: Product) -> some View {
        Button {
            editingProduct = product
            showFormSheet = true
        } label: {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    Text(product.name)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(product.defaultPrice, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    typeBadge(product.type)

                    if let unit = product.unit, !unit.isEmpty {
                        Text("per \(unit)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    if let margin = product.marginPercent {
                        Text("[\(String(format: "%.0f", margin))% margin]")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    Spacer()

                    Button {
                        deactivateTarget = product
                        showDeactivateConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func typeBadge(_ type: LineItemType) -> some View {
        Text(type.rawValue)
            .font(OPSStyle.Typography.smallCaption)
            .fontWeight(.medium)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.horizontal, OPSStyle.Layout.spacing1 + 2)
            .padding(.vertical, 2)
            .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
            .cornerRadius(4)
    }

    private func filterChip(_ filter: ProductFilter) -> some View {
        Button(action: { selectedFilter = filter }) {
            Text(filter.rawValue)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)
                .foregroundColor(
                    selectedFilter == filter ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText
                )
                .padding(.horizontal, OPSStyle.Layout.spacing2 + 2)
                .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                .background(
                    selectedFilter == filter
                    ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                    : OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                )
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(
                            selectedFilter == filter ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: OPSStyle.Icons.productTag)
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(products.isEmpty ? "NO PRODUCTS YET" : "NO MATCHES")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if products.isEmpty {
                Text("Add products and services to your catalog")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadProducts() async {
        guard let repo = repository else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await repo.fetchAll()
            products = dtos.map { $0.toModel() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deactivateProduct(_ product: Product) async {
        guard let repo = repository else { return }
        do {
            try await repo.deactivate(product.id)
            products.removeAll { $0.id == product.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
