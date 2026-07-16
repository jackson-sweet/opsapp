//
//  DeckFullscreenViewer.swift
//  OPS
//
//  Fullscreen focus mode for a project's deck design, entered by overscrolling
//  the Deck tab. The canvas fills the screen; a minimal top bar carries the
//  title + 2D/3D toggle + close, a right-side rail carries the 2D measuring
//  tools, and a bottom peek sheet carries the selection readout. 3D is
//  view-only (no rail) per product direction.
//
//  Tool state is shared (DeckViewerToolState) so the same canvas views render
//  here (with tools) and inline (read-only). Chrome auto-dims while the user
//  pans/zooms so it never obstructs the geometry being inspected.
//

import SwiftUI

struct DeckFullscreenViewer: View {
    /// Deck/project title for the top bar.
    let title: String
    /// The geometry to render — the only inputs the viewer needs, so it stays
    /// decoupled from SwiftData models (and headlessly renderable).
    let drawingData: DeckDrawingData
    @Binding var viewMode: DeckTabViewMode
    @ObservedObject var toolState: DeckViewerToolState
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True while the user pans/zooms the visible viewport — drives the chrome fade.
    @State private var isViewportInteracting = false
    /// Downward drag distance on the top bar for swipe-to-dismiss.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            canvas
                .ignoresSafeArea()

            chrome
                .opacity(chromeOpacity)
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: isViewportInteracting)
        }
        .hidesGlobalTabBar()
        .offset(y: dragOffset)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        switch viewMode {
        case .threeD:
            if drawingData.hasAnyClosedSurface {
                DeckTab3DView(drawingData: drawingData,
                              onInteractingChange: { isViewportInteracting = $0 })
                    .transition(.opacity)
            } else {
                incompleteNote
            }
        case .twoD, .materials:
            // Fullscreen is a canvas surface — the materials tab has no
            // fullscreen form. Unreachable in practice (the presenter remaps
            // .materials to .twoD before opening), but the fallback keeps the
            // viewer honest if it ever arrives here.
            DeckTab2DView(drawingData: drawingData,
                          toolState: toolState,
                          showsTools: true,
                          onInteractingChange: { isViewportInteracting = $0 })
                .transition(.opacity)
        }
    }

    private var incompleteNote: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: "square.dashed")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("OUTLINE ISN'T CLOSED YET")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .tracking(1)
            Text("Switch to 2D to see the plan.")
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if viewMode == .twoD {
                HStack(alignment: .bottom, spacing: 0) {
                    // Readouts anchored bottom-left: the split card while a
                    // valid cut exists (the selection readout is stale context
                    // once the user is cutting), else the selection peek sheet
                    // in select mode, else the measure card in measure mode.
                    // One grammar — data left / tools right.
                    if toolState.isSplitting, splitReadout.didSplit {
                        splitSheet
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if toolState.isSelecting, toolState.hasSelection {
                        peekSheet
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if toolState.isMeasuring, showsMeasureCard {
                        measureSheet
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Spacer(minLength: OPSStyle.Layout.spacing3)
                    // Tool rail anchored bottom-right, thumb reachable. Measure
                    // mode slides in its contextual actions (undo / finish)
                    // above the rail in the same circular-button language.
                    VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing2_5) {
                        if let hint = measurementHint {
                            hintPill(hint)
                        }
                        if toolState.isMeasuring {
                            if toolState.canUndoMeasurement {
                                toolButton(
                                    icon: "arrow.uturn.backward",
                                    isActive: false,
                                    activeColor: OPSStyle.Colors.warningStatus,
                                    label: "Undo last point"
                                ) {
                                    toolState.undoMeasurePoint()
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                .transition(.opacity)
                            }
                            if toolState.canFinishMeasurement {
                                toolButton(
                                    icon: "checkmark",
                                    isActive: true,
                                    activeColor: OPSStyle.Colors.warningStatus,
                                    label: "Finish measurement"
                                ) {
                                    toolState.finishMeasurement()
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                                .transition(.opacity)
                            }
                        }
                        if toolState.isSelecting, toolState.canSplit {
                            toolButton(
                                icon: "scissors",
                                isActive: toolState.isSplitting,
                                activeColor: OPSStyle.Colors.primaryAccent,
                                label: toolState.isSplitting ? "Stop splitting" : "Split surface"
                            ) {
                                toolState.toggleSplitting()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            .transition(.opacity)
                        }
                        toolRail
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing4)
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: toolState.measurementPoints.count)
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: toolState.measurementPhase)
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: toolState.canSplit)
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: toolState.isSplitting)
                .animation(reduceMotion ? nil : OPSStyle.Animation.fast, value: toolState.splitPoints.count)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(title)
                    .font(OPSStyle.Typography.screenTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textCase(.uppercase)
                Text(summaryReadout)
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer(minLength: OPSStyle.Layout.spacing2)

            SegmentedControl(
                selection: $viewMode,
                options: [
                    (DeckTabViewMode.threeD, "3D"),
                    (DeckTabViewMode.twoD, "2D")
                ]
            )
            .frame(width: 108)
            .onChange(of: viewMode) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isViewportInteracting = false
            }

            closeButton
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .background(alignment: .top) {
            // Faint top scrim so the title reads over a busy canvas.
            LinearGradient(
                colors: [OPSStyle.Colors.background.opacity(0.9), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 140)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    private var closeButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .accessibilityLabel("Close fullscreen")
    }

    // MARK: - Tool Rail (2D only)

    private var toolRail: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            toolButton(
                icon: "ruler",
                isActive: toolState.isMeasuring,
                activeColor: OPSStyle.Colors.warningStatus,
                label: "Measure distance"
            ) { toolState.toggleMeasure() }

            toolButton(
                icon: "hand.tap",
                isActive: toolState.isSelecting,
                activeColor: OPSStyle.Colors.primaryAccent,
                label: "Select and measure"
            ) { toolState.toggleSelect() }

            toolButton(
                icon: toolState.showDimensions ? "ruler.fill" : "eye.slash",
                isActive: !toolState.showDimensions,
                activeColor: OPSStyle.Colors.primaryAccent,
                label: toolState.showDimensions ? "Hide dimensions" : "Show dimensions"
            ) {
                toolState.showDimensions.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            if drawingData.isMultiLevel {
                toolButton(
                    icon: "square.3.layers.3d",
                    isActive: toolState.isolatedLevelId != nil,
                    activeColor: OPSStyle.Colors.primaryAccent,
                    label: toolState.isolatedLevelId == nil ? "Isolate level" : "Show all levels"
                ) { cycleIsolatedLevel() }
            }

            toolButton(
                icon: "arrow.up.left.and.arrow.down.right",
                isActive: false,
                activeColor: OPSStyle.Colors.primaryAccent,
                label: "Fit to screen"
            ) {
                toolState.requestFit()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func toolButton(
        icon: String,
        isActive: Bool,
        activeColor: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                .background(
                    Circle().fill(isActive ? activeColor : Color.black.opacity(0.6))
                )
                .overlay(
                    Circle().stroke(isActive ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .accessibilityLabel(label)
    }

    private func hintPill(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.warningStatus)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(Color.black.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.chipRadius)
    }

    // MARK: - Peek Sheet (selection readout)

    private var peekSheet: some View {
        let readout = DeckSelectionReadout.build(
            drawingData: drawingData,
            selectedEdgeIds: toolState.selectedEdgeIds,
            selectedSurfaceIds: toolState.selectedSurfaceIds
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("SELECTED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("\(readout.selectionCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Spacer(minLength: 12)
                Button {
                    toolState.clearSelection()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("CLEAR")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .accessibilityLabel("Clear selection")
            }

            ForEach(readout.surfaceGroups) { selectionRow($0.label, $0.value) }
            ForEach(readout.edgeGroups) { selectionRow($0.label, $0.value) }
            if let stair = readout.stairGroup { selectionRow(stair.label, stair.value) }

            if readout.totalAreaText != nil || readout.totalLengthText != nil {
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder.opacity(0.6))
                    .frame(height: 0.5)
                    .padding(.vertical, 2)
                if let area = readout.totalAreaText { selectionRow("TOTAL AREA", area, emphasized: true) }
                if let length = readout.totalLengthText { selectionRow("TOTAL LENGTH", length, emphasized: true) }
            }
        }
        .padding(10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    private func selectionRow(_ label: String, _ value: String, emphasized: Bool = false, accent: Color = OPSStyle.Colors.primaryAccent) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: emphasized ? 10 : 9, weight: .semibold, design: .monospaced))
                .foregroundColor(emphasized ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: emphasized ? 13 : 11, weight: emphasized ? .bold : .semibold, design: .monospaced))
                .foregroundColor(emphasized ? accent : OPSStyle.Colors.primaryText)
                .lineLimit(1)
        }
    }

    // MARK: - Measure Card (polyline readout)

    /// The card earns its spot only when it adds information beyond the
    /// per-segment pills: a running total across 2+ segments, or the
    /// area + perimeter of a closed loop (closing requires 3 points).
    private var showsMeasureCard: Bool {
        toolState.measurementPoints.count >= 3
    }

    /// Measure-mode readout card — the peek-sheet pattern in the measure
    /// tool's color. Open run: running total + segment count. Closed loop:
    /// area + perimeter.
    private var measureSheet: some View {
        let readout = DeckMeasureReadout.build(
            points: toolState.measurementPoints,
            closed: toolState.measurementPhase == .closed,
            scaleFactor: drawingData.effectiveScaleFactor,
            system: drawingData.config.measurementSystem
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("MEASURE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 12)
                Button {
                    toolState.clearMeasurement()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("CLEAR")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .accessibilityLabel("Clear measurement")
            }

            if let area = readout.areaText {
                selectionRow("AREA", area.uppercased(), emphasized: true, accent: OPSStyle.Colors.warningStatus)
            }
            if let perimeter = readout.perimeterText {
                selectionRow("PERIMETER", perimeter)
            }
            if let total = readout.totalLengthText {
                selectionRow("TOTAL LENGTH", total, emphasized: true, accent: OPSStyle.Colors.warningStatus)
                selectionRow("SEGMENTS", "\(readout.segmentCount)")
            }
        }
        .padding(10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    // MARK: - Split Card (cut readout)

    /// Split readout — recomputed on every cut change. Empty until two points.
    private var splitReadout: DeckSplitReadout.Result {
        guard toolState.isSplitting, toolState.splitPoints.count == 2,
              let id = toolState.selectedSurfaceIds.first,
              toolState.selectedSurfaceIds.count == 1,
              let surface = DeckSelectionReadout.surfaceContexts(in: drawingData)
                  .first(where: { $0.face.id == id })?.face.positions
        else { return DeckSplitReadout.empty }
        return DeckSplitReadout.build(
            surface: surface,
            cutA: toolState.splitPoints[0], cutB: toolState.splitPoints[1],
            scaleFactor: drawingData.effectiveScaleFactor,
            system: drawingData.config.measurementSystem
        )
    }

    /// Split card — the peek-sheet pattern with side rows tinted to match
    /// the canvas fills (A accent, B amber).
    private var splitSheet: some View {
        let readout = splitReadout
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("SPLIT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 12)
                Button {
                    toolState.clearSplit()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("CLEAR")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .accessibilityLabel("Clear split")
            }
            if let a = readout.sideAText {
                selectionRow("SIDE A", a.uppercased(), emphasized: true, accent: OPSStyle.Colors.primaryAccent)
            }
            if let b = readout.sideBText {
                selectionRow("SIDE B", b.uppercased(), emphasized: true, accent: OPSStyle.Colors.warningStatus)
            }
            if let cut = readout.cutLengthText {
                selectionRow("CUT", cut)
            }
        }
        .padding(10)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.black.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(6)
    }

    // MARK: - Derived

    private var summaryReadout: String {
        let levelCount = drawingData.isMultiLevel ? drawingData.levels.count : 1
        let areaSqIn = drawingData.totalRealWorldArea(scaleFactor: drawingData.effectiveScaleFactor)
        let areaText = DimensionEngine.formatArea(areaSqIn, system: drawingData.config.measurementSystem).uppercased()
        return "\(levelCount) LVL · \(areaText)"
    }

    /// Live instruction for the active tool. Split hints take over while the
    /// scissors are armed; measure hints otherwise. Each state teaches only
    /// the newly unlocked, non-obvious action.
    private var measurementHint: String? {
        if toolState.isSplitting {
            switch toolState.splitPoints.count {
            case 0: return "TAP POINT"
            case 1: return "TAP ACROSS"
            default: return splitReadout.didSplit ? "TAP TO RE-CUT" : "DRAW ACROSS THE FACE"
            }
        }
        guard toolState.isMeasuring else { return nil }
        switch toolState.measurementPhase {
        case .finished, .closed:
            return "TAP TO RESET"
        case .drawing:
            switch toolState.measurementPoints.count {
            case 0: return "TAP POINT"
            case 1: return "TAP NEXT"
            case 2: return "TAP LAST TO FINISH"
            default: return "TAP FIRST TO CLOSE"
            }
        }
    }

    /// Chrome fades to 0 while the viewport is being manipulated so the canvas
    /// is never obstructed mid-inspection. Reduce Motion still hides it (via a
    /// nil animation on the modifier) — the value change is instant.
    private var chromeOpacity: Double { isViewportInteracting ? 0 : 1 }

    // MARK: - Isolate cycling

    /// Cycle the isolated level: none → first → second → … → none.
    private func cycleIsolatedLevel() {
        let ids = drawingData.levels.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
        guard !ids.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let current = toolState.isolatedLevelId, let idx = ids.firstIndex(of: current) else {
            toolState.isolatedLevelId = ids.first
            return
        }
        let next = idx + 1
        toolState.isolatedLevelId = next < ids.count ? ids[next] : nil
    }

    // MARK: - Dismiss

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Track only downward pulls; ignore upward.
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(OPSStyle.Animation.standard) { dragOffset = 0 }
                }
            }
    }

    private func dismiss() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dragOffset = 0
        onClose()
    }
}
