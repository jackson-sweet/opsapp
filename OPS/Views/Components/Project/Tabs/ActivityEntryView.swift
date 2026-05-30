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
    /// Bug 213bbaa4 — full set of valid mention strings (every team
    /// member's full name + the literal "All Team"). Used by the highlighter
    /// to span the entire mention even when it contains spaces. Without
    /// this the previous word-split parser only painted the leading
    /// `@<FirstWord>` blue and left the trailing word in the default
    /// foreground colour ("@Harrison" blue, "Sweet" not — same for
    /// "@All Team").
    let mentionNames: [String]
    /// Bug 162364de — full TeamMember roster passed in so the edit field
    /// can fire the same `@`-mention picker as the compose bar. Without
    /// it the edit flow had no source of truth for avatars + ids.
    let allTeamMembers: [TeamMember]
    let onDelete: () -> Void
    let onEdit: (String) -> Void
    let onPhotoTap: (([String], Int) -> Void)?

    @EnvironmentObject private var dataController: DataController

    @State private var isEditing = false
    @State private var editText = ""
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
            HStack(spacing: 8) {
                // Avatar
                if let member = teamMember {
                    TeamMemberAvatar(teamMember: member, size: 28)
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(authorName.prefix(1)).uppercased())
                                .font(OPSStyle.Typography.status)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        )
                }

                Text(authorName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(relativeTimestamp)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Spacer()

                // Edit/Delete menu for own notes
                if isOwnNote {
                    Menu {
                        Button(action: {
                            editText = note.content ?? ""
                            isEditing = true
                        }) {
                            Label("Edit", image: OPSStyle.Icons.pencil)
                        }
                        Button(role: .destructive, action: {
                            showDeleteConfirmation = true
                        }) {
                            Label("Delete", image: OPSStyle.Icons.trash)
                        }
                    } label: {
                        Image("ops.overflow")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 32, height: 32)
                    }
                }
            }

            // Content
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Edit note...", text: $editText, axis: .vertical)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                        .onChange(of: editText) { _, newValue in
                            updateEditMentionState(for: newValue)
                        }

                    if editShowMentionPicker {
                        editMentionPicker
                    }

                    HStack {
                        Button("Cancel") {
                            isEditing = false
                            clearEditMentionState()
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        Button("Save") {
                            onEdit(editText)
                            isEditing = false
                            clearEditMentionState()
                        }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            } else if !note.content.isEmpty {
                // Render with @mention highlighting
                mentionHighlightedText(note.content)
            }

            // Photo attachments
            let allPhotos = notePhotoURLs
            if !allPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .confirmationDialog("Delete Note", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this note?")
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
                            Image(OPSStyle.Icons.crew)
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
                        .background(OPSStyle.Colors.cardBackground)
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
            .padding(.vertical, 2)
        }
    }

    private func updateEditMentionState(for text: String) {
        guard let match = ProjectNotesViewModel.mentionMatch(for: text, in: allTeamMembers) else {
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

    private func insertEditMention(_ member: TeamMember) {
        editText = ProjectNotesViewModel.textInserting(mention: member.fullName, into: editText)
        clearEditMentionState()
    }

    private func insertEditAllTeamMention() {
        editText = ProjectNotesViewModel.textInserting(mention: "All Team", into: editText)
        clearEditMentionState()
    }

    /// Bug 213bbaa4 + f6cd3c43 — render `@Mention` spans in the accent
    /// colour and (when the matched span is a real teammate) attach a
    /// link so tapping the mention opens that teammate's contact sheet.
    /// Mentions can contain spaces (e.g. "@Harrison Sweet", "@All Team"),
    /// so a naive split-on-space paints only the first word. We scan
    /// for `@`, look ahead for the longest match against `mentionNames`
    /// (sorted longest-first so "All Team" wins over "All"), and
    /// highlight the whole span. Unrecognised `@<token>` strings still
    /// highlight as a graceful fallback — preserves intent when the
    /// mention's referent has been removed from the team or when the
    /// post comes from another platform.
    private func mentionHighlightedText(_ text: String) -> some View {
        Text(mentionAttributedText(text))
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "opsmention", let memberId = url.host else {
                    return .systemAction
                }
                openContactSheet(forMemberId: memberId)
                return .handled
            })
    }

    private func mentionAttributedText(_ text: String) -> AttributedString {
        // Sort longest-first so "All Team" wins the prefix match against
        // "All" if both happen to be valid.
        let sortedNames = mentionNames.sorted { $0.count > $1.count }

        var result = AttributedString()
        var buffer = ""
        var i = text.startIndex

        func flushPlainBuffer() {
            guard !buffer.isEmpty else { return }
            var plain = AttributedString(buffer)
            plain.font = OPSStyle.Typography.body
            plain.foregroundColor = OPSStyle.Colors.primaryText
            result.append(plain)
            buffer = ""
        }

        while i < text.endIndex {
            if text[i] == "@" {
                flushPlainBuffer()
                let afterAt = text.index(after: i)
                let remainder = text[afterAt...]

                if let matched = sortedNames.first(where: { remainder.hasPrefix($0) }) {
                    result.append(mentionSpan(matched))
                    i = text.index(afterAt, offsetBy: matched.count)
                    continue
                }

                let tokenEnd = remainder.firstIndex(where: { $0 == " " || $0 == "\n" }) ?? text.endIndex
                let token = String(remainder[..<tokenEnd])
                if !token.isEmpty {
                    result.append(mentionSpan(token))
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

        flushPlainBuffer()
        return result
    }

    /// Build the styled `@Name` span. Attaches a custom-scheme link only
    /// when the name resolves to a known TeamMember — `@All Team` and
    /// orphaned mentions render coloured but inert (no link, no tap).
    private func mentionSpan(_ name: String) -> AttributedString {
        var span = AttributedString("@\(name)")
        span.font = OPSStyle.Typography.body
        span.foregroundColor = OPSStyle.Colors.primaryAccent
        if let member = allTeamMembers.first(where: { $0.fullName == name }),
           let url = URL(string: "opsmention://\(member.id)") {
            span.link = url
        }
        return span
    }

    /// Resolve the tapped mention to a `User` via DataController and
    /// surface its contact sheet. Silently no-ops when the teammate is
    /// no longer on the company roster (e.g. removed since the note was
    /// posted) — same graceful-degradation policy as the renderer.
    private func openContactSheet(forMemberId memberId: String) {
        guard let companyId = dataController.currentUser?.companyId else { return }
        let users = dataController.getTeamMembers(companyId: companyId)
        if let user = users.first(where: { $0.id == memberId }) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            contactSheetMember = user
        }
    }
}
