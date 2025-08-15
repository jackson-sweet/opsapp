//
//  DeveloperDashboard.swift
//  OPS
//
//  Central dashboard for all developer tools and debugging features
//

import SwiftUI
import SwiftData

struct DeveloperDashboard: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @State private var selectedTool: DeveloperTool? = nil
    
    enum DeveloperTool: String, CaseIterable, Identifiable {
        var id: String { self.rawValue }
        
        case taskTest = "Task Test"
        case taskList = "Task List"
        case calendarEvents = "Calendar Events"
        case apiCalls = "API Calls"
        case clearData = "Clear Data"
        case taskTypes = "Task Types"
        
        var icon: String {
            switch self {
            case .taskTest: return "hammer.circle"
            case .taskList: return "list.bullet.rectangle"
            case .calendarEvents: return "calendar.badge.clock"
            case .apiCalls: return "network"
            case .clearData: return "trash.circle"
            case .taskTypes: return "square.grid.2x2"
            }
        }
        
        var description: String {
            switch self {
            case .taskTest: return "Test task-based scheduling models"
            case .taskList: return "View all tasks with full details"
            case .calendarEvents: return "View and sync calendar events"
            case .apiCalls: return "Test API endpoints and responses"
            case .clearData: return "Clear local database data"
            case .taskTypes: return "Manage task type definitions"
            }
        }
        
        var color: Color {
            switch self {
            case .taskTest: return OPSStyle.Colors.primaryAccent
            case .taskList: return OPSStyle.Colors.successStatus
            case .calendarEvents: return OPSStyle.Colors.warningStatus
            case .apiCalls: return Color.purple
            case .clearData: return OPSStyle.Colors.errorStatus
            case .taskTypes: return Color.orange
            }
        }
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                ZStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        
                        Spacer()
                        
                        // Exit Developer Mode button
                        Button {
                            exitDeveloperMode()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                Text("Exit Dev Mode")
                                    .font(OPSStyle.Typography.caption)
                            }
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(OPSStyle.Colors.errorStatus, lineWidth: 1)
                            )
                        }
                    }
                    
                    Text("Developer Tools")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                
                // Tools Grid
                ScrollView {
                    VStack(spacing: 20) {
                        // Quick Info Card
                        InfoCard()
                            .padding(.horizontal)
                            .padding(.top)
                        
                        // Tool Categories
                        VStack(alignment: .leading, spacing: 16) {
                            // Data Management Tools
                            SectionHeader(title: "DATA MANAGEMENT")
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ToolCard(tool: .taskList) {
                                    selectedTool = .taskList
                                }
                                
                                ToolCard(tool: .calendarEvents) {
                                    selectedTool = .calendarEvents
                                }
                                
                                ToolCard(tool: .taskTypes) {
                                    selectedTool = .taskTypes
                                }
                                
                                ToolCard(tool: .clearData) {
                                    selectedTool = .clearData
                                }
                            }
                            
                            // Testing Tools
                            SectionHeader(title: "TESTING & DEBUG")
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ToolCard(tool: .taskTest) {
                                    selectedTool = .taskTest
                                }
                                
                                ToolCard(tool: .apiCalls) {
                                    selectedTool = .apiCalls
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Database Stats
                        DatabaseStatsCard()
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedTool) { tool in
            NavigationStack {
                switch tool {
                case .taskTest:
                    TaskTestView()
                        .environmentObject(dataController)
                case .taskList:
                    TaskListDebugView()
                        .environmentObject(dataController)
                case .calendarEvents:
                    CalendarEventsDebugView()
                        .environmentObject(dataController)
                case .apiCalls:
                    APICallsDebugView()
                        .environmentObject(dataController)
                case .clearData:
                    ClearDataView()
                        .environmentObject(dataController)
                case .taskTypes:
                    TaskTypesDebugView()
                        .environmentObject(dataController)
                }
            }
        }
    }
    
    private func exitDeveloperMode() {
        UserDefaults.standard.set(false, forKey: "developerModeEnabled")
        UserDefaults.standard.synchronize()
        dismiss()
    }
}

// Section header component
struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
    }
}

// Tool card component
struct ToolCard: View {
    let tool: DeveloperDashboard.DeveloperTool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tool.color.opacity(0.2))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: tool.icon)
                        .font(.system(size: 24))
                        .foregroundColor(tool.color)
                }
                
                Text(tool.rawValue)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                Text(tool.description)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Info card showing current state
struct InfoCard: View {
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Label("Development Mode Active", systemImage: "hammer.circle.fill")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.successStatus)
                
                HStack(spacing: 16) {
                    if let user = dataController.currentUser {
                        Label(user.fullName, systemImage: "person.fill")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    Label(dataController.isConnected ? "Online" : "Offline", 
                          systemImage: dataController.isConnected ? "wifi" : "wifi.slash")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(dataController.isConnected ? 
                            OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// Database stats card
struct DatabaseStatsCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var projectCount = 0
    @State private var taskCount = 0
    @State private var eventCount = 0
    @State private var userCount = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATABASE STATS")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatItem(label: "Projects", value: "\(projectCount)")
                StatItem(label: "Tasks", value: "\(taskCount)")
                StatItem(label: "Events", value: "\(eventCount)")
                StatItem(label: "Users", value: "\(userCount)")
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .onAppear {
            fetchCounts()
        }
    }
    
    private func fetchCounts() {
        do {
            projectCount = try modelContext.fetchCount(FetchDescriptor<Project>())
            taskCount = try modelContext.fetchCount(FetchDescriptor<ProjectTask>())
            eventCount = try modelContext.fetchCount(FetchDescriptor<CalendarEvent>())
            userCount = try modelContext.fetchCount(FetchDescriptor<User>())
        } catch {
            print("Error fetching counts: \(error)")
        }
    }
}

// Stat item component
struct StatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)
            
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DeveloperDashboard()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}