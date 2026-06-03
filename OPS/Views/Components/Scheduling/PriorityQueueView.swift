import SwiftUI

struct PriorityQueueView: View {
    enum DisplayMode { case fullScreen, inline }

    @EnvironmentObject private var dataController: DataController
    @StateObject private var vm: PriorityQueueViewModel
    let displayMode: DisplayMode
    var onClose: (() -> Void)? = nil

    @State private var showConfirm = false
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
        .alert("Move scheduled tasks?", isPresented: $showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") { vm.buildPlan() }
        } message: {
            Text("This moves \(vm.pendingConfirmCount) already-scheduled tasks.")
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
            toggleChip("MOVE SCHEDULED", isOn: vm.rescheduleScheduled) { vm.rescheduleScheduled.toggle() }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var list: some View {
        List {
            Section {
                if vm.ranked.isEmpty {
                    Text("Drag tasks up to rank them, or turn on Include Unranked.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(vm.ranked.enumerated()), id: \.element.id) { idx, task in
                        PriorityQueueRow(task: task, rankNumber: idx + 1)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        vm.moveRanked(taskId: vm.ranked[f].id, to: to > f ? to - 1 : to)
                    }
                }
            } header: {
                Text("RANKED").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Section {
                ForEach(vm.unranked, id: \.id) { task in
                    PriorityQueueRow(task: task, rankNumber: nil)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading) {
                            Button("Rank") { vm.rank(taskId: task.id, at: vm.ranked.count) }
                                .tint(OPSStyle.Colors.primaryAccent)
                        }
                }
            } header: {
                Text("UNRANKED").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
    }

    private var runBar: some View {
        HStack(spacing: 12) {
            Button { Task { await vm.tapToPlaceNext() } } label: {
                Text("SCHEDULE NEXT").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryRunButtonStyle())
            .disabled(vm.ranked.allSatisfy { $0.startDate != nil })

            Button {
                let moves = vm.scheduledMoveCount()
                if moves > 0 { vm.pendingConfirmCount = moves; showConfirm = true } else { vm.buildPlan() }
            } label: {
                Text("SCHEDULE ALL").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryRunButtonStyle())
            .disabled(vm.ranked.isEmpty)
        }
        .padding(16)
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
