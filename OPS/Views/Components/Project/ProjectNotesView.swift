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
                                // Bug ab12c273 — pass the canonical mention strings
                                // ("All Team" + every team member's full name) so the
                                // highlighter spans the full "@First Last" range
                                // instead of stopping after the first word.
                                mentionNames: viewModel.mentionNames,
                                onDelete: {
                                    Task { await viewModel.deleteNote(note) }
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
            Image(OPSStyle.Icons.notes)
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
                            Image(OPSStyle.Icons.crew)
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
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
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
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing1)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            TextField("Write a note...", text: $viewModel.newNoteText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .focused($isComposeFocused)
                .onChange(of: viewModel.newNoteText) { _, newValue in
                    viewModel.handleMentionInput(newValue)
                }
                .onSubmit {
                    Task { await viewModel.postNote() }
                }

            Button(action: {
                Task { await viewModel.postNote() }
            }) {
                Image(OPSStyle.Icons.sendFill)
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
        .background(OPSStyle.Colors.cardBackgroundDark)
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
    /// Bug ab12c273 — full set of valid mention strings (every team
    /// member's full name plus "All Team"). Lets the highlighter span the
    /// entire mention even when it contains spaces. Without it the parser
    /// only highlighted the first whitespace-delimited token after `@` so
    /// "@Jason Sweet" rendered as "@Jason" + plain "Sweet".
    let mentionNames: [String]
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

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
                        Image(OPSStyle.Icons.trash)
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
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .confirmationDialog("Delete Note", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This note will be permanently deleted.")
        }
    }

    private var authorAvatarView: some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.subtleBackground)
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

    /// Bug ab12c273 — render `@Mention` spans in the accent colour with
    /// the rest of the body in the primary colour. Mentions can contain
    /// spaces (e.g. "@Harrison Sweet", "@All Team"), so the previous
    /// space-counting parser stopped after the first word and bled the
    /// last name out of the highlighted range. Mirrors the team-aware
    /// algorithm in ActivityEntryView: scan for `@`, look ahead for the
    /// longest match against `mentionNames` (sorted longest-first so
    /// "All Team" wins over "All"), and highlight that whole span.
    /// Unrecognised `@<token>` strings still highlight the single token
    /// as a graceful fallback for stale references.
    private func highlightedContent(_ text: String) -> some View {
        let sortedNames = mentionNames.sorted { $0.count > $1.count }
        var segments: [(text: String, isMention: Bool)] = []
        var buffer = ""
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "@" {
                if !buffer.isEmpty {
                    segments.append((buffer, false))
                    buffer = ""
                }
                let afterAt = text.index(after: i)
                let remainder = text[afterAt...]

                if let matched = sortedNames.first(where: { remainder.hasPrefix($0) }) {
                    segments.append(("@" + matched, true))
                    i = text.index(afterAt, offsetBy: matched.count)
                    continue
                }

                let tokenEnd = remainder.firstIndex(where: { $0 == " " || $0 == "\n" }) ?? text.endIndex
                let token = String(remainder[..<tokenEnd])
                if !token.isEmpty {
                    segments.append(("@" + token, true))
                    i = tokenEnd
                    continue
                }

                buffer.append("@")
                i = afterAt
            } else {
                buffer.append(text[i])
                i = text.index(after: i)
            }
        }

        if !buffer.isEmpty {
            segments.append((buffer, false))
        }

        var result = Text("")
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
