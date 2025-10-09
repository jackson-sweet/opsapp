//
//  AddTaskSheet.swift
//  OPS
//
//  Sheet for adding new tasks to a project
//

import SwiftUI
import SwiftData

struct AddTaskSheet: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var selectedTaskType: TaskType?
    @State private var taskNotes: String = ""
    @State private var selectedTeamMembers: Set<User> = []
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Available task types from company
    private var availableTaskTypes: [TaskType] {
        // For now, return empty until we implement company task types
        return []
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Task Type Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Label("TASK TYPE", systemImage: "hammer.circle")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            if availableTaskTypes.isEmpty {
                                Text("No task types available")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                            } else {
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    ForEach(availableTaskTypes) { taskType in
                                        TaskTypeButton(
                                            taskType: taskType,
                                            isSelected: selectedTaskType?.id == taskType.id,
                                            onTap: {
                                                selectedTaskType = taskType
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Dates Section
                        VStack(alignment: .leading, spacing: 12) {
                            Label("SCHEDULE", systemImage: "calendar")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            VStack(spacing: 1) {
                                // Start Date
                                DatePicker(
                                    "Start Date",
                                    selection: $startDate,
                                    displayedComponents: [.date]
                                )
                                .datePickerStyle(.compact)
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                
                                // End Date
                                DatePicker(
                                    "End Date",
                                    selection: $endDate,
                                    in: startDate...,
                                    displayedComponents: [.date]
                                )
                                .datePickerStyle(.compact)
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                            }
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        
                        // Team Members Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Label("TEAM MEMBERS", systemImage: "person.2")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(project.teamMembers) { member in
                                        TeamMemberSelectionChip(
                                            member: member,
                                            isSelected: selectedTeamMembers.contains(member),
                                            onTap: {
                                                if selectedTeamMembers.contains(member) {
                                                    selectedTeamMembers.remove(member)
                                                } else {
                                                    selectedTeamMembers.insert(member)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        
                        // Notes Section
                        VStack(alignment: .leading, spacing: 12) {
                            Label("NOTES", systemImage: "note.text")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            TextEditor(text: $taskNotes)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .frame(minHeight: 100)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    .padding()
                }
                
                if isLoading {
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Add Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        createTask()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(selectedTaskType == nil || isLoading)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func createTask() {
        guard let taskType = selectedTaskType else { return }
        // For now, use project's company ID
        let companyId = project.companyId
        
        isLoading = true
        
        Task {
            do {
                print("[TASK_CREATE] Creating task in Bubble...")

                // Create the task locally first with temp ID
                let tempTask = ProjectTask(
                    id: UUID().uuidString,
                    projectId: project.id,
                    taskTypeId: taskType.id,
                    companyId: companyId,
                    status: .scheduled,
                    taskColor: taskType.color
                )

                tempTask.taskNotes = taskNotes.isEmpty ? nil : taskNotes
                tempTask.setTeamMemberIds(selectedTeamMembers.map { $0.id })

                // Create in Bubble API first
                let createdTask = try await dataController.apiService.createTask(
                    TaskDTO.from(tempTask)
                )
                print("[TASK_CREATE] ✅ Task created in Bubble with ID: \(createdTask.id)")

                // Update task with Bubble ID
                tempTask.id = createdTask.id
                tempTask.needsSync = false
                tempTask.lastSyncedAt = Date()

                // Create calendar event for the task
                let calendarEvent = CalendarEvent(
                    id: UUID().uuidString,
                    projectId: project.id,
                    companyId: companyId,
                    title: taskType.display,
                    startDate: startDate,
                    endDate: endDate,
                    color: taskType.color,
                    type: .task
                )

                calendarEvent.taskId = tempTask.id
                calendarEvent.setTeamMemberIds(selectedTeamMembers.map { $0.id })

                // Link task and calendar event
                tempTask.calendarEventId = calendarEvent.id
                tempTask.calendarEvent = calendarEvent
                calendarEvent.task = tempTask

                // Add to project
                project.tasks.append(tempTask)

                // Save to database
                dataController.modelContext?.insert(tempTask)
                dataController.modelContext?.insert(calendarEvent)

                // Calendar event will sync later
                calendarEvent.needsSync = true

                try dataController.modelContext?.save()
                
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to create task: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// Task type selection button
struct TaskTypeButton: View {
    let taskType: TaskType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: taskType.icon ?? "hammer.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                Text(taskType.display)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(isSelected ? .white : OPSStyle.Colors.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(isSelected ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Team member selection chip
struct TeamMemberSelectionChip: View {
    let member: User
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Simple circle with initials
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: 28, height: 28)
                    
                    Text(String(member.firstName.prefix(1)) + String(member.lastName.prefix(1)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(member.firstName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(isSelected ? .white : OPSStyle.Colors.secondaryText)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    AddTaskSheet(project: Project(
        id: "1",
        title: "Sample Project",
        status: .inProgress
    ))
    .environmentObject(DataController())
    .preferredColorScheme(.dark)
}