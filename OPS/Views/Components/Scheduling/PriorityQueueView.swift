import SwiftUI

struct PriorityQueueView: View {
    enum DisplayMode { case fullScreen, inline }

    @EnvironmentObject private var dataController: DataController
    @StateObject private var vm: PriorityQueueViewModel
    let displayMode: DisplayMode
    var onClose: (() -> Void)? = nil

    @State private var waterlineEngaged = false
    @State private var waterlineSteps = 0
    private let waterlineRowHeight: CGFloat = OPSStyle.Layout.touchTargetStandard
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
                        PriorityQueueRow(project: project, rankNumber: idx + 1)
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
                ForEach(displayUnranked, id: \.id) { project in
                    PriorityQueueRow(project: project, rankNumber: nil)
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
        .animation(reduceMotion ? Optional<Animation>.none : OPSStyle.Animation.standard, value: waterlineSteps)
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

    // MARK: - Live waterline preview
    // While the UNRANKED handle is being dragged, the ranked/unranked split is
    // computed from a live preview so rows visibly reflow across the boundary
    // as the finger passes each one. Committed on release via setWaterline.

    private var combinedProjects: [Project] { vm.ranked + vm.unranked }

    private var previewRankedCount: Int {
        let base = vm.ranked.count + (waterlineEngaged ? waterlineSteps : 0)
        return min(max(base, 0), combinedProjects.count)
    }

    private var displayRanked: [Project] { Array(combinedProjects.prefix(previewRankedCount)) }
    private var displayUnranked: [Project] { Array(combinedProjects.suffix(combinedProjects.count - previewRankedCount)) }

    /// Long-press to engage, then drag up/down: each `rowHeight` of travel flips one
    /// row across the waterline. Drag DOWN (positive) = more ranked; UP = fewer.
    private var waterlineGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    if !waterlineEngaged {
                        waterlineEngaged = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                case .second(true, let drag?):
                    let raw = Int((drag.translation.height / waterlineRowHeight).rounded())
                    let clamped = min(max(raw, -vm.ranked.count), vm.unranked.count)
                    if clamped != waterlineSteps {
                        UISelectionFeedbackGenerator().selectionChanged()
                        waterlineSteps = clamped
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                let newCount = previewRankedCount
                if newCount != vm.ranked.count {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    vm.setWaterline(rankedCount: newCount)
                }
                waterlineEngaged = false
                waterlineSteps = 0
            }
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
