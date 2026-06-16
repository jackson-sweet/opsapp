//
//  TaskCompletionChecklistSheet.swift
//  OPS
//
//  Sheet for completing task-based projects - requires all tasks to be marked complete
//

import SwiftUI
import SwiftData

struct TaskCompletionChecklistSheet: View {
    let project: Project
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @State private var taskStates: [String: Bool] = [:]

    private var allTasksComplete: Bool {
        let incompleteTasks = project.tasksBlockingCompletion
        return incompleteTasks.allSatisfy { taskStates[$0.id] == true }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                            headerSection

                            if project.tasksBlockingCompletion.isEmpty {
                                allTasksAlreadyCompleteView
                            } else {
                                taskChecklistSection
                            }
                        }
                        .padding()
                    }

                    completeButtonSection
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("COMPLETE PROJECT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text(project.title.uppercased())
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Mark all incomplete tasks as complete before finishing this project.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.top, OPSStyle.Layout.spacing1)
        }
    }

    private var allTasksAlreadyCompleteView: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text("All tasks for this project have been completed.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing4)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var taskChecklistSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("INCOMPLETE TASKS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                let blockingTasks = project.tasksBlockingCompletion
                ForEach(blockingTasks, id: \.id) { task in
                    taskChecklistRow(task: task)
                    if task.id != blockingTasks.last?.id {
                        Divider()
                            .background(OPSStyle.Colors.subtleBackground)
                    }
                }
            }
        }
    }

    private func taskChecklistRow(task: ProjectTask) -> some View {
        Button(action: {
            withAnimation(OPSStyle.Animation.fast) {
                taskStates[task.id] = !(taskStates[task.id] ?? false)
            }

            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                ZStack {
                    Circle()
                        .stroke(taskStates[task.id] == true ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        .frame(width: 20, height: 20)

                    if taskStates[task.id] == true {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text((task.taskType?.display ?? "Task").uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(task.status.displayName.uppercased())
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()

                if let date = task.scheduledDate {
                    Text(formatDate(date))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var completeButtonSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(OPSStyle.Colors.subtleBackground)

            Button(action: {
                completeAllTasksAndProject()
            }) {
                Text("COMPLETE PROJECT")
                    .font(OPSStyle.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                    .foregroundColor(allTasksComplete ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(allTasksComplete ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .disabled(!allTasksComplete)
            .padding()
            .background(OPSStyle.Colors.background)
        }
    }

    private func completeAllTasksAndProject() {
        let incompleteTasks = project.tasksBlockingCompletion

        Task {
            for task in incompleteTasks where taskStates[task.id] == true {
                do {
                    // Set end date on task directly
                    await MainActor.run {
                        task.endDate = Date()
                    }

                    // Use centralized status update function
                    try await dataController.updateTaskStatus(task: task, to: .completed)
                } catch {
                    print("[TASK] Failed to sync task status: \(error)")
                }
            }

            await MainActor.run {
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()

                dismiss()
                onComplete()
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
