//
//  JobBoardAnalyticsView.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//

import SwiftUI
import SwiftData
import Charts

struct JobBoardAnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Query private var allProjects: [Project]
    @Query private var allTasks: [ProjectTask]
    @Query private var allClients: [Client]

    @State private var selectedTimeframe: TimeFrame = .month
    @State private var selectedMetric: MetricType = .projects

    enum TimeFrame: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case quarter = "Quarter"
        case year = "Year"
    }

    enum MetricType: String, CaseIterable {
        case projects = "Projects"
        case tasks = "Tasks"
        case revenue = "Revenue"
        case team = "Team"
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // Time Frame Selector
                        TimeFrameSelector(selectedTimeframe: $selectedTimeframe)

                        // Key Metrics
                        KeyMetricsGrid()

                        // Project Status Distribution
                        ProjectStatusChart()

                        // Task Completion Trend
                        TaskCompletionTrend(timeframe: selectedTimeframe)

                        // Client Distribution
                        ClientDistributionCard()

                        // Team Performance
                        TeamPerformanceCard()

                        // Revenue Analysis (Placeholder)
                        RevenueAnalysisCard()
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("ANALYTICS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
}

// MARK: - Time Frame Selector
struct TimeFrameSelector: View {
    @Binding var selectedTimeframe: JobBoardAnalyticsView.TimeFrame

    var body: some View {
        HStack(spacing: 0) {
            ForEach(JobBoardAnalyticsView.TimeFrame.allCases, id: \.self) { timeframe in
                Button(action: { selectedTimeframe = timeframe }) {
                    Text(timeframe.rawValue.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(
                            selectedTimeframe == timeframe
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedTimeframe == timeframe
                                ? OPSStyle.Colors.primaryAccent.opacity(0.1)
                                : Color.clear
                        )
                }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Key Metrics Grid
struct KeyMetricsGrid: View {
    @Query private var projects: [Project]
    @Query private var tasks: [ProjectTask]

    private var activeProjects: Int {
        projects.filter {
            $0.status == .inProgress || $0.status == .accepted
        }.count
    }

    private var completedProjects: Int {
        projects.filter { $0.status == .completed }.count
    }

    private var totalTasks: Int {
        tasks.count
    }

    private var completedTasks: Int {
        tasks.filter { $0.status == .completed }.count
    }

    private var taskCompletionRate: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks) * 100
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            MetricCard(
                title: "ACTIVE",
                value: "\(activeProjects)",
                subtitle: "Projects",
                color: .green
            )

            MetricCard(
                title: "COMPLETED",
                value: "\(completedProjects)",
                subtitle: "This Month",
                color: .blue
            )

            MetricCard(
                title: "TASKS",
                value: "\(totalTasks)",
                subtitle: "Total",
                color: .orange
            )

            MetricCard(
                title: "COMPLETION",
                value: "\(Int(taskCompletionRate))%",
                subtitle: "Task Rate",
                color: OPSStyle.Colors.primaryAccent
            )
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Text(value)
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(subtitle)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Project Status Chart
struct ProjectStatusChart: View {
    @Query private var projects: [Project]

    private var statusData: [(status: Status, count: Int)] {
        Status.allCases.compactMap { status in
            let count = projects.filter { $0.status == status }.count
            return count > 0 ? (status, count) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROJECT STATUS DISTRIBUTION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if statusData.isEmpty {
                Text("No project data available")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(statusData, id: \.status) { item in
                        StatusBar(
                            status: item.status,
                            count: item.count,
                            total: projects.count
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct StatusBar: View {
    let status: Status
    let count: Int
    let total: Int

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.displayName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Text("\(count)")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.05))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(status.color)
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Task Completion Trend
struct TaskCompletionTrend: View {
    @Query private var tasks: [ProjectTask]
    let timeframe: JobBoardAnalyticsView.TimeFrame

    private var trendData: [(date: String, completed: Int, booked: Int)] {
        // This would calculate actual trend data based on timeframe
        // For now, returning mock data
        switch timeframe {
        case .week:
            return [
                ("Mon", 5, 8),
                ("Tue", 7, 9),
                ("Wed", 6, 7),
                ("Thu", 8, 10),
                ("Fri", 9, 11),
                ("Sat", 3, 4),
                ("Sun", 2, 2)
            ]
        case .month:
            return [
                ("Week 1", 25, 35),
                ("Week 2", 30, 38),
                ("Week 3", 28, 32),
                ("Week 4", 35, 40)
            ]
        default:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TASK COMPLETION TREND")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if trendData.isEmpty {
                Text("No trend data available")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 16) {
                    // Legend
                    HStack(spacing: 20) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(OPSStyle.Colors.successStatus)
                                .frame(width: 8, height: 8)
                            Text("Completed")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        HStack(spacing: 4) {
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(width: 8, height: 8)
                            Text("Booked")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }

                    // Simple bar chart
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(trendData, id: \.date) { item in
                            VStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    BarView(
                                        value: Double(item.completed),
                                        maxValue: 15,
                                        color: OPSStyle.Colors.successStatus
                                    )

                                    BarView(
                                        value: Double(item.booked),
                                        maxValue: 15,
                                        color: OPSStyle.Colors.primaryAccent.opacity(0.5)
                                    )
                                }

                                Text(item.date)
                                    .font(.system(size: 8))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .rotationEffect(.degrees(-45))
                            }
                        }
                    }
                    .frame(height: 100)
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct BarView: View {
    let value: Double
    let maxValue: Double
    let color: Color

    private var heightPercentage: Double {
        guard maxValue > 0 else { return 0 }
        return min(value / maxValue, 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(height: geometry.size.height * heightPercentage)
            }
        }
    }
}

// MARK: - Client Distribution Card
struct ClientDistributionCard: View {
    @Query private var clients: [Client]
    @Query private var projects: [Project]

    private var topClients: [(client: Client, projectCount: Int)] {
        clients.compactMap { client in
            let count = client.projects.count
            return count > 0 ? (client, count) : nil
        }
        .sorted { $0.projectCount > $1.projectCount }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOP CLIENTS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if topClients.isEmpty {
                Text("No client data available")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(topClients, id: \.client.id) { item in
                        HStack {
                            Text(item.client.name)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)

                            Spacer()

                            Text("\(item.projectCount) project\(item.projectCount == 1 ? "" : "s")")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        if item.client != topClients.last?.client {
                            Divider()
                                .background(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Team Performance Card
struct TeamPerformanceCard: View {
    @Query private var teamMembers: [TeamMember]
    @Query private var tasks: [ProjectTask]

    private var topPerformers: [(member: TeamMember, completedTasks: Int)] {
        teamMembers.compactMap { member in
            let completedCount = tasks.filter { task in
                task.teamMembers.contains(where: { $0.id == member.id }) && task.status == .completed
            }.count
            return completedCount > 0 ? (member, completedCount) : nil
        }
        .sorted { $0.completedTasks > $1.completedTasks }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEAM PERFORMANCE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if topPerformers.isEmpty {
                Text("No performance data available")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(topPerformers, id: \.member.id) { item in
                        HStack {
                            // Avatar placeholder
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(item.member.fullName.prefix(1))
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                )

                            Text(item.member.fullName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Spacer()

                            Text("\(item.completedTasks) completed")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.successStatus)
                        }

                        if item.member.id != topPerformers.last?.member.id {
                            Divider()
                                .background(Color.white.opacity(0.05))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Revenue Analysis Card (Placeholder)
struct RevenueAnalysisCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("REVENUE ANALYSIS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 12) {
                HStack {
                    Text("Monthly Target")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    Text("$50,000")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                HStack {
                    Text("Current Progress")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    Text("$32,450")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.successStatus)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(OPSStyle.Colors.successStatus)
                            .frame(width: geometry.size.width * 0.65)
                    }
                }
                .frame(height: 8)

                Text("65% of monthly target")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}