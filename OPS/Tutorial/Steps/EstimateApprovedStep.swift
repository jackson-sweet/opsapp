import SwiftUI

/// Step 3: "Won — Tasks Auto-Generate"
///
/// Emotional beat: ACHIEVEMENT
/// The magic moment. Estimate approved → tasks auto-generate from labor items.
/// Now with clear contextual labels explaining what's happening.
struct EstimateApprovedStep: View {

    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: StepPhase = .waiting
    @State private var visibleTasks: Int = 0
    @State private var showCrew: Bool = false
    @State private var showExplainer: Bool = false

    private enum StepPhase {
        case waiting
        case notification
        case explaining
        case transforming
        case settled
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Context label at top of content area
            if phase == .notification || phase == .explaining {
                contextLabel
                    .padding(.bottom, OPSStyle.Layout.spacing4)
            }

            if phase == .transforming || phase == .settled {
                transformLabel
                    .padding(.bottom, OPSStyle.Layout.spacing3)
            }

            // Main content
            ZStack {
                switch phase {
                case .waiting:
                    EmptyView()

                case .notification, .explaining:
                    approvalCard
                        .transition(.move(edge: .top).combined(with: .opacity))

                case .transforming, .settled:
                    taskCardsView
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startSequence() }
    }

    // MARK: - Context Labels

    private var contextLabel: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Text("CLIENT APPROVED YOUR ESTIMATE")
                .font(.microLabel)
                .foregroundStyle(OPSStyle.Colors.successStatus)
                .tracking(1.5)
            if showExplainer {
                Text("Tasks generate automatically from labor items.")
                    .font(.smallCaption)
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var transformLabel: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Text("TASKS AUTO-GENERATED")
                .font(.microLabel)
                .foregroundStyle(OPSStyle.Colors.primaryAccent)
                .tracking(1.5)
            Text("Zero duplicate entry. Crew auto-assigned.")
                .font(.smallCaption)
                .foregroundStyle(OPSStyle.Colors.tertiaryText)
        }
        .multilineTextAlignment(.center)
        .transition(.opacity)
    }

    // MARK: - Approval Notification

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(OPSStyle.Colors.successStatus)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ESTIMATE APPROVED")
                        .font(.status)
                        .foregroundStyle(OPSStyle.Colors.successStatus)
                        .tracking(1.5)
                    Text("\(TutorialData.clientName) accepted")
                        .font(.body)
                        .foregroundStyle(OPSStyle.Colors.primaryText)
                }
            }

            // Show the line items that will become tasks
            if showExplainer {
                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(height: 0.5)
                    .padding(.vertical, OPSStyle.Layout.spacing1)

                ForEach(TutorialData.lineItems) { item in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(item.type.color)
                            .frame(width: 3, height: 20)

                        Text(item.name)
                            .font(.smallBody)
                            .foregroundStyle(OPSStyle.Colors.primaryText.opacity(0.6))

                        Spacer()

                        Text(item.type.rawValue)
                            .font(.microLabel)
                            .foregroundStyle(item.type.color.opacity(0.5))
                            .tracking(0.8)

                        // Arrow for labor items → becomes task
                        if item.type == .labor {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(OPSStyle.Colors.primaryAccent.opacity(0.5))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.successStatus.opacity(0.2), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Task Cards

    private var taskCardsView: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(Array(TutorialData.taskCards.prefix(visibleTasks).enumerated()), id: \.element.id) { _, task in
                taskCard(task)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: -20)),
                        removal: .opacity
                    ))
            }
        }
    }

    private func taskCard(_ task: TutorialData.TaskCard) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(task.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name.uppercased())
                    .font(.bodyBold)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.5)

                Text("BOOKED")
                    .font(.microLabel)
                    .foregroundStyle(OPSStyle.Colors.inactiveStatus)
                    .tracking(1)
            }

            Spacer()

            if showCrew {
                HStack(spacing: 6) {
                    Circle()
                        .fill(crewColor(for: task).opacity(0.2))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(crewColor(for: task))
                        )
                    Text(task.crew)
                        .font(.smallCaption)
                        .foregroundStyle(OPSStyle.Colors.secondaryText)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(height: 48)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func crewColor(for task: TutorialData.TaskCard) -> Color {
        TutorialData.crewMembers.first(where: { $0.name == task.crew })?.color ?? OPSStyle.Colors.primaryAccent
    }

    // MARK: - Sequence

    private func startSequence() {
        guard !reduceMotion else {
            phase = .settled
            visibleTasks = TutorialData.taskCards.count
            showCrew = true; showExplainer = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { onComplete() }
            return
        }

        // 0.4s — Notification drops in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.3)) {
                phase = .notification
            }
            TutorialHaptics.milestone()
        }

        // 1.5s — Show the estimate line items inside the card + explainer text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                phase = .explaining
                showExplainer = true
            }
        }

        // 3.5s — Transform: labor items become task cards
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeOut(duration: 0.25)) {
                phase = .transforming
            }

            for i in 0..<TutorialData.taskCards.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + (Double(i) * 0.15)) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        visibleTasks = i + 1
                    }
                    TutorialHaptics.arrival()
                }
            }
        }

        // Crew docks
        let crewDelay = 3.5 + (Double(TutorialData.taskCards.count) * 0.15) + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + crewDelay) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCrew = true
                phase = .settled
            }
        }

        // Auto-advance
        DispatchQueue.main.asyncAfter(deadline: .now() + crewDelay + 1.5) {
            onComplete()
        }
    }
}
