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
    /// Catalog units are the structured source of truth for "what dimension is
    /// this product priced in" (length/area/count/...). Both iOS and ops-web
    /// write Product.unitId pointing at a row here. We join through this rather
    /// than parsing the legacy free-text `unit` field, because:
    ///   - iOS writes `unit = catalog_unit.display` (e.g. "linear_ft", "sqft"),
    ///     ops-web does the same, but neither writes consistent values
    ///     ("sqft" vs "sq ft" vs "ft²") — string parsing would miss them all.
    ///   - The `pricing_unit` text column defaults to 'each' and ops-web never
    ///     overrides it; iOS overrides it but earlier-version products are
    ///     stuck at 'each' regardless of true dimension.
    /// Bug ee787f29.
    @Query private var catalogUnits: [CatalogUnit]

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
        let unitNeeded = isLinearMode ? "a length unit (ft, m, linear_ft)" : "an area unit (sqft, m²)"
        return "Pulled from your Company Products. Only products priced in \(unitNeeded) show up here. Add or edit products and units in Settings → Products."
    }

    // MARK: - Unit Filtering

    /// Company products filtered by unit dimension. Linear (edge) mode shows
    /// length-dimensioned products; surface mode shows area-dimensioned. We
    /// intentionally drop `.other` so a stray each-priced product doesn't
    /// pollute the picker — those belong in the toolbar's quick-add path.
    /// Dimension resolution lives in `ProductUnitResolver` (shared with
    /// `AssignmentWheelView` so both surfaces behave identically).
    private var filteredProducts: [Product] {
        products.filter { product in
            let dim = ProductUnitResolver.dimension(of: product, catalogUnits: catalogUnits)
            switch dim {
            case .length: return isLinearMode
            case .area:   return !isLinearMode
            case .other:  return false
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
                    // Section 1: Company catalog (when populated).
                    if !filteredProducts.isEmpty {
                        sectionHeader("// FROM CATALOG")
                        ForEach(orderedProducts) { product in
                            productRow(product)
                        }
                    }

                    // Section 2: Built-in standards — common industry types so
                    // a fresh-install company can still spec a real material
                    // without having to populate Products first. Each pick
                    // creates an AssignedItem with no productId and a $0 base
                    // price — the operator fills in price at estimate time.
                    // Bug ee787f29 — "Material pickers still need to support
                    // some default types like house edge, parapet wall…".
                    if !builtInDefaults.isEmpty {
                        if !filteredProducts.isEmpty {
                            Divider()
                                .background(OPSStyle.Colors.separator)
                                .padding(.vertical, OPSStyle.Layout.spacing1)
                        }
                        sectionHeader("// STANDARDS")
                        ForEach(builtInDefaults, id: \.id) { standard in
                            builtInRow(standard)
                        }
                    }

                    // Empty state — only when BOTH catalog AND standards are
                    // dry (e.g. an each-priced selection where neither linear
                    // nor area standards apply). Practically rare.
                    if filteredProducts.isEmpty && builtInDefaults.isEmpty {
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
                    }
                }
                .padding(OPSStyle.Layout.spacing3_5)
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
        // Wrapped in an immediately-invoked closure because @ViewBuilder
        // rejects top-level switch statements (would be inferred as a void
        // expression). Same outcome, just packaged so the result builder
        // never sees the switch.
        let mapped: UnitType = {
            switch ProductUnitResolver.dimension(of: product, catalogUnits: catalogUnits) {
            case .length: return .linearFoot
            case .area:   return .squareFoot
            case .other:  return isLinearMode ? .linearFoot : .squareFoot
            }
        }()
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

                    HStack(spacing: OPSStyle.Layout.spacing1) {
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

    // MARK: - Built-in Standards

    /// Static built-in defaults shown in the "// STANDARDS" section. Each
    /// entry produces an `AssignedItem` with no `productId` — downstream
    /// code already handles that (estimate falls back to operator-supplied
    /// price; cut list emits a generic line). The list is filtered by
    /// `isLinearMode` so surface picks don't see railing entries.
    private var builtInDefaults: [BuiltInMaterial] {
        if isLinearMode {
            return BuiltInMaterial.linearStandards
        } else {
            return BuiltInMaterial.areaStandards
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.smallCaption.monospaced())
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .tracking(0.5)
    }

    @ViewBuilder
    private func builtInRow(_ standard: BuiltInMaterial) -> some View {
        Button {
            let item = AssignedItem(
                productId: nil,
                name: standard.name,
                unitType: isLinearMode ? .linearFoot : .squareFoot,
                unitPrice: nil,
                taskTypeId: nil,
                taskTypeColor: nil,
                isGate: standard.id.contains("gate")
            )
            applyBuiltInMaterial(item, standard: standard)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: standard.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(standard.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(standard.subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
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

    private func applyBuiltInMaterial(_ item: AssignedItem, standard: BuiltInMaterial) {
        guard isLinearMode, viewModel.selection.hasEdges else {
            applyMaterial(item)
            return
        }

        let selectedEdgeIds = Array(viewModel.selection.selectedEdgeIds)
        let material = houseEdgeMaterial(for: standard)
        var shouldAssignDeckItem = false

        for edgeId in selectedEdgeIds {
            guard let edge = viewModel.findEdge(byId: edgeId) else { continue }

            if edge.edgeType == .houseEdge {
                if let material {
                    viewModel.setHouseEdgeMaterial(edgeId, material: material)
                }
                continue
            }

            if standard.id == "std.wall.parapet" {
                viewModel.setRailing(
                    edgeId,
                    config: RailingConfig(
                        railingType: .parapetWall,
                        maxPostSpacing: RailingType.parapetWall.defaultMaxPostSpacing,
                        wallMaterial: .parapet
                    )
                )
                shouldAssignDeckItem = true
            } else if let material, edge.railingConfig?.railingType == .parapetWall {
                viewModel.setRailingWallMaterial(edgeId, material: material)
                shouldAssignDeckItem = true
            } else if standard.id.contains("gate") {
                shouldAssignDeckItem = true
            }
        }

        if shouldAssignDeckItem {
            viewModel.assignItemToSelectedEdges(item)
        }
    }

    private func houseEdgeMaterial(for standard: BuiltInMaterial) -> HouseEdgeMaterial? {
        switch standard.id {
        case "std.wall.parapet": return .parapet
        case "std.cladding.stucco": return .stucco
        case "std.cladding.hardie": return .hardie
        case "std.cladding.woodVertical": return .woodVertical
        case "std.cladding.brick": return .brick
        case "std.cladding.stone": return .stone
        case "std.cladding.vinyl": return .vinyl
        default: return nil
        }
    }

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
