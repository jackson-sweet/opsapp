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
    @Query private var companyDefaults: [CompanyDefaultProduct]

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

    /// Which `DesignComponentType` the picker is filling for, derived from
    /// the current selection. Drives the company-default highlighting per
    /// deck-catalog integration spec § 4.4 — the picker pre-pins the
    /// default Product (when one exists) at the top of the list with a
    /// "// DEFAULT" tag.
    private var surfaceContext: DesignComponentType {
        if viewModel.selection.hasEdges {
            // Stair-context wins over railing when the selected edge
            // already carries a stair config — assigning more material
            // there is presumptively for the stair set.
            let firstId = viewModel.selection.selectedEdgeIds.first
            if let firstId, let edge = viewModel.findEdge(byId: firstId), edge.stairConfig != nil {
                return .stairSet
            }
            return .railing
        }
        return .deckBoard
    }

    /// Company default Product id for the current `surfaceContext`, when
    /// the company has set one. Drives the "// DEFAULT" tag in the row.
    private var defaultProductId: String? {
        let companyId = viewModel.deckDesign.companyId
        return companyDefaults.first(where: {
            $0.companyId == companyId && $0.componentType == surfaceContext
        })?.productId
    }

    /// `filteredProducts` with the company default (if any) hoisted to
    /// the top so it's the first thing the user sees.
    private var orderedProducts: [Product] {
        guard let pid = defaultProductId,
              let pinned = filteredProducts.first(where: { $0.id == pid }) else {
            return filteredProducts
        }
        let rest = filteredProducts.filter { $0.id != pid }
        return [pinned] + rest
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
                        ForEach(orderedProducts) { product in
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
        // Gate-detection per deck-catalog spec § 3.5 — products whose
        // category (legacy free-text on Product) contains "gate" auto-flag
        // the assignment as a gate, which drives the gate-component
        // emission on the parent edge. The user can override later via
        // the property sheet if the inference is wrong.
        let isGate = product.category?.lowercased().contains("gate") == true
        Button {
            let item = AssignedItem(
                productId: product.id,
                name: product.name,
                unitType: mapped,
                unitPrice: product.basePrice,
                taskTypeId: product.taskTypeId,
                taskTypeColor: taskTypes.first(where: { $0.id == product.taskTypeId && $0.deletedAt == nil })?.color,
                isGate: isGate
            )
            applyMaterial(item)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Circle()
                    .fill(taskTypeColor(for: product.taskTypeId) ?? OPSStyle.Colors.tertiaryText.opacity(0.3))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(product.name)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        if defaultProductId == product.id {
                            Text("// DEFAULT")
                                .font(OPSStyle.Typography.smallCaption.monospaced())
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    OPSStyle.Colors.primaryAccent.opacity(0.12)
                                        .clipShape(Capsule())
                                )
                        }
                    }

                    HStack(spacing: 4) {
                        Text(String(format: "$%.2f / %@", product.basePrice, isLinearMode ? "lin ft" : "sq ft"))
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
