//
//  ActivityTabView.swift
//  OPS
//
//  Chronological mixed feed of photos and notes — the Activity tab.
//  Extracts notes + photos logic from the former ProjectDetailsView.
//

import SwiftUI

struct ActivityTabView: View {
    @ObservedObject var notesViewModel: ProjectNotesViewModel
    let project: Project
    let onShowImagePicker: () -> Void
    let onShowNoteImagePicker: () -> Void
    let onPhotoTap: ([String], Int) -> Void
    var onProjectPhotoTap: ((Int) -> Void)? = nil
    @Binding var noteFieldFocused: Bool

    @Environment(\.tutorialMode) private var tutorialMode
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                // Section header
                sectionLabel("ACTIVITY")
                    .padding(.top, 8)

                // Notes feed
                notesFeed

                // Compose bar
                composeBar
                    .id("composeBar")

                // Project photos (below notes)
                projectPhotosSection

                // Bottom spacer for scroll
                Spacer()
                    .frame(height: 200)
            }
            // Sync FocusState ↔ Binding
            .onChange(of: isTextFieldFocused) { _, newValue in
                noteFieldFocused = newValue
                if newValue {
                    // Scroll compose bar into view above keyboard
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("composeBar", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: noteFieldFocused) { _, newValue in
                if newValue { isTextFieldFocused = true }
            }
        }
    }

    // MARK: - Notes Feed

    private var notesFeed: some View {
        VStack(alignment: .leading, spacing: 12) {
            if notesViewModel.isLoading && notesViewModel.notes.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    Spacer()
                }
                .padding(.vertical, OPSStyle.Layout.spacing4)
            } else if notesViewModel.notes.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: OPSStyle.Layout.IconSize.xl))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("No activity yet")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("Post a note or add photos for your team")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing5)
            } else {
                ForEach(notesViewModel.notes) { note in
                    ActivityEntryView(
                        note: note,
                        authorName: notesViewModel.authorName(for: note.authorId),
                        teamMember: notesViewModel.teamMember(for: note.authorId),
                        isOwnNote: notesViewModel.isOwnNote(note),
                        onDelete: {
                            Task { await notesViewModel.deleteNote(note) }
                        },
                        onEdit: { newContent in
                            Task { await notesViewModel.updateNoteContent(note, newContent: newContent) }
                        },
                        onPhotoTap: onPhotoTap
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        VStack(spacing: 0) {
            // Pending images strip
            if !notesViewModel.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(Array(notesViewModel.pendingImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))

                                Button(action: { notesViewModel.removeImage(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .background(Circle().fill(OPSStyle.Colors.background))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                }
            }

            // Upload progress
            if notesViewModel.isUploading {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    Text("Uploading photos...")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, OPSStyle.Layout.spacing1)
            }

            // Mention suggestions
            if notesViewModel.showMentionPicker {
                mentionSuggestions
            }

            // Input row
            HStack(spacing: OPSStyle.Layout.spacing1) {
                // @ mention button
                Button(action: {
                    notesViewModel.newNoteText += "@"
                    notesViewModel.handleMentionInput(notesViewModel.newNoteText)
                }) {
                    Image(systemName: OPSStyle.Icons.mention)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 32, height: 32)

                // Camera button
                Button(action: onShowNoteImagePicker) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 32, height: 32)

                TextField("Write a note...", text: $notesViewModel.newNoteText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .focused($isTextFieldFocused)
                    .onChange(of: notesViewModel.newNoteText) { _, newValue in
                        notesViewModel.handleMentionInput(newValue)
                    }
                    .onSubmit {
                        if notesViewModel.canPost {
                            Task { await notesViewModel.postNote() }
                        }
                    }

                Button(action: {
                    Task { await notesViewModel.postNote() }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(
                            notesViewModel.canPost
                                ? OPSStyle.Colors.primaryAccent
                                : OPSStyle.Colors.tertiaryText
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!notesViewModel.canPost || notesViewModel.isUploading)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(
                    isTextFieldFocused
                        ? OPSStyle.Colors.primaryAccent
                        : OPSStyle.Colors.cardBorder,
                    lineWidth: isTextFieldFocused ? 1.5 : 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isTextFieldFocused)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Mention Suggestions

    private var mentionSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // @All Team pill
                if notesViewModel.showAllTeamOption {
                    Button(action: { notesViewModel.insertAllTeamMention() }) {
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
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                ForEach(notesViewModel.mentionSuggestions, id: \.id) { member in
                    Button(action: { notesViewModel.insertMention(member) }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            UserAvatar(teamMember: member, size: 24)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Project Photos

    private var projectPhotosSection: some View {
        let photos = project.getProjectImages()

        return Group {
            if !photos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("[ PHOTOS ]")
                        .font(OPSStyle.Typography.smallCaption)
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                                    Button(action: { onProjectPhotoTap?(index) }) {
                                        PhotoThumbnail(url: url, project: project)
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(14)
                        }

                        Text("\(photos.count) PHOTO\(photos.count == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.top, 24)
            }
        }
    }
}
