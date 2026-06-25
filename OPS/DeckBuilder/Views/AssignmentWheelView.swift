// OPS/OPS/DeckBuilder/Views/AssignmentWheelView.swift

import SwiftUI
import DeckKit
import SwiftData

struct AssignmentWheelView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @State private var isExpanded = false
    @State private var dragAngle: Double?
    @State private var highlightedIndex: Int?

    // Catalog inputs — the wheel pulls railing-eligible (linear-dimensioned)
    // company products into its first 3 slots so the operator picks an actual
    // catalog SKU instead of a generic style. Falls back to the legacy
    // Glass/Picket/Cable Rail placeholders when the company hasn't set up
    // products yet. Bug ee787f29.
    @Query(filter: #Predicate<Product> { $0.isActive }, sort: \Product.name)
    private var products: [Product]
    @Query private var catalogUnits: [CatalogUnit]
    @Query private var companyDefaults: [CompanyDefaultProduct]
    @Query(sort: \TaskType.displayOrder) private var taskTypes: [TaskType]

    private let wheelRadius: CGFloat = 110
    private let slotCount = 8

    /// Linear-dimensioned products that could plausibly be assigned to a
    /// railing edge. We hoist the company's `CompanyDefaultProduct` for the
    /// current component type (railing / stairSet) to the top of the list so
    /// it lands in slot 0 — same default-pinning pattern MaterialPickerSheet
    /// uses. Sorted: default first, then alphabetical (matches what @Query
    /// returns).
    private var railingProducts: [Product] {
        let linear = products.filter { product in
            ProductUnitResolver.dimension(of: product, catalogUnits: catalogUnits) == .length
        }
        guard let defaultId = defaultProductId,
              let pinned = linear.first(where: { $0.id == defaultId }) else {
            return linear
        }
        let rest = linear.filter { $0.id != defaultId }
        return [pinned] + rest
    }

    /// Component type the wheel is filling for, mirrors `MaterialPickerSheet`'s
    /// `surfaceContext`. Stair context wins over railing when the selected
    /// edge already carries a stair set — picking another product there is
    /// presumptively for the stair.
    private var surfaceContext: DesignComponentType {
        let firstId = viewModel.selection.selectedEdgeIds.first
        if let firstId,
           let edge = viewModel.findEdge(byId: firstId),
           edge.stairConfig != nil {
            return .stairSet
        }
        return .railing
    }

    private var defaultProductId: String? {
        let companyId = viewModel.deckDesign.companyId
        return companyDefaults.first(where: {
            $0.companyId == companyId && $0.componentType == surfaceContext
        })?.productId
    }

    /// Slot list for the current selection. 8 slots total:
    ///   slot 0–2: catalog railing products (default first), backfilled with
    ///            generic Glass/Picket/Cable placeholders when the catalog is
    ///            short. Field crews with no catalog still get a working wheel.
    ///   slot 3 : No Railing
    ///   slot 4 : Add Stairs
    ///   slot 5 : Dimension
    ///   slot 6 : House Edge
    ///   slot 7 : Deck Edge
    /// The legacy `selectedFootprint` branch is dead code — DeckBuilderView
    /// hides the wheel entirely when no edge is selected — but kept here as a
    /// belt-and-braces fallback so the assertion stays load-bearing.
    private var wheelItems: [WheelSlot] {
        var items: [WheelSlot] = []

        if viewModel.selection.hasEdges {
            // Slots 0–2: company catalog products if any; built-in standards
            // backfill the rest. Bug ee787f29 follow-up — the previous
            // backfill used bare `.railing(type)` actions, which only set
            // railingConfig without ever creating an AssignedItem. The
            // assignment never appeared in the cut list / estimate, which
            // read as "the wheel still shows placeholders" because tapping
            // a placeholder did nothing trackable. Now both code paths route
            // through `.assignRailingProduct` so a tap always produces a
            // proper material assignment alongside the railing-type change.
            let catalogSlots = railingProducts.prefix(3).map { product -> WheelSlot in
                let isDefault = product.id == defaultProductId
                let railingType = derivedRailingType(from: product)
                let assigned = AssignedItem(
                    productId: product.id,
                    name: product.name,
                    unitType: .linearFoot,
                    unitPrice: product.basePrice,
                    taskTypeId: product.taskTypeId,
                    taskTypeColor: taskTypes.first(where: { $0.id == product.taskTypeId && $0.deletedAt == nil })?.color,
                    isGate: product.category?.lowercased().contains("gate") == true
                )
                return WheelSlot(
                    name: product.name,
                    icon: railingIcon(for: railingType),
                    initials: String(product.name.prefix(3)).uppercased(),
                    isDefault: isDefault,
                    action: .assignRailingProduct(item: assigned, railingType: railingType)
                )
            }
            let standardBackfill = wheelStandardSlots()
            for i in 0..<3 {
                if i < catalogSlots.count {
                    items.append(catalogSlots[i])
                } else if i - catalogSlots.count < standardBackfill.count {
                    items.append(standardBackfill[i - catalogSlots.count])
                }
            }

            // Slots 3–7: structural utilities + edge type.
            items.append(WheelSlot(name: "No Railing", icon: "xmark", initials: nil, isDefault: false, action: .removeRailing))
            items.append(WheelSlot(name: "Add Stairs", icon: "stairs", initials: nil, isDefault: false, action: .addStairs))
            items.append(WheelSlot(name: "Dimension",  icon: "ruler",  initials: nil, isDefault: false, action: .dimension))
            items.append(WheelSlot(name: "House Edge", icon: "house",     initials: nil, isDefault: false, action: .edgeType(.houseEdge)))
            items.append(WheelSlot(name: "Deck Edge",  icon: "rectangle", initials: nil, isDefault: false, action: .edgeType(.deckEdge)))
        } else if viewModel.selection.selectedFootprint {
            items.append(WheelSlot(name: "Material", icon: "shippingbox", initials: nil, isDefault: false, action: .openMaterialPicker))
        }

        return items
    }

    /// Built-in standard slot used when the company catalog has fewer than
    /// three linear products. Parapet wall is the only built-in railing
    /// default; generic glass/picket/cable rail choices must come from the
    /// company's catalog if they are actually part of the job.
    private func wheelStandardSlots() -> [WheelSlot] {
        let chosen: [BuiltInMaterial] = [
            BuiltInMaterial.linearStandards.first(where: { $0.id == "std.wall.parapet" })
        ].compactMap { $0 }

        return chosen.map { standard in
            let assigned = AssignedItem(
                productId: nil,
                name: standard.name,
                unitType: .linearFoot,
                unitPrice: nil,
                taskTypeId: nil,
                taskTypeColor: nil,
                isGate: standard.id.contains("gate")
            )
            return WheelSlot(
                name: standard.name,
                icon: railingIcon(for: .parapetWall),
                initials: nil,
                isDefault: false,
                action: .assignRailingProduct(item: assigned, railingType: .parapetWall)
            )
        }
    }

    /// Name-only derivation (no category context) for built-in standards.
    private func derivedRailingType(name: String) -> RailingType {
        let haystack = name.lowercased()
        if haystack.contains("parapet") { return .parapetWall }
        if haystack.contains("glass") { return .glass }
        if haystack.contains("cable") { return .cable }
        if haystack.contains("horizontal") { return .horizontal }
        if haystack.contains("wood") || haystack.contains("cedar") { return .wood }
        return .parapetWall
    }

    /// Best-guess railing type from a product's name/category. Drives the 3D
    /// preview style when the user picks a catalog product directly from the
    /// wheel. Defaults to parapet wall so uncategorized catalog products do
    /// not recreate the removed generic picket/cable defaults.
    private func derivedRailingType(from product: Product) -> RailingType {
        let haystack = ((product.name) + " " + (product.category ?? "")).lowercased()
        if haystack.contains("glass") { return .glass }
        if haystack.contains("cable") { return .cable }
        if haystack.contains("horizontal") { return .horizontal }
        if haystack.contains("wood") || haystack.contains("cedar") { return .wood }
        return .parapetWall
    }

    private func railingIcon(for type: RailingType) -> String {
        switch type {
        case .parapetWall: return "rectangle.bottomhalf.filled"
        case .glass:      return "rectangle.split.3x1"
        case .picket:     return "line.3.horizontal"
        case .cable:      return "cable.connector.horizontal"
        case .horizontal: return "rectangle.split.1x2"
        case .wood:       return "square.grid.2x2"
        }
    }

    var body: some View {
        ZStack {
            if isExpanded {
                // Background overlay
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { collapse() }

                // Wheel slots. Two interaction paths into `executeAction`:
                //  - tap a slot directly (added for bug ee787f29 — the original
                //    long-press → drag → release path discovered approximately
                //    no one in field testing; users would expand the wheel via
                //    tap, then tap a slot and get no response).
                //  - long-press the center, drag to a slot, release (power path
                //    for muscle-memory single-handed use; still wired on the
                //    center button below).
                ForEach(Array(wheelItems.enumerated()), id: \.offset) { index, slot in
                    let angle = slotAngle(index: index)
                    let isHighlighted = highlightedIndex == index

                    VStack(spacing: 3) {
                        // Catalog products render as a 3-letter mono badge
                        // (matches the active-assignment indicator on the
                        // center button); generic placeholders keep their SF
                        // Symbol icon.
                        if let initials = slot.initials {
                            Text(initials)
                                .font(.system(size: isHighlighted ? 13 : 11, weight: .bold, design: .monospaced))
                                .foregroundColor(isHighlighted ? OPSStyle.Colors.text : OPSStyle.Colors.primaryText)
                        } else {
                            Image(systemName: slot.icon)
                                .font(.system(size: isHighlighted ? OPSStyle.Layout.IconSize.lg : OPSStyle.Layout.IconSize.md, weight: .medium))
                                .foregroundColor(isHighlighted ? OPSStyle.Colors.text : OPSStyle.Colors.primaryText)
                        }

                        Text(slot.name)
                            .font(OPSStyle.Typography.miniLabel)
                            .foregroundColor(isHighlighted ? OPSStyle.Colors.text : OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 56)
                    }
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(isHighlighted
                                  ? OPSStyle.Colors.surfaceActive
                                  : OPSStyle.Colors.cardBackground)
                    )
                    .overlay(alignment: .topTrailing) {
                        // Subtle 6pt accent dot marks the company default
                        // (slot 0 when a default exists). Mirrors the
                        // "// DEFAULT" tag MaterialPickerSheet uses, scaled
                        // down for the wheel.
                        if slot.isDefault {
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(width: 6, height: 6)
                                .offset(x: -4, y: 4)
                        }
                    }
                    .contentShape(Circle())
                    .onTapGesture {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        executeAction(slot.action)
                        collapse()
                    }
                    .offset(
                        x: cos(angle) * wheelRadius,
                        y: sin(angle) * wheelRadius
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Center button
            centerButton
        }
        .animation(OPSStyle.Animation.spring, value: isExpanded)
    }

    // MARK: - Center Button

    private var centerButton: some View {
        Circle()
            .fill(OPSStyle.Colors.primaryAccent.opacity(isExpanded ? 0.3 : 1.0))
            .frame(width: 56, height: 56)
            .overlay(
                Group {
                    if let assignment = viewModel.activeAssignment {
                        Text(assignment.name.prefix(3).uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Image(systemName: isExpanded ? OPSStyle.Icons.xmark : "circle.grid.2x2")
                            .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .second(true, let drag):
                            if !isExpanded {
                                isExpanded = true
                            }
                            if let drag = drag {
                                updateHighlight(drag: drag)
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        if let index = highlightedIndex, index < wheelItems.count {
                            executeAction(wheelItems[index].action)
                        }
                        collapse()
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if isExpanded {
                            collapse()
                        } else {
                            isExpanded = true
                        }
                    }
            )
    }

    // MARK: - Helpers

    private func slotAngle(index: Int) -> Double {
        let angleStep = (2 * .pi) / Double(max(wheelItems.count, 1))
        return Double(index) * angleStep - .pi / 2 // start at top
    }

    private func updateHighlight(drag: DragGesture.Value) {
        let dx = Double(drag.location.x - 28) // center offset
        let dy = Double(drag.location.y - 28)
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > 30 else {
            highlightedIndex = nil
            return
        }

        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        // Offset to match slot positions (starting at top)
        angle = angle + .pi / 2
        if angle > 2 * .pi { angle -= 2 * .pi }

        let angleStep = (2 * .pi) / Double(max(wheelItems.count, 1))
        highlightedIndex = Int((angle + angleStep / 2) / angleStep) % wheelItems.count
    }

    private func collapse() {
        isExpanded = false
        highlightedIndex = nil
        dragAngle = nil
    }

    private func executeAction(_ action: WheelAction) {
        // Footprint actions
        if case .openMaterialPicker = action, viewModel.selection.selectedFootprint {
            viewModel.showingMaterialPicker = true
            return
        }
        if case .assignItem(let item) = action, viewModel.selection.selectedFootprint {
            viewModel.assignItemToFootprint(item)
            return
        }

        guard let edgeId = viewModel.selection.selectedEdgeIds.first else { return }

        switch action {
        case .edgeType(let type):
            viewModel.setEdgeType(Array(viewModel.selection.selectedEdgeIds), type: type)
        case .railing(let type):
            let config = RailingConfig(railingType: type, maxPostSpacing: type.defaultMaxPostSpacing)
            for id in viewModel.selection.selectedEdgeIds {
                viewModel.setRailing(id, config: config)
            }
        case .removeRailing:
            for id in viewModel.selection.selectedEdgeIds {
                viewModel.setRailing(id, config: nil)
            }
        case .addStairs:
            viewModel.editingEdgeId = edgeId
            viewModel.showingStairConfig = true
        case .dimension:
            viewModel.editingEdgeId = edgeId
            viewModel.showingDimensionInput = true
        case .assignItem(let item):
            viewModel.assignItemToSelectedEdges(item)
        case .assignRailingProduct(let item, let railingType):
            // Two-step: set railing config first (so the 3D scene renders the
            // right style) then attach the catalog product to every selected
            // edge. If the edge already has a railingConfig, only its
            // railingType + maxPostSpacing get overwritten — color, mount type
            // etc. stay so the user doesn't lose prior config every time they
            // tap a new product.
            for id in viewModel.selection.selectedEdgeIds {
                if let edge = viewModel.findEdge(byId: id), var existing = edge.railingConfig {
                    existing.railingType = railingType
                    existing.maxPostSpacing = railingType.defaultMaxPostSpacing
                    viewModel.setRailing(id, config: existing)
                } else {
                    let config = RailingConfig(
                        railingType: railingType,
                        maxPostSpacing: railingType.defaultMaxPostSpacing
                    )
                    viewModel.setRailing(id, config: config)
                }
            }
            viewModel.assignItemToSelectedEdges(item)
        case .openMaterialPicker:
            viewModel.showingMaterialPicker = true
        }
    }
}

// MARK: - Types

private struct WheelSlot {
    let name: String
    let icon: String
    /// 3-letter mono badge shown in place of the SF Symbol when the slot
    /// represents a specific catalog product. nil for generic/structural slots.
    let initials: String?
    /// Whether this slot is the company's pinned default for the current
    /// component type — drives the small accent dot on the slot circle.
    let isDefault: Bool
    let action: WheelAction
}

private enum WheelAction {
    case edgeType(EdgeType)
    case railing(RailingType)
    case removeRailing
    case addStairs
    case dimension
    case assignItem(AssignedItem)
    /// Tap on a catalog-driven slot: sets railing type structurally AND
    /// attaches the chosen product as an `AssignedItem` so the cut list /
    /// estimate knows which SKU to bill. Bug ee787f29.
    case assignRailingProduct(item: AssignedItem, railingType: RailingType)
    case openMaterialPicker
}
