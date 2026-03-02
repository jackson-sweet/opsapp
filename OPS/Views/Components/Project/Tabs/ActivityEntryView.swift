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
    let onDelete: () -> Void
    let onEdit: (String) -> Void
    let onPhotoTap: (([String], Int) -> Void)?

    @State private var isEditing = false
    @State private var editText = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: avatar + name + timestamp + menu
            HStack(spacing: 8) {
                // Avatar
                if let member = teamMember {
                    UserAvatar(teamMember: member, size: 28)
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(authorName.prefix(1)).uppercased())
                                .font(.custom("Mohave-Bold", size: 12))
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
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Edit note...", text: $editText, axis: .vertical)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )

                    HStack {
                        Button("Cancel") {
                            isEditing = false
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        Button("Save") {
                            onEdit(editText)
                            isEditing = false
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

    private func mentionHighlightedText(_ text: String) -> some View {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var result = Text("")

        for word in words {
            if word.hasPrefix("@") {
                result = result + Text(String(word) + " ")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            } else {
                result = result + Text(String(word) + " ")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }

        return result
    }
}
