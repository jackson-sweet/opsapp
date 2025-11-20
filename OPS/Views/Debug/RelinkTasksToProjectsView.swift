//
//  RelinkTasksToProjectsView.swift
//  OPS
//
//  Developer tool to re-link tasks to their parent projects
//  Fixes duplicates and missing references
//

import SwiftUI
import SwiftData

struct RelinkTasksToProjectsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    @State private var isProcessing = false
    @State private var progressMessage = ""
    @State private var logs: [LogEntry] = []
    @State private var stats = RelinkStats()

    struct LogEntry: Identifiable {
        let id = UUID()
        let message: String
        let type: LogType
        let timestamp = Date()

        enum LogType {
            case info, success, warning, error

            var color: Color {
                switch self {
                case .info: return OPSStyle.Colors.primaryText
                case .success: return OPSStyle.Colors.successStatus
                case .warning: return OPSStyle.Colors.warningStatus
                case .error: return OPSStyle.Colors.errorStatus
                }
            }

            var icon: String {
                switch self {
                case .info: return "info.circle"
                case .success: return "checkmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .error: return "xmark.circle.fill"
                }
            }
        }
    }

    struct RelinkStats {
        var totalTasks = 0
        var tasksProcessed = 0
        var projectsUpdated = 0
        var duplicatesRemoved = 0
        var tasksLinked = 0
        var orphanedTasks = 0
        var errors = 0
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                headerView

                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        // Stats Card
                        statsCard
                            .padding(.horizontal)
                            .padding(.top)

                        // Instructions
                        if !isProcessing && logs.isEmpty {
                            instructionsCard
                                .padding(.horizontal)
                        }

                        // Logs
                        if !logs.isEmpty {
                            logsSection
                                .padding(.horizontal)
                        }

                        // Action Button
                        if !isProcessing {
                            Button(action: startRelinking) {
                                HStack {
                                    Image(systemName: "arrow.triangle.branch")
                                    Text("Start Re-linking")
                                }
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.green)
                                .cornerRadius(OPSStyle.Layout.buttonRadius)
                            }
                            .padding(.horizontal)
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                                .padding()
                        }

                        if !progressMessage.isEmpty {
                            Text(progressMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var headerView: some View {
        ZStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: OPSStyle.Icons.close)
                        .font(.system(size: 20))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()
            }

            Text("Re-link Tasks to Projects")
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("STATISTICS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatRow(label: "Total Tasks", value: "\(stats.totalTasks)")
                StatRow(label: "Processed", value: "\(stats.tasksProcessed)")
                StatRow(label: "Tasks Linked", value: "\(stats.tasksLinked)")
                StatRow(label: "Projects Updated", value: "\(stats.projectsUpdated)")
                StatRow(label: "Duplicates Removed", value: "\(stats.duplicatesRemoved)", color: OPSStyle.Colors.warningStatus)
                StatRow(label: "Orphaned", value: "\(stats.orphanedTasks)", color: OPSStyle.Colors.errorStatus)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What This Tool Does", systemImage: "info.circle.fill")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(Color.green)

            VStack(alignment: .leading, spacing: 8) {
                BulletPoint(text: "Re-links all tasks to their parent projects")
                BulletPoint(text: "Removes duplicate task references from projects")
                BulletPoint(text: "Adds missing tasks to project.tasks lists")
                BulletPoint(text: "Syncs all changes to Bubble backend")
            }

            Text("⚠️ This may take a few minutes for large datasets")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
                .padding(.top, 8)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOGS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 8) {
                ForEach(logs.reversed()) { log in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: log.type.icon)
                            .foregroundColor(log.type.color)
                            .font(.system(size: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.message)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text(formatTime(log.timestamp))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.5))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Helper Views

    struct StatRow: View {
        let label: String
        let value: String
        var color: Color = OPSStyle.Colors.primaryText

        var body: some View {
            VStack(spacing: 4) {
                Text(value)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(color)

                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }

    struct BulletPoint: View {
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundColor(Color.green)
                Text(text)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
            }
        }
    }

    // MARK: - Re-linking Logic

    private func startRelinking() {
        isProcessing = true
        logs.removeAll()
        stats = RelinkStats()

        Task {
            await performRelinking()

            await MainActor.run {
                isProcessing = false
                progressMessage = ""
            }
        }
    }

    private func performRelinking() async {
        await log("🔵 Starting task-to-project re-linking process", type: .info)

        // STEP 1: Fetch all tasks
        await updateProgress("Fetching tasks...")
        guard let allTasks = await fetchAllTasks() else {
            await log("❌ Failed to fetch tasks", type: .error)
            return
        }

        await MainActor.run {
            stats.totalTasks = allTasks.count
        }
        await log("✅ Found \(allTasks.count) tasks", type: .success)

        // STEP 2: Fetch all projects
        await updateProgress("Fetching projects...")
        guard let allProjects = await fetchAllProjects() else {
            await log("❌ Failed to fetch projects", type: .error)
            return
        }

        await log("✅ Found \(allProjects.count) projects", type: .success)

        // STEP 3: Build project dictionary for fast lookup
        let projectDict = Dictionary(uniqueKeysWithValues: allProjects.map { ($0.id, $0) })

        // STEP 4: Re-link tasks to projects
        await updateProgress("Re-linking tasks to projects...")
        await relinkTasksToProjects(tasks: allTasks, projectDict: projectDict)

        await log("✅ Re-linking complete!", type: .success)
        await updateProgress("Complete!")
    }

    private func fetchAllTasks() async -> [ProjectTask]? {
        let descriptor = FetchDescriptor<ProjectTask>()

        return await MainActor.run {
            do {
                return try modelContext.fetch(descriptor)
            } catch {
                return nil
            }
        }
    }

    private func fetchAllProjects() async -> [Project]? {
        let descriptor = FetchDescriptor<Project>()

        return await MainActor.run {
            do {
                return try modelContext.fetch(descriptor)
            } catch {
                return nil
            }
        }
    }

    private func relinkTasksToProjects(tasks: [ProjectTask], projectDict: [String: Project]) async {
        // Group tasks by project ID
        let tasksByProject = Dictionary(grouping: tasks, by: { $0.projectId })

        for (projectId, projectTasks) in tasksByProject {
            await MainActor.run {
                stats.tasksProcessed += projectTasks.count
            }

            // Find the project
            guard let project = projectDict[projectId] else {
                await log("⚠️ Orphaned tasks: \(projectTasks.count) tasks for missing project \(projectId)", type: .warning)
                await MainActor.run {
                    stats.orphanedTasks += projectTasks.count
                }
                continue
            }

            // Build the correct task list from projectTasks (tasks that have this projectId)
            // This is the TRUE relationship - these tasks point to this project
            let correctTaskIds = projectTasks.map { $0.id }

            // Remove duplicates to ensure clean list
            let uniqueTaskIds = Array(Set(correctTaskIds))
            let duplicatesRemoved = correctTaskIds.count - uniqueTaskIds.count

            if duplicatesRemoved > 0 {
                await log("🗑️ Found \(duplicatesRemoved) duplicate task ID(s) for project: \(project.title)", type: .warning)
                await MainActor.run {
                    stats.duplicatesRemoved += duplicatesRemoved
                }
            }

            await log("🔗 Updating project '\(project.title)' in Bubble with \(uniqueTaskIds.count) task(s)", type: .info)

            // Update in Bubble - ALWAYS update to ensure Bubble is in sync
            do {
                let updateData: [String: Any] = [
                    BubbleFields.Project.tasks: uniqueTaskIds
                ]

                let bodyData = try JSONSerialization.data(withJSONObject: updateData)

                let _: EmptyResponse = try await dataController.apiService.executeRequest(
                    endpoint: "api/1.1/obj/\(BubbleFields.Types.project)/\(projectId)",
                    method: "PATCH",
                    body: bodyData,
                    requiresAuth: false
                )

                await MainActor.run {
                    stats.projectsUpdated += 1
                    stats.tasksLinked += uniqueTaskIds.count
                }

                await log("✅ Updated project '\(project.title)' in Bubble with \(uniqueTaskIds.count) task(s)", type: .success)
            } catch {
                await log("❌ Failed to update project '\(project.title)': \(error.localizedDescription)", type: .error)
                await MainActor.run {
                    stats.errors += 1
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func log(_ message: String, type: LogEntry.LogType) async {
        await MainActor.run {
            logs.append(LogEntry(message: message, type: type))
            print("[RELINK_TASKS] \(message)")
        }
    }

    private func updateProgress(_ message: String) async {
        await MainActor.run {
            progressMessage = message
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    RelinkTasksToProjectsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
