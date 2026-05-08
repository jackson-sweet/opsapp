//
//  CatalogProductsListView.swift
//  OPS
//
//  Products surface for the CATALOG tab. Lists every Product the company
//  has authored, with type/recipe filters and a tail count. Tapping a row
//  navigates into ProductDetailView for read-only options/modifiers/recipe
//  inspection plus light editing of base fields.
//
//  The `Catalog` prefix is retained to keep the rename diff isolated.
//  When future phases revisit naming the struct can collapse back to
//  `ProductsListView` without colliding with anything else.
//

import SwiftUI
import SwiftData

struct CatalogProductsListView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @Query private var allProducts: [Product]
    @Query private var allMaterials: [ProductMaterial]
    @Query private var allOptions: [ProductOption]

    @State private var selectedFilter: ProductFilter = .all
    @State private var searchText: String = ""

    enum ProductFilter: String, CaseIterable, Identifiable {
        case all
        case service
        case good
        case withRecipe

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:        return "ALL"
            case .service:    return "SERVICE"
            case .good:       return "GOOD"
            case .withRecipe: return "WITH RECIPE"
            }
        }
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyProducts: [Product] {
        allProducts.filter { $0.companyId == companyId && $0.isActive }
    }

    private var productIdsWithRecipe: Set<String> {
        Set(allMaterials.map(\.productId))
    }

    private var filteredProducts: [Product] {
        var result = companyProducts
        switch selectedFilter {
        case .all:
            break
        case .service:
            result = result.filter { $0.kind == .service }
        case .good:
            result = result.filter { $0.kind == .good }
        case .withRecipe:
            let withRecipe = productIdsWithRecipe
            result = result.filter { withRecipe.contains($0.id) }
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                ($0.productDescription ?? "").localizedCaseInsensitiveContains(trimmed) ||
                ($0.sku ?? "").localizedCaseInsensitiveContains(trimmed)
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func optionCount(for productId: String) -> Int {
        allOptions.filter { $0.productId == productId }.count
    }

    private func recipeCount(for productId: String) -> Int {
        allMaterials.filter { $0.productId == productId }.count
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                filterBar
                Divider().background(OPSStyle.Colors.separator)

                if filteredProducts.isEmpty {
                    emptyState
                } else {
                    productList
                }
            }
        }
        .navigationBarHidden(true)
        .trackScreen("Catalog.Products")
    }

    // MARK: - Sub-views

    private var searchBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField("Search products…", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(ProductFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    private func filterChip(_ filter: ProductFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedFilter = filter
            }
        } label: {
            Text(filter.label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(
                    isSelected
                        ? OPSStyle.Colors.cardBackground
                        : OPSStyle.Colors.cardBackgroundDark
                )
                .cornerRadius(OPSStyle.Layout.chipRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .stroke(
                            isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var productList: some View {
        ScrollView {
            LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(filteredProducts) { product in
                    NavigationLink {
                        ProductDetailView(product: product)
                    } label: {
                        ProductRow(
                            product: product,
                            optionCount: optionCount(for: product.id),
                            recipeCount: recipeCount(for: product.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    })
                }

                productCount
                Color.clear.frame(height: 100) // FAB clearance
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }

    private var productCount: some View {
        Text("[ \(filteredProducts.count) PRODUCTS ]")
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.top, OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Text(emptyStateMessage)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "// NO MATCHES"
        }
        if companyProducts.isEmpty {
            return "// NO PRODUCTS YET — TAP + TO ADD"
        }
        return "// NO PRODUCTS MATCH FILTER"
    }
}

// MARK: - Row

private struct ProductRow: View {
    let product: Product
    let optionCount: Int
    let recipeCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            // Leading thumbnail when the product has one. Renders at the
            // same 40x40pt slot every row uses regardless of image presence
            // so the row layout stays in lockstep across the list — even
            // products without a thumbnail get a hairline placeholder so
            // the name column doesn't reflow when scrolling between rows.
            thumbnailLeading

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(product.name)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(priceLabel)
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    kindChip
                    if optionCount > 0 {
                        metadataChip(label: "\(optionCount) OPT")
                    }
                    if recipeCount > 0 {
                        metadataChip(label: "\(recipeCount) RECIPE")
                    }
                    if let sku = product.sku, !sku.isEmpty {
                        Text(sku)
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, 2)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    /// Leading 40x40 thumbnail slot for the row. AsyncImage handles
    /// fetch + decode + memory cache via URLCache; we keep an empty
    /// placeholder of the same size for rows without an image so the row
    /// alignment doesn't shift between rows. Border + radius mirror the
    /// rest of the catalog's card chrome.
    @ViewBuilder
    private var thumbnailLeading: some View {
        let size: CGFloat = 40
        Group {
            if let urlString = product.thumbnailUrl,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.clear
                    case .empty:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(OPSStyle.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var kindChip: some View {
        Text(product.kind.rawValue.uppercased())
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func metadataChip(label: String) -> some View {
        Text(label)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private var priceLabel: String {
        let priceFormatter = NumberFormatter()
        priceFormatter.numberStyle = .currency
        priceFormatter.currencyCode = "USD"
        priceFormatter.maximumFractionDigits = 2
        priceFormatter.minimumFractionDigits = 0
        let priceString = priceFormatter.string(from: NSNumber(value: product.basePrice)) ?? "$0"
        let suffix = pricingUnitSuffix(product.pricingUnit)
        return suffix.isEmpty ? priceString : "\(priceString) \(suffix)"
    }

    private func pricingUnitSuffix(_ unit: ProductPricingUnit) -> String {
        switch unit {
        case .flatRate:    return ""
        case .each:        return "/ ea"
        case .linearFoot:  return "/ ft"
        case .sqft:        return "/ sqft"
        case .hour:        return "/ hr"
        case .day:         return "/ day"
        }
    }
}
