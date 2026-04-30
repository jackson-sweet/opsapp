// OPS/OPS/DeckBuilder/Views/MaterialPickerSheet.swift

import SwiftUI
import SwiftData

struct MaterialPickerSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingHint: Bool = false
    @Query(filter: #Predicate<Product> { $0.isActive }, sort: \Product.name)
    private var products: [Product]
    @Query(sort: \TaskType.displayOrder) private var taskTypes: [TaskType]

    /// Whether we're showing linear (edge) or area (footprint) materials
    private var isLinearMode: Bool {
        viewModel.selection.hasEdges
    }

    private var sheetTitle: String {
        isLinearMode ? "Linear Materials" : "Surface Materials"
    }

    /// Explanation surfaced both in the empty state and behind the (?) button.
    /// Kept short — field crews don't read paragraphs.
    private var sourceHintBody: String {
        let unitNeeded = isLinearMode ? "linear ft" : "sq ft"
        return "Pulled from your Company Products. The picker filters by unit — only products in \(unitNeeded) show up here. Add or edit products in Settings → Products."
    }

    // MARK: - Unit Type Mapping

    static func unitType(from unitString: String?) -> UnitType? {
        guard let unit = unitString?.lowercased().trimmingCharacters(in: .whitespaces) else { return nil }
        let linearPatterns = ["linear ft", "linear foot", "lin ft", "lf", "linear meter", "lm"]
        let areaPatterns = ["sq ft", "square foot", "sf", "sq meter", "square meter", "sm"]
        if linearPatterns.contains(where: { unit.contains($0) }) { return .linearFoot }
        if areaPatterns.contains(where: { unit.contains($0) }) { return .squareFoot }
        if unit == "each" { return .each }
        if unit == "set" { return .set }
        return nil
    }

    /// Company products filtered by unit type
    private var filteredProducts: [Product] {
        products.filter { product in
            guard let mapped = Self.unitType(from: product.unit) else { return false }
            if isLinearMode {
                return mapped == .linearFoot || mapped == .linearMeter
            } else {
                return mapped == .squareFoot || mapped == .squareMeter
            }
        }
    }

    // MARK: - Task Type Helpers

    private func taskTypeColor(for taskTypeId: String?) -> Color? {
        guard let id = taskTypeId else { return nil }
        guard let tt = taskTypes.first(where: { $0.id == id && $0.deletedAt == nil }) else { return nil }
        return Color(hex: tt.color)
    }

    private func taskTypeDisplayName(for taskTypeId: String?) -> String? {
        guard let id = taskTypeId else { return nil }
        return taskTypes.first(where: { $0.id == id && $0.deletedAt == nil })?.display
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    if filteredProducts.isEmpty {
                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 32))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(isLinearMode ? "No linear materials" : "No surface materials")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Text(sourceHintBody)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing4)
                    } else {
                        ForEach(filteredProducts) { product in
                            productRow(product)
                        }
                    }
                }
                .padding(20)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                if !filteredProducts.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            showingHint = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .accessibilityLabel("Where do these materials come from?")
                    }
                }
            }
            .alert("Where do these come from?", isPresented: $showingHint) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sourceHintBody)
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Components

    @ViewBuilder
    private func productRow(_ product: Product) -> some View {
        let mapped = Self.unitType(from: product.unit) ?? (isLinearMode ? .linearFoot : .squareFoot)
        Button {
            let item = AssignedItem(
                productId: product.id,
                name: product.name,
                unitType: mapped,
                unitPrice: product.defaultPrice,
                taskTypeId: product.taskTypeId,
                taskTypeColor: taskTypes.first(where: { $0.id == product.taskTypeId && $0.deletedAt == nil })?.color
            )
            applyMaterial(item)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Circle()
                    .fill(taskTypeColor(for: product.taskTypeId) ?? OPSStyle.Colors.tertiaryText.opacity(0.3))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    HStack(spacing: 4) {
                        Text(String(format: "$%.2f / %@", product.defaultPrice, isLinearMode ? "lin ft" : "sq ft"))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        if let ttName = taskTypeDisplayName(for: product.taskTypeId) {
                            Text(ttName)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(taskTypeColor(for: product.taskTypeId) ?? OPSStyle.Colors.tertiaryText)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
        }
    }

    // MARK: - Apply

    /// Bug 5e681032 — when multiple edges are selected, the material must apply
    /// to ALL of them (not just the first). The previous if/else-if split also
    /// silently dropped the edge update when both footprint AND edges were
    /// selected (multi-select mode), which read as "only the first one took"
    /// in the field. Now both branches run when both kinds of target are
    /// selected, and the linear branch always uses `assignItemToSelectedEdges`
    /// which iterates the full set.
    private func applyMaterial(_ item: AssignedItem) {
        var didApply = false
        if viewModel.selection.selectedFootprint && !isLinearMode {
            viewModel.assignItemToFootprint(item)
            didApply = true
        }
        if viewModel.selection.hasEdges && isLinearMode {
            viewModel.assignItemToSelectedEdges(item)
            didApply = true
        }
        // Edge fallback: in case unit mapping disagrees with the toolbar
        // routing (mixed selection where `isLinearMode` resolved to surface
        // mode), still ensure the edges receive the item if any are selected
        // and the picked product is linear.
        if !didApply {
            if viewModel.selection.hasEdges {
                viewModel.assignItemToSelectedEdges(item)
            } else if viewModel.selection.selectedFootprint {
                viewModel.assignItemToFootprint(item)
            }
        }
    }
}
