//
//  NotesCard.swift
//  OPS
//
//  Reusable notes display/edit card - built on SectionCard base
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
        SectionCard(
            icon: OPSStyle.Icons.notes,
            title: title,
            actionIcon: isEditable ? (isEditing ? OPSStyle.Icons.complete : OPSStyle.Icons.pencilCircle) : nil,
            actionLabel: isEditable ? (isEditing ? "Done" : "Edit") : nil,
            onAction: isEditable ? toggleEdit : nil
        ) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No notes available")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .italic()
                }
            }
        }
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
