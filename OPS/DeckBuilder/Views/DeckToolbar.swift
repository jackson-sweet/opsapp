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

            // Context-sensitive action bar — one shell, action set varies by
            // selected data type. Mixed selections keep the bulk bar.
            if canEdit, !viewModel.selection.isEmpty {
                selectedContextTools
            } else {
                defaultTools
            }
        }
        .background(OPSStyle.Colors.cardBackground)
    }

    private enum SelectionContext {
        case vertex
        case edge
        case stair
        case surface
        case mixed
    }

    @ViewBuilder
    private var selectedContextTools: some View {
        switch selectionContext {
        case .vertex:
            vertexTools
        case .edge:
            edgeTools
        case .stair:
            stairTools
        case .surface:
            surfaceTools
        case .mixed:
            multiSelectBulkTools
        }
    }

    private var selectionContext: SelectionContext {
        let hasVertices = viewModel.selection.hasVertices
        let hasEdges = viewModel.selection.hasEdges
        let hasSurfaces = viewModel.selection.hasSurfaces
        let kindCount = (hasVertices ? 1 : 0) + (hasEdges ? 1 : 0) + (hasSurfaces ? 1 : 0)

        guard kindCount == 1 else { return .mixed }
        if hasVertices { return .vertex }
        if hasSurfaces { return .surface }
        if selectedEdgesAreOnlyStairs { return .stair }
        return .edge
    }

    // MARK: - Multi-Select Header

    private var multiSelectHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            let total = viewModel.selection.selectedEdgeIds.count
                      + viewModel.selection.selectedVertexIds.count
                      + viewModel.selection.selectedSurfaceIds.count

            // Count pill — primary mode indicator. Number only, no "SELECTED"
            // label: the checkmark icon already conveys the meaning, and the
            // toolbar can't afford the extra width on narrow phones (it was
            // wrapping mid-label on iPhone SE — bug 6d1c0a2a follow-up). One-
            // line, intrinsic-width so the pill stays compact regardless of
            // count digits.
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text("\(total)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(total > 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(OPSStyle.Colors.primaryAccent.opacity(total > 0 ? 0.12 : 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(total > 0 ? 0.4 : 0.2), lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(4)
            .accessibilityLabel(total == 1 ? "1 element selected" : "\(total) elements selected")

            // Marquee / Lasso shape toggle — DECK-NEW-4. Picks the drag
            // shape used when the user drags from empty canvas while in
            // select mode. Compact 2-segment switch.
            marqueeShapeToggle

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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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
        // Move-to-level shows whenever a surface OR edge selection exists —
        // even in single-level mode it offers "+ New level" so the operator
        // can split off a second deck. Cap is 3 levels. Edge migration also
        // moves the bounding vertices and invalidates any surface whose
        // perimeter the move breaks (bug 6d1c0a2a).
        let hasSurfaceSelection = !viewModel.selection.selectedSurfaceIds.isEmpty
        let hasEdgeSelection = edgeCount > 0
        let canMoveToLevel = (hasSurfaceSelection || hasEdgeSelection)
            && (viewModel.isMultiLevel || viewModel.drawingData.levels.count < 3)
        _ = vertexCount  // silence unused-warning while we keep the readable line above

        return contextToolBar {
            contextLabel("Selection")

            toolDivider

            selectOnlyMenuIfUseful(includeKindSection: true)

            if canAssignMaterial {
                actionButton(icon: "square.grid.3x3", label: "Material") {
                    viewModel.showingMaterialPicker = true
                }
            }

            if surfaceSelected {
                actionButton(icon: "shippingbox", label: "Order Vinyl") {
                    viewModel.vinylOrderSurfaceScope = .selectedSurfaces
                    viewModel.showingVinylOrderSheet = true
                }
            }

            actionButton(icon: "arrow.up.left.and.arrow.down.right", label: "Move XY",
                         isActive: viewModel.isSelectionMoveArmed) {
                viewModel.toggleSelectionMove()
            }

            if canMoveToLevel {
                moveToLevelMenu
            }

            Spacer()

            actionButton(icon: OPSStyle.Icons.trash, label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                viewModel.deleteSelection()
            }

            clearSelectionButton
        }
    }

    /// Marquee / Lasso shape toggle for tap-select mode (DECK-NEW-4).
    @ViewBuilder
    private var marqueeShapeToggle: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.marqueeShape = .rect
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(viewModel.marqueeShape == .rect ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(height: 28)
                    .background(viewModel.marqueeShape == .rect ? OPSStyle.Colors.primaryAccent.opacity(0.18) : Color.clear)
            }
            .accessibilityLabel("Marquee select")

            Button {
                viewModel.marqueeShape = .lasso
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "lasso")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(viewModel.marqueeShape == .lasso ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(height: 28)
                    .background(viewModel.marqueeShape == .lasso ? OPSStyle.Colors.primaryAccent.opacity(0.18) : Color.clear)
            }
            .accessibilityLabel("Lasso select")
        }
        .background(OPSStyle.Colors.cardBackground.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(OPSStyle.Colors.cardBorder.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(4)
    }

    /// Move-to-level menu — sends the current selection (surfaces and/or
    /// edges) to a different level. Existing levels listed first, then a
    /// "+ New Level" option that spawns a fresh level and moves the
    /// selection there in one step (capped at 3 levels). DECK-NEW-4 + bug
    /// 6d1c0a2a: now handles edge selections too — moving edges also moves
    /// their bounding vertices and drops any surface whose perimeter the
    /// move broke.
    @ViewBuilder
    private var moveToLevelMenu: some View {
        let hasSurfaces = !viewModel.selection.selectedSurfaceIds.isEmpty
        let hasEdges = !viewModel.selection.selectedEdgeIds.isEmpty
        Menu {
            if viewModel.isMultiLevel {
                ForEach(Array(viewModel.drawingData.levels.enumerated()), id: \.element.id) { idx, level in
                    Button {
                        if hasSurfaces { viewModel.moveSelectedSurfacesToLevel(at: idx) }
                        if hasEdges    { viewModel.moveSelectedEdgesToLevel(at: idx) }
                    } label: {
                        Label(level.name, systemImage: "square.stack.3d.up")
                    }
                }
                if viewModel.drawingData.levels.count < 3 {
                    Divider()
                }
            }
            if viewModel.drawingData.levels.count < 3 {
                Button {
                    if hasEdges {
                        viewModel.moveSelectedEdgesToNewLevel()
                    } else if hasSurfaces {
                        viewModel.moveSelectedSurfacesToNewLevel()
                    }
                } label: {
                    Label("New Level", systemImage: "plus.square.on.square")
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(.white)
                Text("Move")
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .frame(minWidth: OPSStyle.Layout.touchTargetStandard, minHeight: OPSStyle.Layout.touchTargetStandard)
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
                    // DECK-NEW-4 — collapsed Select + Lasso + Multi into a
                    // single Select tool. Tap = toggle individual; drag from
                    // empty = marquee or lasso (sub-toolbar toggle). Saves
                    // ~120pt of toolbar width and keeps select-mode entry
                    // unambiguous.
                    toolButton(icon: "pencil.and.outline", label: "Draw", tool: .draw)
                    toolButton(icon: "checkmark.circle", label: "Select", tool: .tapSelect)

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
        contextToolBar {
            contextLabel("Vertex")

            toolDivider

            actionButton(icon: "arrow.up.and.down.circle", label: "Elevation") {
                viewModel.showingElevationInput = true
            }

            actionButton(icon: "arrow.up.left.and.arrow.down.right", label: "Move XY",
                         isActive: viewModel.isSelectionMoveArmed) {
                viewModel.toggleSelectionMove()
            }

            Spacer()

            actionButton(icon: "trash", label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                viewModel.deleteSelectedVertices()
            }

            clearSelectionButton
        }
    }

    // MARK: - Edge Tools (edge selected)

    private var edgeTools: some View {
        contextToolBar {
            contextLabel("Edge")

            toolDivider

            selectOnlyMenuIfUseful(includeKindSection: false)

            actionButton(icon: "ruler", label: "Dimension") {
                viewModel.showingDimensionInput = true
            }

            actionButton(icon: "stairs", label: "Stairs") {
                viewModel.showingStairConfig = true
            }

            actionButton(icon: "arrow.up.left.and.arrow.down.right", label: "Move XY",
                         isActive: viewModel.isSelectionMoveArmed) {
                viewModel.toggleSelectionMove()
            }

            // Material entry removed from edge toolbar — the floating
            // assignment wheel (center-right of the canvas) is the
            // canonical material-pick path for edge selections. Bug
            // 6d1c0a2a — reporter saw two material buttons (toolbar +
            // wheel) and didn't know which to use. Surface selections
            // keep the toolbar Material button below because the wheel
            // is hidden in surface-only mode.

            // Move-to-level — edges + bounding vertices migrate; any
            // source-level surface whose perimeter the move breaks gets
            // dropped from level.surfaces (the operator's reshaped graph
            // is what now defines closure). Capped at 3 levels.
            if viewModel.isMultiLevel || viewModel.drawingData.levels.count < 3 {
                moveToLevelMenu
            }

            // Properties — opens PropertySheetView for edge type, house
            // cladding, railing config, stair metadata, labels. Previously
            // orphaned with no entry point so cladding/labels were
            // unreachable. Bug ee787f29.
            actionButton(icon: "slider.horizontal.3", label: "Properties") {
                viewModel.showingPropertySheet = true
            }

            Spacer()

            actionButton(icon: "trash", label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                viewModel.deleteSelectedEdges()
            }

            clearSelectionButton
        }
    }

    // MARK: - Stair Tools (stair selected)

    private var stairTools: some View {
        contextToolBar {
            contextLabel("Stair")

            toolDivider

            selectOnlyMenuIfUseful(includeKindSection: false)

            actionButton(icon: "stairs", label: "Edit") {
                viewModel.showingStairConfig = true
            }

            actionButton(icon: "shippingbox", label: "Material") {
                viewModel.showingMaterialPicker = true
            }

            actionButton(icon: "ruler", label: "Dimension") {
                viewModel.showingDimensionInput = true
            }

            actionButton(icon: "arrow.up.left.and.arrow.down.right", label: "Move XY",
                         isActive: viewModel.isSelectionMoveArmed) {
                viewModel.toggleSelectionMove()
            }

            if viewModel.isMultiLevel || viewModel.drawingData.levels.count < 3 {
                moveToLevelMenu
            }

            actionButton(icon: "slider.horizontal.3", label: "Properties") {
                viewModel.showingPropertySheet = true
            }

            Spacer()

            actionButton(icon: "trash", label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                viewModel.deleteSelectedEdges()
            }

            clearSelectionButton
        }
    }

    // MARK: - Surface Tools (surface selected)

    private var surfaceTools: some View {
        contextToolBar {
            contextLabel("Surface")

            toolDivider

            actionButton(icon: "square.grid.3x3", label: "Material") {
                viewModel.showingMaterialPicker = true
            }

            actionButton(icon: "shippingbox", label: "Order Vinyl") {
                viewModel.vinylOrderSurfaceScope = .selectedSurfaces
                viewModel.showingVinylOrderSheet = true
            }

            if viewModel.isMultiLevel || viewModel.drawingData.levels.count < 3 {
                moveToLevelMenu
            }

            actionButton(icon: "arrow.up.left.and.arrow.down.right", label: "Move XY",
                         isActive: viewModel.isSelectionMoveArmed) {
                viewModel.toggleSelectionMove()
            }

            actionButton(icon: "arrow.up.and.down.circle", label: "Elevation") {
                viewModel.showingElevationInput = true
            }

            actionButton(icon: "slider.horizontal.3", label: "Properties") {
                viewModel.showingPropertySheet = true
            }

            Spacer()

            clearSelectionButton
        }
    }

    private var selectedEdgesAreOnlyStairs: Bool {
        let selectedIds = viewModel.selection.selectedEdgeIds
        guard !selectedIds.isEmpty else { return false }
        let selectedEdges = viewModel.drawingData.allEdges.filter { selectedIds.contains($0.id) }
        return selectedEdges.count == selectedIds.count
            && selectedEdges.allSatisfy { $0.stairConfig != nil }
    }

    private func contextToolBar<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                content()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
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

    /// `isActive` mirrors `toolButton`'s active treatment for sticky-toggle
    /// modes (currently only Move-XY) — color + weight + accent background
    /// signal the toggled-on state so the user knows further canvas drags
    /// will operate in that mode without re-tapping. Color is paired with
    /// weight + background so the state is legible without relying on
    /// color alone.
    private func actionButton(
        icon: String, label: String,
        tint: Color = Color.white,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryAccent : tint)
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
        case .parapetWall: return "rectangle.bottomhalf.filled"
        case .glass:      return "rectangle.split.3x1"
        case .picket:     return "line.3.horizontal"
        case .cable:      return "cable.connector.horizontal"
        case .horizontal: return "minus"
        case .wood:       return "rectangle.fill"
        }
    }
}
