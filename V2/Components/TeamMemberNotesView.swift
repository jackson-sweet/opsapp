//
//  TeamMemberNotesView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI

struct TeamMemberNotesView: View {
    let user: User
    let project: Project
    @State private var isExpanded = false
    @State private var isEditing = false
    @State private var noteText: String
    @EnvironmentObject private var dataController: DataController
    
    // Initialize with existing note content
    init(user: User, project: Project, initialNote: String = "") {
        self.user = user
        self.project = project
        self._noteText = State(initialValue: initialNote)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with user name and expand/collapse button
            HStack {
                Text("\(user.firstName)'s Notes")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            if isEditing {
                // Editable notes
                TextEditor(text: $noteText)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                HStack {
                    Spacer()
                    
                    // Cancel button
                    Button(action: {
                        isEditing = false
                        // Reset to original if we found a note
                        if let existingNote = findTeamMemberNote() {
                            noteText = existingNote.content
                        } else {
                            noteText = ""
                        }
                    }) {
                        Text("CANCEL")
                            .font(OPSStyle.Typography.smallCaption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    // Save button
                    Button(action: {
                        isEditing = false
                        saveNote()
                    }) {
                        Text("SAVE")
                            .font(OPSStyle.Typography.smallCaption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OPSStyle.Colors.secondaryAccent)
                            .foregroundColor(.white)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            } else {
                // Notes display (single line or expanded)
                if noteText.isEmpty {
                    // Empty state - only visible when expanded or when there are no notes
                    if isExpanded {
                        HStack {
                            Text("No notes added yet")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                                .padding(.vertical, 4)
                            
                            Spacer()
                            
                            Button(action: {
                                isEditing = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10))
                                    Text("ADD")
                                        .font(OPSStyle.Typography.smallCaption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(OPSStyle.Colors.secondaryAccent)
                                .foregroundColor(.white)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                        }
                    } else {
                        // Single line empty state
                        HStack {
                            Text("No notes")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                            
                            Spacer()
                            
                            Button(action: {
                                isEditing = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(OPSStyle.Colors.secondaryAccent)
                            }
                        }
                    }
                } else {
                    // Notes content
                    VStack(alignment: .leading, spacing: 6) {
                        if isExpanded {
                            // Full text
                            Text(noteText)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 2)
                            
                            // Edit button
                            HStack {
                                Spacer()
                                
                                Button(action: {
                                    isEditing = true
                                }) {
                                    Text("EDIT")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(OPSStyle.Colors.secondaryAccent)
                                        .foregroundColor(.white)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                }
                            }
                        } else {
                            // Single line with truncation
                            HStack {
                                Text(noteText)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                Spacer()
                                
                                Button(action: {
                                    isEditing = true
                                }) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 14))
                                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(OPSStyle.Colors.cardBackground.opacity(0.2))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .onAppear {
            // Load existing note if available
            if let existingNote = findTeamMemberNote() {
                noteText = existingNote.content
            }
        }
    }
    
    // Helper function to find the team member note for this user in this project
    private func findTeamMemberNote() -> TeamMemberNote? {
        guard let modelContext = dataController.modelContext else { return nil }
        
        do {
            let descriptor = FetchDescriptor<TeamMemberNote>(
                predicate: #Predicate<TeamMemberNote> { 
                    $0.projectId == project.id && $0.userId == user.id 
                }
            )
            
            let notes = try modelContext.fetch(descriptor)
            return notes.first
        } catch {
            print("Error fetching team member note: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Save or update the note
    private func saveNote() {
        guard let modelContext = dataController.modelContext else { return }
        
        // Find existing note or create a new one
        if let existingNote = findTeamMemberNote() {
            // Update existing note
            existingNote.content = noteText
            existingNote.updatedAt = Date()
            existingNote.needsSync = true
        } else if !noteText.isEmpty {
            // Create new note only if there's content
            let newNote = TeamMemberNote(
                projectId: project.id,
                userId: user.id,
                content: noteText
            )
            newNote.project = project
            newNote.user = user
            
            modelContext.insert(newNote)
        }
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Error saving team member note: \(error.localizedDescription)")
        }
    }
}