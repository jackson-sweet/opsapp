// OPS/OPS/DeckBuilder/Views/DeckToolbar.swift

import SwiftUI
import UIKit

struct DeckToolbar: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    private let permissionStore = PermissionStore.shared

    /// True when user has view-only access (no create or edit permission)
    private var isViewOnly: Bool {
        !permissionStore.can("deck_builder.edit") && !permissionStore.can("deck_builder.create")
    }

    /// True when user can generate estimates
    private var canCreate: Bool {
        permissionStore.can("deck_builder.create")
    }

    /// True when user can draw/edit the deck design
    private var canEdit: Bool {
        permissionStore.can("deck_builder.edit")
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.activeTool == .tapSelect {
                multiSelectHeader
            }

            // Context-sensitive action bar — changes based on what's selected.
            // In multi-select the bulk action bar takes priority over single-kind bars so
            // mixed selections (edges + vertices + surface) can be acted on in one place.
            if canEdit, viewModel.activeTool == .tapSelect, !viewModel.selection.isEmpty {
                multiSelectBulkTools
            } else if canEdit, viewModel.selection.hasVertices {
                vertexTools
            } else if canEdit, viewModel.selection.hasEdges {
                edgeTools
            } else if canEdit, viewModel.selection.selectedFootprint {
                footprintTools
            } else {
                defaultTools
            }
        }
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - Multi-Select Header

    private var multiSelectHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // Prominent mode indicator + live count — user always knows they're in multi-select
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                Text("MULTI-SELECT")
                    .font(OPSStyle.Typography.miniLabel)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(OPSStyle.Colors.primaryAccent.opacity(0.12))
            .cornerRadius(4)

            let total = viewModel.selection.selectedEdgeIds.count
                      + viewModel.selection.selectedVertexIds.count
                      + (viewModel.selection.selectedFootprint ? 1 : 0)

            // Count pill — sits beside the mode badge so scanning the toolbar shows both state + count
            Text("\(total) SELECTED")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(total > 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(OPSStyle.Colors.cardBackground.opacity(total > 0 ? 1 : 0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(OPSStyle.Colors.cardBorder.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                )
                .cornerRadius(4)

            Spacer()

            Menu {
                ForEach(SelectableElementType.allCases, id: \.self) { type in
                    Button {
                        if viewModel.tapSelectFilter.contains(type) {
                            viewModel.tapSelectFilter.remove(type)
                        } else {
                            viewModel.tapSelectFilter.insert(type)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text(type.rawValue.capitalized)
                            if viewModel.tapSelectFilter.contains(type) {
                                Image(systemName: OPSStyle.Icons.checkmark)
                            }
                        }
                    }
                }
            } label: {
                Text("FILTER")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

            Button {
                viewModel.exitMultiSelect()
            } label: {
                Text("DONE")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Multi-Select Bulk Tools

    /// Bulk action bar for a multi-kind selection — replaces per-kind context bars.
    /// Handles mixed selections (e.g. 3 edges + 2 vertices) in one tap via `deleteSelection`.
    private var multiSelectBulkTools: some View {
        let edgeCount = viewModel.selection.selectedEdgeIds.count
        let vertexCount = viewModel.selection.selectedVertexIds.count
        let surfaceSelected = viewModel.selection.selectedFootprint

        // Material only makes sense when at least one edge or surface is selected
        let canAssignMaterial = edgeCount > 0 || surfaceSelected
        // Properties sheet supports edges + vertices + surface
        let canOpenProperties = edgeCount > 0 || vertexCount > 0 || surfaceSelected

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                contextLabel("Selection")

                toolDivider

                selectOnlyMenuIfUseful(includeKindSection: true)

                if canAssignMaterial {
                    actionButton(icon: "square.grid.3x3", label: "Material") {
                        viewModel.showingMaterialPicker = true
                    }
                }

                if canOpenProperties {
                    actionButton(icon: "info.circle", label: "Properties") {
                        viewModel.showingPropertySheet = true
                    }
                }

                Spacer()

                actionButton(icon: OPSStyle.Icons.trash, label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                    viewModel.deleteSelection()
                }

                clearSelectionButton
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Default Tools (no selection)

    private var defaultTools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if isViewOnly {
                    // View Only badge — no drawing tools
                    Text("VIEW ONLY")
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.secondaryText.opacity(0.12))
                        .cornerRadius(4)
                } else if canEdit {
                    toolButton(icon: "pencil.and.outline", label: "Draw", tool: .draw)
                    toolButton(icon: "rectangle.dashed", label: "Select", tool: .select)
                    toolButton(icon: "lasso", label: "Lasso", tool: .lasso)
                    toolButton(icon: "checkmark.circle", label: "Multi", tool: .tapSelect)

                    toolDivider

                    actionButton(icon: "arrow.up.and.down.circle", label: "Height") {
                        viewModel.showingElevationInput = true
                    }

                    if viewModel.canAddLevel {
                        actionButton(icon: "plus.square.on.square", label: "Add Level") {
                            viewModel.addLevel()
                        }
                    }

                    toolDivider

                    actionButton(icon: "trash", label: "Clear", tint: OPSStyle.Colors.errorStatus) {
                        viewModel.showingClearConfirm = true
                    }
                }

                if !isViewOnly {
                    toolDivider
                }

                if canCreate {
                    labeledButton(icon: "doc.text", label: "Estimate",
                                  tint: viewModel.canGenerateEstimate ? Color.white : OPSStyle.Colors.tertiaryText,
                                  enabled: viewModel.canGenerateEstimate) {
                        viewModel.showingEstimatePreview = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }

                labeledButton(icon: "square.and.arrow.up", label: "Share",
                              tint: Color.white, enabled: true) {
                    viewModel.showingShareOptions = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                labeledButton(icon: "photo.on.rectangle.angled", label: "Overlay",
                              tint: viewModel.canShowOverlay ? Color.white : OPSStyle.Colors.tertiaryText,
                              enabled: viewModel.canShowOverlay) {
                    viewModel.showingPhotoSourcePicker = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                labeledButton(icon: "arkit", label: "AR",
                              tint: viewModel.canViewInAR ? Color.white : OPSStyle.Colors.tertiaryText,
                              enabled: viewModel.canViewInAR) {
                    viewModel.showingARVisualization = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

                if viewModel.isLaserConnected {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.successStatus)
                        .frame(width: 28, height: OPSStyle.Layout.touchTargetMin)
                }

                Divider()
                    .frame(height: 24)
                    .overlay(OPSStyle.Colors.cardBorder)

                Button {
                    viewModel.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Vertex Tools (vertex selected)

    private var vertexTools: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            contextLabel("Vertex")

            toolDivider

            actionButton(icon: "arrow.up.and.down.circle", label: "Elevation") {
                viewModel.showingElevationInput = true
            }

            actionButton(icon: "info.circle", label: "Properties") {
                viewModel.showingPropertySheet = true
            }

            Spacer()

            actionButton(icon: "trash", label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                viewModel.deleteSelectedVertices()
            }

            clearSelectionButton
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Edge Tools (edge selected)

    private var edgeTools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                contextLabel("Edge")

                toolDivider

                selectOnlyMenuIfUseful(includeKindSection: false)

                actionButton(icon: "ruler", label: "Dimension") {
                    viewModel.showingDimensionInput = true
                }

                actionButton(icon: "stairs", label: "Stairs") {
                    viewModel.showingStairConfig = true
                }

                actionButton(icon: "square.grid.3x3", label: "Material") {
                    viewModel.showingMaterialPicker = true
                }

                actionButton(icon: "info.circle", label: "Properties") {
                    viewModel.showingPropertySheet = true
                }

                Spacer()

                actionButton(icon: "trash", label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                    viewModel.deleteSelectedEdges()
                }

                clearSelectionButton
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Footprint Tools (area selected)

    private var footprintTools: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            contextLabel("Surface")

            toolDivider

            actionButton(icon: "square.grid.3x3", label: "Material") {
                viewModel.showingMaterialPicker = true
            }

            actionButton(icon: "arrow.up.and.down.circle", label: "Elevation") {
                viewModel.showingElevationInput = true
            }

            actionButton(icon: "info.circle", label: "Properties") {
                viewModel.showingPropertySheet = true
            }

            Spacer()

            clearSelectionButton
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Context Label

    private func contextLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(OPSStyle.Typography.miniLabel)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(OPSStyle.Colors.primaryAccent.opacity(0.12))
            .cornerRadius(4)
    }

    // MARK: - Clear Selection Button

    private var clearSelectionButton: some View {
        Button {
            viewModel.selection.clear()
            viewModel.editingEdgeId = nil
            viewModel.editingVertexId = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
    }

    // MARK: - Drawing Tool Button

    private func toolButton(icon: String, label: String, tool: DrawingTool) -> some View {
        let isActive = viewModel.activeTool == tool
        return Button {
            viewModel.activeTool = tool
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryAccent : Color.white)
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(isActive ? OPSStyle.Colors.primaryAccent.opacity(0.12) : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Context Action Button

    private func actionButton(
        icon: String, label: String,
        tint: Color = Color.white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(tint)
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
        }
    }

    // MARK: - Labeled Feature Button

    private func labeledButton(
        icon: String, label: String,
        tint: Color, enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(tint)
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(tint == Color.white ? OPSStyle.Colors.secondaryText : tint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
        }
        .disabled(!enabled)
    }

    // MARK: - Helpers

    private var toolDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.separator)
            .frame(width: 1, height: 32)
    }

    // MARK: - Select Only Filter Menu
    //
    // Lets the user narrow a multi-element selection to a subset (kind or
    // edge attribute). Only renders when there's actually something to
    // narrow — no point showing "Filter" against a single edge.

    @ViewBuilder
    private func selectOnlyMenuIfUseful(includeKindSection: Bool) -> some View {
        let edgeIds = viewModel.selection.selectedEdgeIds
        let vertexCount = viewModel.selection.selectedVertexIds.count
        let surfaceSelected = viewModel.selection.selectedFootprint
        let allEdges = viewModel.drawingData.allEdges
        let selectedEdges = allEdges.filter { edgeIds.contains($0.id) }

        let kindCount = (edgeIds.isEmpty ? 0 : 1) + (vertexCount == 0 ? 0 : 1) + (surfaceSelected ? 1 : 0)
        let hasMultipleKinds = kindCount > 1
        let edgeFilterUseful = selectedEdges.count >= 2 && edgesHaveFilterableVariation(selectedEdges)

        let showMenu = (includeKindSection && hasMultipleKinds) || edgeFilterUseful

        if showMenu {
            Menu {
                if includeKindSection && hasMultipleKinds {
                    Section("Geometry") {
                        if !edgeIds.isEmpty {
                            Button {
                                viewModel.selectOnlyEdges()
                            } label: {
                                Label("Edges (\(edgeIds.count))", systemImage: "rectangle")
                            }
                        }
                        if vertexCount > 0 {
                            Button {
                                viewModel.selectOnlyVertices()
                            } label: {
                                Label("Vertices (\(vertexCount))", systemImage: "circle")
                            }
                        }
                        if surfaceSelected {
                            Button {
                                viewModel.selectOnlySurface()
                            } label: {
                                Label("Surface", systemImage: "square.dashed")
                            }
                        }
                    }
                }

                if edgeFilterUseful {
                    edgeFilterSections(for: selectedEdges)
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                        .foregroundColor(.white)
                    Text("Filter")
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing1)
                .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
            }
        }
    }

    /// True when the selected edges have at least two variants along ANY of
    /// the supported filter axes (edge type, railing, stairs, material).
    /// Without variation there's nothing to narrow to and the menu would be
    /// degenerate.
    private func edgesHaveFilterableVariation(_ edges: [DeckEdge]) -> Bool {
        guard edges.count >= 2 else { return false }
        let edgeTypes = Set(edges.map { $0.edgeType })
        if edgeTypes.count > 1 { return true }
        let railings = Set(edges.map { $0.railingConfig?.railingType })  // nil counts as "no railing"
        if railings.count > 1 { return true }
        let stairs = edges.contains { $0.stairConfig != nil } && edges.contains { $0.stairConfig == nil }
        if stairs { return true }
        let materials = edges.contains { !$0.assignedItems.isEmpty } && edges.contains { $0.assignedItems.isEmpty }
        if materials { return true }
        return false
    }

    @ViewBuilder
    private func edgeFilterSections(for selectedEdges: [DeckEdge]) -> some View {
        // Edge type — only show if both types exist in the current selection.
        let houseCount = selectedEdges.filter { $0.edgeType == .houseEdge }.count
        let deckCount = selectedEdges.filter { $0.edgeType == .deckEdge }.count
        if houseCount > 0 && deckCount > 0 {
            Section("Edge Type") {
                Button {
                    viewModel.filterSelectedEdges { $0.edgeType == .houseEdge }
                } label: {
                    Label("House Edges (\(houseCount))", systemImage: "house")
                }
                Button {
                    viewModel.filterSelectedEdges { $0.edgeType == .deckEdge }
                } label: {
                    Label("Deck Edges (\(deckCount))", systemImage: "rectangle")
                }
            }
        }

        // Railings — emit one button per railing type that's present in the
        // selection, plus a "No Railing" button if at least one un-railed
        // edge is present alongside a railed one.
        let railedCount = selectedEdges.filter { $0.railingConfig != nil }.count
        let unrailedCount = selectedEdges.count - railedCount
        let hasRailingVariation = railedCount > 0 && (unrailedCount > 0 || railingTypeCount(selectedEdges) > 1)
        if hasRailingVariation {
            Section("Railing") {
                ForEach(RailingType.allCases, id: \.self) { type in
                    let count = selectedEdges.filter { $0.railingConfig?.railingType == type }.count
                    if count > 0 {
                        Button {
                            viewModel.filterSelectedEdges { $0.railingConfig?.railingType == type }
                        } label: {
                            Label("\(type.displayName) (\(count))", systemImage: railingIcon(for: type))
                        }
                    }
                }
                if unrailedCount > 0 && railedCount > 0 {
                    Button {
                        viewModel.filterSelectedEdges { $0.railingConfig == nil }
                    } label: {
                        Label("No Railing (\(unrailedCount))", systemImage: "xmark")
                    }
                }
            }
        }

        // Stairs — only useful when some edges have stairs and others don't.
        let stairsCount = selectedEdges.filter { $0.stairConfig != nil }.count
        if stairsCount > 0 && stairsCount < selectedEdges.count {
            Section("Stairs") {
                Button {
                    viewModel.filterSelectedEdges { $0.stairConfig != nil }
                } label: {
                    Label("With Stairs (\(stairsCount))", systemImage: "stairs")
                }
            }
        }

        // Material — only useful when the selection mixes assigned and
        // unassigned edges. Single-state selections have nothing to narrow.
        let withMaterial = selectedEdges.filter { !$0.assignedItems.isEmpty }.count
        let withoutMaterial = selectedEdges.count - withMaterial
        if withMaterial > 0 && withoutMaterial > 0 {
            Section("Material") {
                Button {
                    viewModel.filterSelectedEdges { !$0.assignedItems.isEmpty }
                } label: {
                    Label("With Material (\(withMaterial))", systemImage: "shippingbox.fill")
                }
                Button {
                    viewModel.filterSelectedEdges { $0.assignedItems.isEmpty }
                } label: {
                    Label("No Material (\(withoutMaterial))", systemImage: "shippingbox")
                }
            }
        }
    }

    /// Number of distinct railing types in the selection (excluding nil).
    private func railingTypeCount(_ edges: [DeckEdge]) -> Int {
        Set(edges.compactMap { $0.railingConfig?.railingType }).count
    }

    /// SF Symbol roughly matching each railing type — kept loose since SF
    /// doesn't ship deck-specific icons.
    private func railingIcon(for type: RailingType) -> String {
        switch type {
        case .glass:      return "rectangle.split.3x1"
        case .picket:     return "line.3.horizontal"
        case .cable:      return "cable.connector.horizontal"
        case .horizontal: return "minus"
        case .wood:       return "rectangle.fill"
        }
    }
}
