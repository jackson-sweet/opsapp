//
//  NotesDisplayField.swift
//  OPS
//
//  Reusable notes display component for project and task details views.
//  Shows first 5 lines when collapsed with expand/collapse functionality.
//

import SwiftUI

/// Reusable notes display field with expand/collapse functionality
///
/// Features:
/// - Shows "No notes" in grey when empty
/// - Shows first 5 lines when collapsed
/// - Gradient fade with "Show more..." when content is truncated
/// - Full content with edit button when expanded
/// - Optional edit functionality
///
/// Usage:
/// ```swift
/// NotesDisplayField(
///     title: "TEAM NOTES",
///     notes: project.notes ?? "",
///     isExpanded: $isNotesExpanded,
///     editedNotes: $noteText,
///     canEdit: canEditProjectSettings(),
///     onSave: saveNotes
/// )
/// ```
struct NotesDisplayField: View {
    let title: String
    let notes: String
    @Binding var isExpanded: Bool
    @Binding var editedNotes: String
    let canEdit: Bool
    let onSave: () -> Void

    @State private var isEditing = false

    /// Number of lines to show when collapsed
    private let collapsedLineLimit = 5

    init(
        title: String,
        notes: String,
        isExpanded: Binding<Bool>,
        editedNotes: Binding<String>,
        canEdit: Bool = true,
        onSave: @escaping () -> Void
    ) {
        self.title = title
        self.notes = notes
        self._isExpanded = isExpanded
        self._editedNotes = editedNotes
        self.canEdit = canEdit
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title header ABOVE the card (per UI guidelines)
            Text(title.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Card container with notes content
            VStack(alignment: .leading, spacing: 0) {
                notesContent
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
            )
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }

    @ViewBuilder
    private var notesContent: some View {
        if isEditing {
            // Editing mode
            editingView
        } else if notes.isEmpty {
            // Empty state
            emptyStateView
        } else if isExpanded {
            // Expanded view
            expandedView
        } else {
            // Collapsed view with first 5 lines
            collapsedView
        }
    }

    private var emptyStateView: some View {
        HStack {
            Text("No notes")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .italic()

            Spacer()

            if canEdit {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editedNotes = ""
                        isEditing = true
                        isExpanded = true
                    }
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    private var collapsedView: some View {
        ZStack(alignment: .bottomLeading) {
            Text(notes)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(collapsedLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)

            // Gradient fade overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    OPSStyle.Colors.cardBackgroundDark.opacity(0.8),
                    OPSStyle.Colors.cardBackgroundDark
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .frame(maxWidth: .infinity)

            // Show more button and edit icon
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }) {
                    Text("Show more...")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                Spacer()

                if canEdit {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editedNotes = notes
                            isEditing = true
                            isExpanded = true
                        }
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
    }

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notes)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Edit button row
            if canEdit {
                HStack {
                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            editedNotes = notes
                            isEditing = true
                        }
                    }) {
                        Text("EDIT")
                            .font(OPSStyle.Typography.smallCaption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(OPSStyle.Colors.primaryAccent)
                            .foregroundColor(.white)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            }
        }
    }

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $editedNotes)
                .frame(minHeight: 120)
                .padding(12)
                .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.9))
                .scrollContentBackground(.hidden)

            HStack {
                Spacer()

                // Cancel button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditing = false
                        editedNotes = notes
                    }
                }) {
                    Text("CANCEL")
                        .font(OPSStyle.Typography.smallCaption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                // Save button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditing = false
                    }
                    onSave()
                }) {
                    Text("SAVE")
                        .font(OPSStyle.Typography.smallCaption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(OPSStyle.Colors.primaryAccent)
                        .foregroundColor(.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // With notes
        NotesDisplayField(
            title: "Team Notes",
            notes: "This is a sample note that demonstrates how the notes field looks with content. It can span multiple lines and will show the first 5 lines when collapsed.\n\nLine 3\nLine 4\nLine 5\nLine 6 - this should be hidden when collapsed",
            isExpanded: .constant(false),
            editedNotes: .constant(""),
            canEdit: true,
            onSave: {}
        )

        // Empty
        NotesDisplayField(
            title: "Task Notes",
            notes: "",
            isExpanded: .constant(false),
            editedNotes: .constant(""),
            canEdit: true,
            onSave: {}
        )
    }
    .padding()
    .background(OPSStyle.Colors.background)
}
