//
//  ClearDataView.swift
//  OPS
//
//  View for clearing local database data for testing
//

import SwiftUI
import SwiftData

struct ClearDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var showingConfirmation = false
    @State private var clearingData = false
    @State private var message = ""
    
    enum DataType: String, CaseIterable {
        case all = "All Data"
        case projects = "Projects"
        case tasks = "Tasks"
        case calendarEvents = "Calendar Events"
        case taskTypes = "Task Types"
        case users = "Users"
        
        var icon: String {
            switch self {
            case .all: return "trash.fill"
            case .projects: return "folder.fill"
            case .tasks: return "list.bullet"
            case .calendarEvents: return "calendar"
            case .taskTypes: return "square.grid.2x2.fill"
            case .users: return "person.2.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return OPSStyle.Colors.errorStatus
            default: return OPSStyle.Colors.warningStatus
            }
        }
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    Spacer()
                    
                    Text("Clear Local Data")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Color.clear
                        .frame(width: 20, height: 20)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Warning card
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                            
                            Text("CAUTION")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)
                            
                            Text("Clearing data will permanently remove it from your local database. This action cannot be undone. Data will need to be re-synced from the server.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        
                        // Clear options
                        VStack(spacing: 12) {
                            ForEach(DataType.allCases, id: \.self) { dataType in
                                ClearDataButton(
                                    dataType: dataType,
                                    action: {
                                        clearData(type: dataType)
                                    },
                                    isDisabled: clearingData
                                )
                            }
                        }
                        
                        // Status message
                        if !message.isEmpty {
                            Text(message)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.successStatus)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    .padding()
                }
                
                if clearingData {
                    ProgressView("Clearing data...")
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .padding()
                }
            }
        }
    }
    
    private func clearData(type: DataType) {
        clearingData = true
        message = ""
        
        Task {
            do {
                var count = 0
                
                switch type {
                case .all:
                    // Clear all data types
                    count += try clearProjects()
                    count += try clearTasks()
                    count += try clearCalendarEvents()
                    count += try clearTaskTypes()
                    count += try clearUsers()
                    
                case .projects:
                    count = try clearProjects()
                    
                case .tasks:
                    count = try clearTasks()
                    
                case .calendarEvents:
                    count = try clearCalendarEvents()
                    
                case .taskTypes:
                    count = try clearTaskTypes()
                    
                case .users:
                    count = try clearUsers()
                }
                
                try modelContext.save()
                
                await MainActor.run {
                    message = "Cleared \(count) \(type == .all ? "total items" : type.rawValue.lowercased())"
                    clearingData = false
                }
                
            } catch {
                await MainActor.run {
                    message = "Error: \(error.localizedDescription)"
                    clearingData = false
                }
            }
        }
    }
    
    private func clearProjects() throws -> Int {
        let descriptor = FetchDescriptor<Project>()
        let projects = try modelContext.fetch(descriptor)
        for project in projects {
            modelContext.delete(project)
        }
        return projects.count
    }
    
    private func clearTasks() throws -> Int {
        let descriptor = FetchDescriptor<ProjectTask>()
        let tasks = try modelContext.fetch(descriptor)
        for task in tasks {
            modelContext.delete(task)
        }
        return tasks.count
    }
    
    private func clearCalendarEvents() throws -> Int {
        let descriptor = FetchDescriptor<CalendarEvent>()
        let events = try modelContext.fetch(descriptor)
        for event in events {
            modelContext.delete(event)
        }
        return events.count
    }
    
    private func clearTaskTypes() throws -> Int {
        let descriptor = FetchDescriptor<TaskType>()
        let types = try modelContext.fetch(descriptor)
        for type in types {
            modelContext.delete(type)
        }
        return types.count
    }
    
    private func clearUsers() throws -> Int {
        let descriptor = FetchDescriptor<User>()
        let users = try modelContext.fetch(descriptor)
        // Don't delete the current user
        let currentUserId = dataController.currentUser?.id
        var count = 0
        for user in users {
            if user.id != currentUserId {
                modelContext.delete(user)
                count += 1
            }
        }
        return count
    }
}

// Clear data button component
struct ClearDataButton: View {
    let dataType: ClearDataView.DataType
    let action: () -> Void
    let isDisabled: Bool
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: dataType.icon)
                    .font(.system(size: 20))
                    .foregroundColor(dataType.color)
                    .frame(width: 30)
                
                Text("Clear \(dataType.rawValue)")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .disabled(isDisabled)
    }
}

#Preview {
    ClearDataView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}