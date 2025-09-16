//
//  NotesCard.swift
//  OPS
//
//  Reusable notes display/edit card
//

import SwiftUI

struct NotesCard: View {
    let title: String
    @Binding var notes: String?
    let isEditable: Bool
    let onSave: () -> Void
    
    @State private var isEditing = false
    @State private var editedNotes: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "note.text")
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(title.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                if isEditable {
                    Button(action: toggleEdit) {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .padding(.bottom, 8)
            
            // Notes content
            if isEditing {
                // Edit mode
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $editedNotes)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .scrollContentBackground(.hidden)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(8)
                        .frame(minHeight: 100)
                    
                    HStack {
                        Button("Cancel") {
                            cancelEdit()
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        
                        Spacer()
                        
                        Button("Save") {
                            saveNotes()
                        }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            } else {
                // Display mode
                if let notes = notes, !notes.isEmpty {
                    Text(notes)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("No notes available")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .italic()
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.tertiaryText.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func toggleEdit() {
        if isEditing {
            saveNotes()
        } else {
            editedNotes = notes ?? ""
            isEditing = true
        }
    }
    
    private func saveNotes() {
        notes = editedNotes.isEmpty ? nil : editedNotes
        isEditing = false
        onSave()
    }
    
    private func cancelEdit() {
        editedNotes = notes ?? ""
        isEditing = false
    }
}