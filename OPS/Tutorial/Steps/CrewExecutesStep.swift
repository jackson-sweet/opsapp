import SwiftUI

/// Step 4: "Crew Executes"
///
/// Emotional beat: AMBIENT → ACHIEVEMENT
/// Before: Watching. After: "It just works."
///
/// Three task cards animate through BOOKED → IN PROGRESS → COMPLETE.
/// Then merge into a completed project card. Non-interactive.
struct CrewExecutesStep: View {

    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var statuses: [TaskStatus] = [.booked, .booked, .booked]
    @State private var showProject = false
    @State private var projectGlow: Double = 0

    private enum TaskStatus: String {
        case booked = "BOOKED"
        case inProgress = "IN PROGRESS"
        case complete = "COMPLETE"

        var color: Color {
            switch self {
            case .booked:     return OPSStyle.Colors.inactiveStatus
            case .inProgress: return OPSStyle.Colors.warningStatus
            case .complete:   return OPSStyle.Colors.successStatus
            }
        }
    }

    var body: some View {
        ZStack {
            if showProject {
                projectCard
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            } else {
                taskList
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startExecution() }
    }

    // MARK: - Task List

    private var taskList: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(Array(TutorialData.taskCards.enumerated()), id: \.element.id) { index, task in
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(task.color)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.name.uppercased())
                            .font(.bodyBold)
                            .foregroundStyle(OPSStyle.Colors.primaryText)
                            .tracking(0.5)

                        Text(statuses[index].rawValue)
                            .font(.microLabel)
                            .foregroundStyle(statuses[index].color)
                            .tracking(1)
                    }

                    Spacer()

                    if statuses[index] == .complete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(OPSStyle.Colors.successStatus)
                            .transition(.scale.combined(with: .opacity))
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
                .opacity(statuses[index] == .complete ? 0.5 : 1.0)
            }
        }
    }

    // MARK: - Project Card

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("COMPLETE")
                .font(.status)
                .foregroundStyle(OPSStyle.Colors.successStatus)
                .tracking(1.5)

            Text(TutorialData.projectTitle.uppercased())
                .font(.headingLarge)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .tracking(0.8)

            Text(TutorialData.clientName)
                .font(.caption)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.successStatus.opacity(projectGlow * 0.3), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .shadow(
            color: OPSStyle.Colors.successStatus.opacity(projectGlow * 0.06),
            radius: 16, x: 0, y: 4
        )
    }

    // MARK: - Execution Sequence

    private func startExecution() {
        guard !reduceMotion else {
            statuses = [.complete, .complete, .complete]
            showProject = true; projectGlow = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { onComplete() }
            return
        }

        // Each task: booked → inProgress (0.8s) → complete (1.2s later)
        for i in 0..<TutorialData.taskCards.count {
            let base = 0.3 + (Double(i) * 1.6)

            // → IN PROGRESS
            DispatchQueue.main.asyncAfter(deadline: .now() + base) {
                withAnimation(OPSStyle.Animation.panel) {
                    statuses[i] = .inProgress
                }
                TutorialHaptics.arrival()
            }

            // → COMPLETE
            DispatchQueue.main.asyncAfter(deadline: .now() + base + 1.0) {
                withAnimation(OPSStyle.Animation.panel) {
                    statuses[i] = .complete
                }
                TutorialHaptics.arrival()
            }
        }

        // All done → project card
        let totalTime = 0.3 + (Double(TutorialData.taskCards.count) * 1.6) + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTime) {
            TutorialHaptics.commit()
            withAnimation(OPSStyle.Animation.standard) {
                showProject = true
            }
        }

        // Project glow
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTime + 0.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                projectGlow = 1
            }
            TutorialHaptics.milestone()
        }

        // Auto-advance
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTime + 1.5) {
            onComplete()
        }
    }
}
