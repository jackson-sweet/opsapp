import SwiftUI

struct PriorityQueueView: View {
    enum DisplayMode { case fullScreen, inline }

    @EnvironmentObject private var dataController: DataController
    @StateObject private var vm: PriorityQueueViewModel
    let displayMode: DisplayMode
    var onClose: (() -> Void)? = nil

    // Waterline drag (move the boundary between ranked/unranked)
    @State private var waterlineEngaged = false
    @State private var waterlineSteps = 0
    @State private var waterlineDragOffset: CGFloat = 0
    // Card drag (reorder within ranked, or cross the waterline to rank/unrank)
    @State private var draggingCardId: String?
    @State private var cardDragOffset: CGFloat = 0
    // Safety: @GestureState auto-resets the instant a gesture ends OR is cancelled /
    // torn down (e.g. when committing rebuilds the list). It drives the cleanup of
    // the @State flags above so they can never get stuck "engaged" — which would
    // otherwise leave a displaced, touch-eating handle on top of the list.
    @GestureState private var waterlineGestureActive = false
    @GestureState private var cardGestureActive = false

    @State private var selectionFeedback = UISelectionFeedbackGenerator()
    @State private var impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Layout constants — one card pitch drives both finger→slot mapping and gap shifts.
    private let cardHeight: CGFloat = OPSStyle.Layout.touchTargetStandard   // 56
    private let rowSpacing: CGFloat = 8
    private var rowPitch: CGFloat { cardHeight + rowSpacing }               // 64
    private let waterlineGap: CGFloat = 44      // extra space opened at the dragged boundary
    private let fadeBelow: Double = 0.4         // unranked-below-the-line opacity during drag

    init(displayMode: DisplayMode, dataController: DataController, onClose: (() -> Void)? = nil) {
        self.displayMode = displayMode
        self.onClose = onClose
        _vm = StateObject(wrappedValue: PriorityQueueViewModel(dataController: dataController))
    }

    var body: some View {
        VStack(spacing: 0) {
            if displayMode == .fullScreen { header }
            toggles
            list
            runBar
        }
        .background(OPSStyle.Colors.background)
        .sheet(item: $vm.previewPlan) { preview in
            PrioritySchedulePreviewSheet(plan: preview.plan, anchorDate: vm.anchorDate) {
                Task { await vm.commit(plan: preview.plan) }
            }
            .environmentObject(dataController)
        }
        .overlay(alignment: .top) { confirmationBanner }
        .onChange(of: vm.justScheduledCount) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(OPSStyle.Animation.standard) { vm.justScheduledCount = nil }
            }
        }
        .animation(OPSStyle.Animation.standard, value: vm.justScheduledCount)
    }

    @ViewBuilder private var confirmationBanner: some View {
        if let n = vm.justScheduledCount {
            Text("\(n) scheduled")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3).padding(.vertical, 10)
                .background(Capsule().fill(OPSStyle.Colors.glassDenseApprox))
                .overlay(Capsule().stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                .padding(.top, OPSStyle.Layout.spacing2_5)
                .transition(.opacity)
        }
    }

    private var header: some View {
        HStack {
            Text("PRIORITIZE")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Button("DONE") { onClose?() }
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(OPSStyle.Layout.spacing3)
    }

    private var toggles: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            toggleChip("INCLUDE UNRANKED", isOn: vm.includeUnranked) { vm.includeUnranked.toggle() }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3).padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - The prioritized list (custom scroll + VStack)
    // A single committed-order column of cards split by a draggable waterline.
    // Drag the waterline → cards spread to open a gap at the target boundary, the
    // divider rides in the gap, and the cards that will be unranked fade below it.
    // Drag a card → it lifts and reorders (within ranked) or crosses the waterline
    // to rank/unrank. The dragged element follows the finger via `.offset`, which is
    // visual-only and never moves the gesture's layout frame — so there is no
    // reflow→measurement feedback loop (the same reason FloatingActionMenu is stable).

    private var list: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: rowSpacing) {
                if vm.ranked.isEmpty {
                    emptyRankedHint
                } else {
                    ForEach(Array(vm.ranked.enumerated()), id: \.element.id) { i, project in
                        card(project, combinedIndex: i)
                    }
                }

                if !combinedProjects.isEmpty {
                    waterlineHandle
                }

                ForEach(Array(vm.unranked.enumerated()), id: \.element.id) { j, project in
                    card(project, combinedIndex: vm.ranked.count + j)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .scrollDisabled(waterlineEngaged || draggingCardId != nil)
        // When either gesture deactivates (lift OR cancel OR teardown), force the
        // transient @State back to rest — guarantees the handle/cards never stick.
        .onChange(of: waterlineGestureActive) { _, active in
            guard !active, waterlineEngaged || waterlineSteps != 0 || waterlineDragOffset != 0 else { return }
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.standard) {
                waterlineEngaged = false
                waterlineSteps = 0
                waterlineDragOffset = 0
            }
        }
        .onChange(of: cardGestureActive) { _, active in
            guard !active, draggingCardId != nil || cardDragOffset != 0 else { return }
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.standard) {
                draggingCardId = nil
                cardDragOffset = 0
            }
        }
    }

    private var emptyRankedHint: some View {
        Text("Drag projects above the line to rank them. The top of the queue schedules first.")
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    // MARK: Card

    @ViewBuilder
    private func card(_ project: Project, combinedIndex i: Int) -> some View {
        let isThisDragging = draggingCardId == project.id
        PriorityQueueRow(project: project, rankNumber: rankNumber(combinedIndex: i), lifted: isThisDragging)
            .opacity(cardOpacity(combinedIndex: i, project: project))
            .offset(y: cardOffsetY(combinedIndex: i, project: project))
            .zIndex(isThisDragging ? 10 : 0)
            .animation(isThisDragging || reduceMotion ? nil : OPSStyle.Animation.standard,
                       value: cardOffsetY(combinedIndex: i, project: project))
            .animation(reduceMotion ? nil : OPSStyle.Animation.standard,
                       value: cardOpacity(combinedIndex: i, project: project))
            // Drag only from the trailing grip zone — the rest of the card scrolls.
            .overlay(alignment: .trailing) {
                Color.clear
                    .frame(width: 56)
                    .contentShape(Rectangle())
                    .gesture(cardDragGesture(project: project, combinedIndex: i))
            }
    }

    // MARK: Waterline handle

    private var waterlineHandle: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(waterlineEngaged ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                Text(waterlineLabel)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(waterlineEngaged ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 14)

            // Hairline sits BELOW the label, spanning the full width.
            Rectangle()
                .fill(waterlineEngaged ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder)
                .frame(height: waterlineEngaged ? 2 : 1)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .contentShape(Rectangle())
        .offset(y: waterlineHandleOffset)
        .animation(waterlineEngaged || reduceMotion ? nil : OPSStyle.Animation.standard, value: waterlineHandleOffset)
        .scaleEffect(waterlineEngaged ? 1.02 : 1.0, anchor: .center)
        .shadow(color: Color.black.opacity(waterlineEngaged ? 0.3 : 0),
                radius: waterlineEngaged ? 10 : 0, x: 0, y: waterlineEngaged ? 4 : 0)
        .zIndex(waterlineEngaged ? 20 : 0)
        .gesture(waterlineGesture)
    }

    private var runBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Button { Task { await vm.tapToPlaceNext() } } label: {
                Text("SCHEDULE NEXT").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryRunButtonStyle())
            .disabled(!vm.canScheduleNext)

            Button {
                vm.buildPlan()
            } label: {
                Text("SCHEDULE ALL").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryRunButtonStyle())
            .disabled(!vm.canScheduleAll)
        }
        .padding(OPSStyle.Layout.spacing3)
    }

    private var waterlineLabel: String {
        if waterlineSteps > 0 { return "UNRANKED  +\(waterlineSteps) ranked" }
        if waterlineSteps < 0 { return "UNRANKED  \(waterlineSteps) ranked" }
        return "UNRANKED"
    }

    // MARK: - Geometry / styling helpers

    private var combinedProjects: [Project] { vm.ranked + vm.unranked }
    private var totalCount: Int { combinedProjects.count }
    private var committedRanked: Int { vm.ranked.count }

    /// Where the waterline will land = committed ranked count shifted by the drag.
    private var targetRankedCount: Int {
        let base = committedRanked + (waterlineEngaged ? waterlineSteps : 0)
        return min(max(base, 0), totalCount)
    }

    /// Provisional rank number: above the (live) boundary → numbered, below → unranked.
    private func rankNumber(combinedIndex i: Int) -> Int? {
        i < targetRankedCount ? i + 1 : nil
    }

    /// Fade the cards that sit below the waterline during a waterline drag.
    private func cardOpacity(combinedIndex i: Int, project: Project) -> Double {
        if draggingCardId == project.id { return 0.95 }
        if waterlineEngaged && i >= targetRankedCount { return fadeBelow }
        return 1
    }

    private func combinedIndex(of id: String) -> Int? {
        combinedProjects.firstIndex { $0.id == id }
    }

    /// Per-card vertical offset: the dragged element follows the finger; siblings
    /// shift to open a gap at the target slot (visual-only — never reflows layout).
    private func cardOffsetY(combinedIndex i: Int, project: Project) -> CGFloat {
        if draggingCardId == project.id { return cardDragOffset }
        if let draggingId = draggingCardId, let dIdx = combinedIndex(of: draggingId) {
            return cardReorderOffset(thisIndex: i, draggingIndex: dIdx)
        }
        if waterlineEngaged {
            return i >= targetRankedCount ? waterlineGap : 0
        }
        return 0
    }

    /// Gap-opening offset for non-dragged cards while a card is being dragged
    /// (FloatingActionMenu's `itemVisualOffset` pattern, across the combined list).
    private func cardReorderOffset(thisIndex: Int, draggingIndex: Int) -> CGFloat {
        let steps = Int((cardDragOffset / rowPitch).rounded())
        let target = min(max(draggingIndex + steps, 0), totalCount - 1)
        if draggingIndex < target {
            if thisIndex > draggingIndex && thisIndex <= target { return -rowPitch }
        } else if draggingIndex > target {
            if thisIndex >= target && thisIndex < draggingIndex { return rowPitch }
        }
        return 0
    }

    /// The waterline handle follows the finger while it is dragged; while a CARD is
    /// dragged it shifts with the boundary cards (its committed position is index
    /// `committedRanked`) so a crossing card never slides over a static handle.
    private var waterlineHandleOffset: CGFloat {
        if waterlineEngaged { return waterlineDragOffset }
        if let draggingId = draggingCardId, let dIdx = combinedIndex(of: draggingId) {
            // The handle lives BETWEEN index R-1 and R, so it must track whichever
            // neighbour stays put: a card dragged from BELOW it (dIdx >= R) → follow
            // the ranked card above (R-1); from ABOVE (dIdx < R) → follow the unranked
            // card below (R). A single fixed index left the handle behind when the
            // first unranked card crossed up, so the last ranked card slid over it.
            let boundaryRef = dIdx >= committedRanked ? committedRanked - 1 : committedRanked
            return cardReorderOffset(thisIndex: boundaryRef, draggingIndex: dIdx)
        }
        return 0
    }

    // MARK: - Gestures

    /// Long-press the waterline, then drag up/down. `waterlineDragOffset` follows the
    /// finger via `.offset` (visual-only → the handle's layout frame is fixed → local
    /// `translation` stays true → no oscillation). A hysteresis deadband keeps the
    /// boundary from chattering at a card midpoint. DOWN = more ranked; UP = fewer.
    private var waterlineGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($waterlineGestureActive) { _, state, _ in state = true }
            .onChanged { value in
                switch value {
                case .first(true):
                    if !waterlineEngaged {
                        waterlineEngaged = true
                        waterlineSteps = 0          // fresh start, regardless of how the last drag ended
                        waterlineDragOffset = 0
                        impactFeedback.impactOccurred()
                        selectionFeedback.prepare()
                        impactFeedback.prepare()
                    }
                case .second(true, let drag?):
                    waterlineDragOffset = drag.translation.height
                    let stepped = steppedWaterline(offsetRows: waterlineDragOffset / rowPitch, current: waterlineSteps)
                    let clamped = min(max(stepped, -committedRanked), vm.unranked.count)
                    if clamped != waterlineSteps {
                        selectionFeedback.selectionChanged()
                        selectionFeedback.prepare()
                        waterlineSteps = clamped
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                let newCount = targetRankedCount
                let changed = newCount != committedRanked
                if changed { impactFeedback.impactOccurred() }
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.standard) {
                    if changed { vm.setWaterline(rankedCount: newCount) }
                    waterlineEngaged = false
                    waterlineSteps = 0
                    waterlineDragOffset = 0
                }
            }
    }

    /// Long-press a card to lift it, then drag. Within ranked → reorder; across the
    /// waterline → rank / unrank (replaces the old swipe-to-rank).
    private func cardDragGesture(project: Project, combinedIndex i: Int) -> some Gesture {
        // Immediate drag — it lives only on the trailing grip zone (see `card`), so
        // the rest of the card body stays free for the ScrollView to pan.
        DragGesture(minimumDistance: 6)
            .updating($cardGestureActive) { _, state, _ in state = true }
            .onChanged { value in
                if draggingCardId == nil {
                    draggingCardId = project.id
                    cardDragOffset = 0          // fresh start, regardless of how the last drag ended
                    impactFeedback.impactOccurred()
                    selectionFeedback.prepare()
                }
                cardDragOffset = value.translation.height
            }
            .onEnded { _ in
                commitCardDrag(project: project, fromIndex: i)
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.standard) {
                    cardDragOffset = 0
                    draggingCardId = nil
                }
            }
    }

    private func commitCardDrag(project: Project, fromIndex i: Int) {
        let steps = Int((cardDragOffset / rowPitch).rounded())
        let target = min(max(i + steps, 0), totalCount - 1)
        guard target != i else { return }

        let wasRanked = i < committedRanked
        let landsRanked = target < committedRanked

        if wasRanked && landsRanked {
            vm.moveRanked(projectId: project.id, to: target)
            impactFeedback.impactOccurred()
        } else if wasRanked && !landsRanked {
            vm.unrank(projectId: project.id)
            impactFeedback.impactOccurred()
        } else if !wasRanked && landsRanked {
            vm.rank(projectId: project.id, at: target)
            impactFeedback.impactOccurred()
        }
        // unranked → unranked: no user-defined order, no-op (card snaps back).
    }

    /// Quantize a continuous row-offset to an integer step through a 0.4-row deadband:
    /// hold the current step until travel clears the row midpoint by `deadband`, then
    /// snap to the nearest step. Asymmetric thresholds (up at s+0.7, back at s+0.3)
    /// prevent flip-flop; a fast drag still jumps multiple steps via `rounded()`.
    private func steppedWaterline(offsetRows x: CGFloat, current s: Int) -> Int {
        let deadband: CGFloat = 0.2
        if x > CGFloat(s) + 0.5 + deadband || x < CGFloat(s) - 0.5 - deadband {
            return Int(x.rounded())
        }
        return s
    }

    @ViewBuilder
    private func toggleChip(_ label: String, isOn: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(isOn ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5).padding(.vertical, OPSStyle.Layout.spacing2)
                .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius).fill(isOn ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput))
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius).stroke(isOn ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
        }
    }
}

private struct PrimaryRunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.button)
            .foregroundColor(.white)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
private struct SecondaryRunButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.button)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius).stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
