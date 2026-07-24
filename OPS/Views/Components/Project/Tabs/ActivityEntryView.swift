//
//  ActivityEntryView.swift
//  OPS
//
//  Individual note/photo entry card for the Activity tab.
//  Shows author avatar, name, relative timestamp, content, and photo grid.
//

import SwiftUI

struct ActivityEntryView: View {
    let note: ProjectNote
    let authorName: String
    let teamMember: TeamMember?
    let isOwnNote: Bool
    /// Bug 162364de — full TeamMember roster passed in so the edit field
    /// can fire the same `@`-mention picker as the compose bar. Without
    /// it the edit flow had no source of truth for avatars + ids.
    let allTeamMembers: [TeamMember]
    /// `deletePhoto` is true when the user chose to also remove the note's
    /// photo from the project gallery (only offered when the note has one).
    let onDelete: (_ deletePhoto: Bool) -> Void
    let onEdit: (String, [ProjectNoteMentionSpan]) async -> Bool
    let onPhotoTap: (([String], Int) -> Void)?

    @EnvironmentObject private var dataController: DataController

    @State private var isEditing = false
    @State private var editText = ""
    @State private var editSelectedRange = NSRange(location: 0, length: 0)
    @State private var editMentionSpans: [ProjectNoteMentionSpan] = []
    @State private var isSavingEdit = false
    @State private var showDeleteConfirmation = false

    // Bug 162364de — local picker state for the edit field. Scoped here
    // so each entry card's edit session has its own picker without
    // colliding with the compose-bar picker further down the screen.
    @State private var editMentionSuggestions: [TeamMember] = []
    @State private var editShowAllTeam = false
    @State private var editShowMentionPicker = false

    // Bug f6cd3c43 — tapping an `@mention` in the rendered note opens
    // that teammate's contact sheet inline. Kept local to the entry
    // card so we don't have to thread a callback through ActivityTabView
    // and ProjectDetailsView (the latter currently has parallel WIP).
    @State private var contactSheetMember: User? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: avatar + name + timestamp + menu
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Avatar
                if let member = teamMember {
                    TeamMemberAvatar(teamMember: member, size: 28)
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.surfaceInput)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(authorName.prefix(1)).uppercased())
                                .font(OPSStyle.Typography.status)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        )
                }

                // Name + timestamp inline (one consistent position across every
                // feed card), with an "added a photo" subtitle on photo-only
                // posts so a comment-less photo still reads as an action.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(authorName)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text(relativeTimestamp)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    if isPhotoComment {
                        // Bug e1f073ed — a note tied to a photo reads as a
                        // comment on it, mirroring the annotation card's
                        // "marked up a photo" subtitle grammar.
                        Text("commented on a photo")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else if note.content.isEmpty && !notePhotoURLs.isEmpty {
                        Text(photoAddedSubtitle)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                Spacer()

                // Edit/Delete menu for own notes
                if isOwnNote {
                    Menu {
                        Button(action: {
                            let draft = ProjectNoteMentionParser.editableDraft(
                                in: note.content,
                                mentionedUserIds: note.mentionedUserIds,
                                teamMembers: mentionIdentityMembers,
                                currentUserId: note.authorId
                            )
                            editText = draft.text
                            editSelectedRange = NSRange(
                                location: (draft.text as NSString).length,
                                length: 0
                            )
                            editMentionSpans = draft.identitySpans
                            isEditing = true
                        }) {
                            Label("Edit", systemImage: OPSStyle.Icons.pencil)
                        }
                        Button(role: .destructive, action: {
                            showDeleteConfirmation = true
                        }) {
                            Label("Delete", systemImage: OPSStyle.Icons.trash)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 32, height: 32)
                    }
                }
            }

            // Content
            if isEditing {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    ProjectNoteMentionEditingField(
                        text: $editText,
                        selectedRange: $editSelectedRange,
                        mentionSpans: $editMentionSpans,
                        placeholder: "Edit note..."
                    )
                    .disabled(isSavingEdit)
                    .onChange(of: editText) { _, newValue in
                        updateEditMentionState(
                            for: newValue,
                            selectedRange: editSelectedRange
                        )
                    }
                    .onChange(of: editSelectedRange) { _, newValue in
                        updateEditMentionState(
                            for: editText,
                            selectedRange: newValue
                        )
                    }

                    if editShowMentionPicker {
                        editMentionPicker
                    }

                    HStack {
                        Button("Cancel") {
                            isEditing = false
                            editMentionSpans = []
                            clearEditMentionState()
                        }
                        .disabled(isSavingEdit)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        Button("Save") {
                            Task { @MainActor in
                                guard !isSavingEdit else { return }
                                isSavingEdit = true
                                let didQueueSave = await onEdit(
                                    editText,
                                    editMentionSpans
                                )
                                isSavingEdit = false
                                guard didQueueSave else { return }
                                isEditing = false
                                editMentionSpans = []
                                clearEditMentionState()
                            }
                        }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .disabled(isSavingEdit)
                    }
                }
            } else if isPhotoComment, let photo = note.photoURL, !photo.isEmpty {
                // Photo comment — thumbnail beside the comment text, tappable
                // into the viewer (same grammar as the annotation card).
                HStack(alignment: .top, spacing: 10) {
                    Button(action: { onPhotoTap?([photo], 0) }) {
                        PhotoThumbnail(url: photo, project: nil)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    if !note.content.isEmpty {
                        mentionHighlightedText(note.content)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            } else {
                if !note.content.isEmpty {
                    // Render with @mention highlighting
                    mentionHighlightedText(note.content)
                }

                // Photo attachments
                let allPhotos = notePhotoURLs
                if !allPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(Array(allPhotos.enumerated()), id: \.offset) { index, url in
                                Button(action: {
                                    onPhotoTap?(allPhotos, index)
                                }) {
                                    PhotoThumbnail(url: url, project: nil)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
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
                 ? "Are you sure you want to delete this note?"
                 : "This photo also shows in the project gallery.")
        }
        // Bug f6cd3c43 — opens when the user taps an `@member` span.
        .sheet(item: $contactSheetMember) { member in
            ContactDetailView(user: member)
                .environmentObject(dataController)
        }
    }

    // MARK: - Helpers

    /// Collect all photo URLs from photoURL + attachments
    private var notePhotoURLs: [String] {
        var urls: [String] = []
        if let photo = note.photoURL, !photo.isEmpty {
            urls.append(photo)
        }
        urls.append(contentsOf: note.attachments.filter { !$0.isEmpty })
        return urls
    }

    /// A note tied to a specific photo (posted from the photo viewer's comment
    /// composer) reads as a comment on that photo.
    private var isPhotoComment: Bool {
        if let photo = note.photoURL { return !photo.isEmpty }
        return false
    }

    /// Subtitle for a comment-less photo post — "added a photo" / "added N photos".
    private var photoAddedSubtitle: String {
        notePhotoURLs.count == 1 ? "added a photo" : "added \(notePhotoURLs.count) photos"
    }

    private var relativeTimestamp: String {
        let interval = Date().timeIntervalSince(note.createdAt)

        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: note.createdAt)
    }

    // MARK: - Edit-mode mention picker (bug 162364de)

    /// Picker bar rendered between the edit TextField and its Save/Cancel
    /// row. Mirrors the compose-bar picker visually so the two flows feel
    /// like the same control.
    @ViewBuilder
    private var editMentionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if editShowAllTeam {
                    Button(action: insertEditAllTeamMention) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: OPSStyle.Icons.crew)
                                .font(.system(size: 12))
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
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                ForEach(editMentionSuggestions, id: \.id) { member in
                    Button(action: { insertEditMention(member) }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            TeamMemberAvatar(teamMember: member, size: 24)
                            Text(member.fullName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func updateEditMentionState(
        for text: String,
        selectedRange: NSRange
    ) {
        guard let match = ProjectNoteMentionEditor.match(
            in: text,
            selectedRange: selectedRange,
            members: allTeamMembers.filter {
                $0.id.lowercased() != note.authorId.lowercased()
            }
        ) else {
            clearEditMentionState()
            return
        }
        editMentionSuggestions = match.suggestions
        editShowAllTeam = match.showAllTeam
        editShowMentionPicker = !match.suggestions.isEmpty || match.showAllTeam
    }

    private func clearEditMentionState() {
        editShowMentionPicker = false
        editShowAllTeam = false
        editMentionSuggestions = []
    }

    /// The active picker remains limited to the current roster, while retained
    /// note identities may resolve through a locally-known former/inactive
    /// teammate. This prevents an unrelated text edit from silently revoking a
    /// still-authoritative mention when the active roster snapshot is stale.
    private var mentionIdentityMembers: [TeamMember] {
        var membersById = Dictionary(
            allTeamMembers.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for id in note.mentionedUserIds {
            let canonicalId = id.lowercased()
            guard membersById[canonicalId] == nil,
                  let user = dataController.getUser(id: id) else {
                continue
            }
            membersById[canonicalId] = TeamMember.fromUser(user)
        }
        return Array(membersById.values)
    }

    private func insertEditMention(_ member: TeamMember) {
        guard let replacement = ProjectNoteMentionEditor
            .replacingActiveMention(
                with: member.fullName,
                in: editText,
                selectedRange: editSelectedRange,
                mentionSpans: editMentionSpans,
                recipient: .user(id: member.id),
                visibleMentionText:
                    ProjectNoteMentionParser.visibleMentionText(for: member)
            ) else {
            clearEditMentionState()
            return
        }
        editText = replacement.text
        editSelectedRange = replacement.selectedRange
        editMentionSpans = replacement.mentionSpans
        clearEditMentionState()
    }

    private func insertEditAllTeamMention() {
        guard let replacement = ProjectNoteMentionEditor
            .replacingActiveMention(
                with: "All Team",
                in: editText,
                selectedRange: editSelectedRange,
                mentionSpans: editMentionSpans,
                recipient: .allTeam
            ) else {
            clearEditMentionState()
            return
        }
        editText = replacement.text
        editSelectedRange = replacement.selectedRange
        editMentionSpans = replacement.mentionSpans
        clearEditMentionState()
    }

    /// Canonical markup is humanized before rendering while its authoritative
    /// recipient remains attached to the attributed span. Duplicate visible
    /// names therefore open the selected teammate, and the reserved group
    /// remains highlighted but inert.
    private func mentionHighlightedText(_ text: String) -> some View {
        Text(
            mentionAttributedText(
                ProjectNoteMentionParser.renderedSegments(
                    in: text,
                    mentionedUserIds: note.mentionedUserIds,
                    teamMembers: mentionIdentityMembers,
                    currentUserId: note.authorId
                )
            )
        )
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "opsmention", let memberId = url.host else {
                    return .systemAction
                }
                openContactSheet(forMemberId: memberId)
                return .handled
            })
    }

    private func mentionAttributedText(
        _ segments: [ProjectNoteMentionRenderSegment]
    ) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            var span = AttributedString(segment.text)
            span.font = OPSStyle.Typography.body
            span.foregroundColor = segment.isMention
                ? OPSStyle.Colors.primaryAccent
                : OPSStyle.Colors.primaryText
            if case .some(.user(let memberId)) = segment.recipient,
               let url = URL(string: "opsmention://\(memberId)") {
                span.link = url
            }
            result.append(span)
        }
        return result
    }

    /// Resolve the tapped mention to a `User` via DataController and
    /// surface its contact sheet. Silently no-ops when the teammate is
    /// no longer on the company roster (e.g. removed since the note was
    /// posted) — same graceful-degradation policy as the renderer.
    private func openContactSheet(forMemberId memberId: String) {
        guard let companyId = dataController.currentUser?.companyId else { return }
        let users = dataController.getTeamMembers(companyId: companyId)
        if let user = users.first(where: {
            $0.id.caseInsensitiveCompare(memberId) == .orderedSame
        }) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            contactSheetMember = user
        }
    }
}
