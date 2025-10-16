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
        let incompleteTasks = project.tasks.filter { $0.status != .completed }
        return incompleteTasks.allSatisfy { taskStates[$0.id] == true }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            headerSection

                            if project.tasks.filter({ $0.status != .completed }).isEmpty {
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
        VStack(alignment: .leading, spacing: 12) {
            Text("COMPLETE PROJECT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text(project.title.uppercased())
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Mark all incomplete tasks as complete before finishing this project.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.top, 4)
        }
    }

    private var allTasksAlreadyCompleteView: some View {
        VStack(spacing: 12) {
            Text("All tasks for this project have been completed.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var taskChecklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INCOMPLETE TASKS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                ForEach(project.tasks.filter { $0.status != .completed }, id: \.id) { task in
                    taskChecklistRow(task: task)
                    if task.id != project.tasks.filter({ $0.status != .completed }).last?.id {
                        Divider()
                            .background(Color.white.opacity(0.1))
                    }
                }
            }
        }
    }

    private func taskChecklistRow(task: ProjectTask) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                taskStates[task.id] = !(taskStates[task.id] ?? false)
            }

            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(taskStates[task.id] == true ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)

                    if taskStates[task.id] == true {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
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
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var completeButtonSection: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))

            Button(action: {
                completeAllTasksAndProject()
            }) {
                Text("COMPLETE PROJECT")
                    .font(OPSStyle.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundColor(allTasksComplete ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(allTasksComplete ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .disabled(!allTasksComplete)
            .padding()
            .background(Color.black)
        }
    }

    private func completeAllTasksAndProject() {
        let incompleteTasks = project.tasks.filter { $0.status != .completed }

        for task in incompleteTasks {
            if taskStates[task.id] == true {
                task.status = .completed
                task.needsSync = true

                if let calendarEvent = task.calendarEvent {
                    calendarEvent.endDate = Date()
                }
            }
        }

        try? dataController.modelContext?.save()

        Task {
            for task in incompleteTasks where taskStates[task.id] == true {
                await syncTaskStatusToAPI(task)
            }
        }

        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        dismiss()
        onComplete()
    }

    private func syncTaskStatusToAPI(_ task: ProjectTask) async {
        guard let syncManager = dataController.syncManager else { return }

        do {
            try await syncManager.updateTaskStatus(id: task.id, status: task.status.rawValue)
        } catch {
            print("[TASK] Failed to sync task status: \(error)")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
