//
//  ProjectNotesView.swift
//  OPS
//
//  Per-project message board — team members post timestamped notes with @mentions.
//

import SwiftUI
import SwiftData

struct ProjectNotesView: View {
    let project: Project

    @StateObject private var viewModel: ProjectNotesViewModel
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isComposeFocused: Bool

    init(project: Project) {
        self.project = project
        self._viewModel = StateObject(wrappedValue: ProjectNotesViewModel(projectId: project.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Notes list
            notesList

            // Mention suggestions overlay
            if viewModel.showMentionPicker {
                mentionSuggestionsBar
            }

            // Compose bar
            composeBar
        }
        .background(OPSStyle.Colors.background)
        .onAppear {
            setupViewModel()
            Task {
                await viewModel.loadNotes()
            }
        }
    }

    // MARK: - Notes List

    private var notesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    if viewModel.isLoading && viewModel.notes.isEmpty {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .padding(.top, OPSStyle.Layout.spacing5)
                    } else if viewModel.notes.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.notes) { note in
                            ProjectNoteRow(
                                note: note,
                                authorName: viewModel.authorName(for: note.authorId),
                                authorAvatarURL: viewModel.authorAvatarURL(for: note.authorId),
                                isOwnNote: viewModel.isOwnNote(note),
                                teamMembers: viewModel.allTeamMembers,
                                onDelete: { deletePhoto in
                                    Task { await viewModel.deleteNote(note, deletePhoto: deletePhoto) }
                                }
                            )
                            .id(note.id)
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
            }
            .onChange(of: viewModel.notes.count) { _, _ in
                // Scroll to newest note at bottom
                if let lastNote = viewModel.notes.last {
                    withAnimation(OPSStyle.Animation.standard) {
                        proxy.scrollTo(lastNote.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.notes)
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("NO NOTES YET")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("Post a note for your team")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.top, OPSStyle.Layout.spacing5)
    }

    // MARK: - Mention Suggestions

    private var mentionSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // @All Team pill
                if viewModel.showAllTeamOption {
                    Button(action: {
                        viewModel.insertAllTeamMention()
                    }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: OPSStyle.Icons.crew)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(width: 24, height: 24)
                                .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
                                .clipShape(Circle())
                            Text("All Team")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .nestedCard()
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                ForEach(viewModel.mentionSuggestions, id: \.id) { member in
                    Button(action: {
                        viewModel.insertMention(member)
                    }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            memberAvatar(member)
                            Text(member.fullName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .nestedCard()
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing1)
        }
        .glassDense()
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ProjectNoteMentionComposerField(
                text: $viewModel.newNoteText,
                selectedRange: $viewModel.composeSelectedRange,
                mentionSpans: $viewModel.composeMentionSpans,
                isFocused: Binding(
                    get: { isComposeFocused },
                    set: { isComposeFocused = $0 }
                ),
                placeholder: "Write a note...",
                onSubmit: {
                    Task { await viewModel.postNote() }
                }
            )
                .onChange(of: viewModel.newNoteText) { _, newValue in
                    viewModel.handleMentionInput(newValue)
                }
                .onChange(of: viewModel.composeSelectedRange) { _, _ in
                    viewModel.handleMentionInput(viewModel.newNoteText)
                }

            Button(action: {
                Task { await viewModel.postNote() }
            }) {
                Image(systemName: OPSStyle.Icons.sendFill)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(
                        viewModel.newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? OPSStyle.Colors.tertiaryText
                            : OPSStyle.Colors.primaryAccent
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .glassDense()
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Helpers

    private func memberAvatar(_ member: TeamMember) -> some View {
        TeamMemberAvatar(teamMember: member, size: 24)
    }

    private func setupViewModel() {
        guard let user = dataController.currentUser,
              let companyId = user.companyId,
              let company = dataController.getCurrentUserCompany() else { return }

        viewModel.setup(
            companyId: companyId,
            currentUserId: user.id,
            teamMembers: dataController.getTeamMembers(companyId: companyId).map { TeamMember.fromUser($0) },
            modelContext: modelContext,
            dataController: dataController
        )
    }
}

// MARK: - Note Row

struct ProjectNoteRow: View {
    let note: ProjectNote
    let authorName: String
    let authorAvatarURL: String?
    let isOwnNote: Bool
    let teamMembers: [TeamMember]
    /// `deletePhoto` is true when the user chose to also remove the note's
    /// photo from the project gallery (only offered when the note has one).
    let onDelete: (_ deletePhoto: Bool) -> Void

    @State private var showDeleteConfirmation = false

    /// Photo URLs carried by this note (photoURL + attachments), used to decide
    /// whether to offer "delete note and photo."
    private var notePhotoURLs: [String] {
        var urls = note.attachments.filter { !$0.isEmpty }
        if let photo = note.photoURL, !photo.isEmpty { urls.append(photo) }
        return urls
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            // Header: avatar + name + timestamp
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Author avatar
                authorAvatarView

                VStack(alignment: .leading, spacing: 0) {
                    Text(authorName.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(formatTimestamp(note.createdAt))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if isOwnNote {
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: OPSStyle.Icons.trash)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                }
            }

            // Content with @mention highlighting
            highlightedContent(note.content)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
        .confirmationDialog(
            notePhotoURLs.isEmpty ? "Delete Note" : "Delete the photo too?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if notePhotoURLs.isEmpty {
                Button("Delete", role: .destructive) { onDelete(false) }
            } else {
                Button("Delete note and photo", role: .destructive) { onDelete(true) }
                Button("Delete note only", role: .destructive) { onDelete(false) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(notePhotoURLs.isEmpty
                 ? "This note will be permanently deleted."
                 : "This photo also shows in the project gallery.")
        }
    }

    private var authorAvatarView: some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.fillNeutral)
                .frame(width: 32, height: 32)

            Text(authorInitials)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    private var authorInitials: String {
        let parts = authorName.split(separator: " ")
        let first = parts.first?.first?.uppercased() ?? ""
        let last = parts.count > 1 ? (parts.last?.first?.uppercased() ?? "") : ""
        return "\(first)\(last)"
    }

    private func highlightedContent(_ text: String) -> some View {
        var result = Text("")
        let segments = ProjectNoteMentionParser.renderedSegments(
            in: text,
            mentionedUserIds: note.mentionedUserIds,
            teamMembers: teamMembers,
            currentUserId: note.authorId
        )
        for segment in segments {
            result = result + Text(segment.text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(segment.isMention ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)
        }
        return result
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
}
