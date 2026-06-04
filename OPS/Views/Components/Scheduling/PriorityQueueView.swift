import SwiftUI

struct PriorityQueueView: View {
    enum DisplayMode { case fullScreen, inline }

    @EnvironmentObject private var dataController: DataController
    @StateObject private var vm: PriorityQueueViewModel
    let displayMode: DisplayMode
    var onClose: (() -> Void)? = nil

    @State private var waterlineEngaged = false
    @State private var waterlineSteps = 0
    @State private var waterlineDragStartY: CGFloat?
    @State private var selectionFeedback = UISelectionFeedbackGenerator()
    @State private var impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let waterlineRowHeight: CGFloat = OPSStyle.Layout.touchTargetStandard
    private static let waterlineSpace = "priorityQueueWaterline"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .sheet(item: Binding(get: { vm.previewPlan.map { PlanBox(plan: $0) } }, set: { if $0 == nil { vm.previewPlan = nil } })) { box in
            PrioritySchedulePreviewSheet(plan: box.plan, anchorDate: vm.anchorDate) {
                Task { await vm.commit(plan: box.plan) }
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
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(OPSStyle.Colors.cardBackgroundDark))
                .overlay(Capsule().stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                .padding(.top, 12)
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
        .padding(16)
    }

    private var toggles: some View {
        HStack(spacing: 12) {
            toggleChip("INCLUDE UNRANKED", isOn: vm.includeUnranked) { vm.includeUnranked.toggle() }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var list: some View {
        List {
            Section {
                if displayRanked.isEmpty {
                    Text("Drag projects up to rank them, or turn on Include Unranked.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(displayRanked.enumerated()), id: \.element.id) { idx, project in
                        PriorityQueueRow(project: project,
                                         rankNumber: idx + 1,
                                         pending: pendingState(combinedIndex: idx),
                                         isWaterline: isWaterlineRow(combinedIndex: idx))
                            .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        vm.moveRanked(projectId: displayRanked[f].id, to: to > f ? to - 1 : to)
                    }
                }
            } header: {
                Text("RANKED").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Section {
                ForEach(Array(displayUnranked.enumerated()), id: \.element.id) { localIdx, project in
                    let combinedIdx = vm.ranked.count + localIdx
                    PriorityQueueRow(project: project,
                                     rankNumber: nil,
                                     pending: pendingState(combinedIndex: combinedIdx),
                                     isWaterline: isWaterlineRow(combinedIndex: combinedIdx))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading) {
                            Button("Rank") { vm.rank(projectId: project.id, at: vm.ranked.count) }
                                .tint(OPSStyle.Colors.primaryAccent)
                        }
                }
            } header: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(waterlineEngaged ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    Text(waterlineLabel)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(waterlineEngaged ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    Spacer()
                }
                .contentShape(Rectangle())
                .gesture(waterlineGesture)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .coordinateSpace(.named(Self.waterlineSpace))
        .animation(reduceMotion ? Optional<Animation>.none : OPSStyle.Animation.standard, value: waterlineSteps)
        .animation(reduceMotion ? Optional<Animation>.none : OPSStyle.Animation.standard, value: waterlineEngaged)
        .animation(reduceMotion ? Optional<Animation>.none : OPSStyle.Animation.standard, value: vm.ranked.count)
    }

    private var runBar: some View {
        HStack(spacing: 12) {
            Button { Task { await vm.tapToPlaceNext() } } label: {
                Text("SCHEDULE NEXT").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryRunButtonStyle())
            .disabled(vm.ranked.allSatisfy { p in
                !p.tasks.contains { $0.deletedAt == nil && $0.status == .active && ($0.startDate == nil || $0.endDate == nil) }
            })

            Button {
                vm.buildPlan()
            } label: {
                Text("SCHEDULE ALL").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryRunButtonStyle())
            .disabled(vm.ranked.isEmpty)
        }
        .padding(16)
    }

    private var waterlineLabel: String {
        if waterlineSteps > 0 { return "UNRANKED  +\(waterlineSteps) ranked" }
        if waterlineSteps < 0 { return "UNRANKED  \(waterlineSteps) ranked" }
        return "UNRANKED"
    }

    // MARK: - Waterline target (non-reflowing preview)
    // The rows stay in COMMITTED order while the UNRANKED handle is dragged — they
    // do NOT reflow. Reflowing mid-drag slid the sticky header (the drag target),
    // which shifted the finger→row mapping and made the list oscillate. Instead the
    // target boundary is painted in place (accent fill + waterline) and the reflow
    // is committed once, on release, via setWaterline.

    private var combinedProjects: [Project] { vm.ranked + vm.unranked }

    /// Where the waterline will land = committed ranked count shifted by the drag.
    private var targetRankedCount: Int {
        let base = vm.ranked.count + (waterlineEngaged ? waterlineSteps : 0)
        return min(max(base, 0), combinedProjects.count)
    }

    // Frozen while dragging: the rows never reflow until commit.
    private var displayRanked: [Project] { vm.ranked }
    private var displayUnranked: [Project] { vm.unranked }

    /// Pending crossing state for the row at `combinedIndex` (ranked first, then
    /// unranked). Rows that will flip side are accented (→ ranked) or dimmed
    /// (→ unranked) so the waterline reads as moving between rows without reflow.
    private func pendingState(combinedIndex i: Int) -> PriorityQueueRow.Pending {
        guard waterlineEngaged else { return .none }
        let committedRanked = vm.ranked.count
        let willBeRanked = i < targetRankedCount
        let isRanked = i < committedRanked
        if isRanked && !willBeRanked { return .willUnrank }
        if !isRanked && willBeRanked { return .willRank }
        return .none
    }

    /// The boundary row — the first row that will be UNRANKED after commit — draws
    /// the waterline on its top edge. Hidden when everything ends up ranked.
    private func isWaterlineRow(combinedIndex i: Int) -> Bool {
        waterlineEngaged && i == targetRankedCount && i < combinedProjects.count
    }

    /// Long-press to engage, then drag up/down. The rows DON'T reflow while dragging
    /// (see `displayRanked`/`displayUnranked`), so the UNRANKED header — the drag
    /// target — stays put and can't feed its own movement back into the measurement.
    /// That frozen layout, not the coordinate space, is what kills the oscillation;
    /// reading the finger's absolute position in `waterlineSpace` is belt-and-braces.
    /// Each `rowHeight` of travel flips one row; a deadband (`steppedWaterline`) keeps
    /// the boundary from chattering when the finger hovers on a row midpoint.
    /// Drag DOWN (positive) = more ranked; UP = fewer.
    private var waterlineGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.waterlineSpace)))
            .onChanged { value in
                switch value {
                case .first(true):
                    if !waterlineEngaged {
                        waterlineEngaged = true
                        impactFeedback.impactOccurred()        // medium on engage
                        selectionFeedback.prepare()            // warm Taptic for per-row ticks
                        impactFeedback.prepare()               // warm for the commit-on-release
                    }
                case .second(true, let drag?):
                    // Anchor on the first drag sample, then measure pure finger travel
                    // in the fixed space — immune to the header reflowing underneath.
                    if waterlineDragStartY == nil { waterlineDragStartY = drag.location.y }
                    guard let startY = waterlineDragStartY else { break }
                    let offsetRows = (drag.location.y - startY) / waterlineRowHeight
                    let stepped = steppedWaterline(offsetRows: offsetRows, current: waterlineSteps)
                    let clamped = min(max(stepped, -vm.ranked.count), vm.unranked.count)
                    if clamped != waterlineSteps {
                        selectionFeedback.selectionChanged()
                        selectionFeedback.prepare()            // re-warm for the next tick
                        waterlineSteps = clamped
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                let newCount = targetRankedCount
                if newCount != vm.ranked.count {
                    impactFeedback.impactOccurred()            // medium on commit
                    vm.setWaterline(rankedCount: newCount)
                }
                waterlineEngaged = false
                waterlineSteps = 0
                waterlineDragStartY = nil
            }
    }

    /// Quantize a continuous row-offset to an integer step through a 0.4-row deadband:
    /// hold the current step until travel clears the row midpoint by `deadband`, then
    /// snap to the nearest step. Asymmetric thresholds (up at s+0.7, back at s+0.3)
    /// prevent flip-flop; a fast drag still jumps multiple steps via `rounded()`.
    private func steppedWaterline(offsetRows x: CGFloat, current s: Int) -> Int {
        let deadband: CGFloat = 0.2                  // hold zone = ±(0.5 + deadband) rows around s
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
                .foregroundColor(isOn ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius).fill(isOn ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark))
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius).stroke(isOn ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
        }
    }
}

/// Identifiable box so SchedulePlan can drive a `.sheet(item:)`.
private struct PlanBox: Identifiable { let id = UUID(); let plan: SchedulePlan }

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
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius).stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
