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
    @EnvironmentObject private var dataController: DataController
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                // Project photos
                projectPhotosSection

                // Compose bar
                composeBar
                    .id("composeBar")

                // Notes feed
                notesFeed

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
            .onAppear {
                NotificationCenter.default.post(name: Notification.Name("WizardActivityTabViewed"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScrollToTarget"))) { notification in
                if let stepId = notification.userInfo?["stepId"] as? String {
                    withAnimation {
                        proxy.scrollTo("wizard_active_\(stepId)", anchor: .top)
                    }
                }
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

            // Error banner
            if let error = notesViewModel.error {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Text(error)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Spacer()
                    Button {
                        notesViewModel.error = nil
                    } label: {
                        Image(systemName: OPSStyle.Icons.xmark)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
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
                // @ mention button — focuses text field and inserts @
                Button(action: {
                    notesViewModel.newNoteText += "@"
                    notesViewModel.handleMentionInput(notesViewModel.newNoteText)
                    isTextFieldFocused = true
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
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
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
        .wizardTarget("write_note")
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
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Project Photos

    /// Bug e5310f3d — pull live in-flight uploads off the shared
    /// ImageSyncManager so the carousel can render placeholder cards
    /// while bytes are still climbing to S3. Each placeholder shows the
    /// photo we already have (the UIImage the user picked) plus a
    /// spinner; it dissolves into a real PhotoThumbnail once the upload
    /// settles and the URL lands on the project row.
    @ViewBuilder
    private var projectPhotosSection: some View {
        if let imageSyncManager = dataController.imageSyncManager {
            ProjectPhotosCarousel(
                project: project,
                imageSyncManager: imageSyncManager,
                onPhotoTap: { index in onProjectPhotoTap?(index) }
            )
            .padding(.top, 16)
        } else {
            // No sync manager available yet — fall back to the static
            // carousel (no upload spinners possible without it).
            staticPhotosCarousel
                .padding(.top, 16)
        }
    }

    /// Plain carousel without in-flight upload tracking. Used as a
    /// fallback when DataController hasn't booted ImageSyncManager yet
    /// (rare, but possible during cold-start race).
    private var staticPhotosCarousel: some View {
        let photos = project.getProjectImages()
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text(photos.isEmpty
                     ? "NO PHOTOS"
                     : "\(photos.count) PHOTO\(photos.count == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .padding(.horizontal, 16)

            if photos.isEmpty {
                Text("Tap the camera to add project photos")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                            Button(action: { onProjectPhotoTap?(index) }) {
                                PhotoThumbnail(url: url, project: project)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .wizardTarget(index == 0 ? "view_photo" : "")
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: - ProjectPhotosCarousel (Bug e5310f3d)

/// Carousel that observes `ImageSyncManager` so it can render
/// placeholder upload cards alongside completed photos. The
/// placeholders crossfade in when an upload starts, show a spinner
/// over a dimmed thumbnail of the picked image, and dissolve out when
/// the URL lands on the project row.
private struct ProjectPhotosCarousel: View {
    let project: Project
    @ObservedObject var imageSyncManager: ImageSyncManager
    let onPhotoTap: (Int) -> Void

    var body: some View {
        let photos = project.getProjectImages()
        let pending = imageSyncManager.currentInFlightUploads(for: project.id)
        let totalCount = photos.count + pending.count

        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text(totalCount == 0
                     ? "NO PHOTOS"
                     : "\(totalCount) PHOTO\(totalCount == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                if !pending.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(0.7)
                        Text("UPLOADING \(pending.count)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            // 0.2s crossfade so the UPLOADING badge feels confident, not
            // jumpy. Matches OPSStyle.Animation.fast.
            .animation(OPSStyle.Animation.fast, value: pending.count)

            if totalCount == 0 {
                Text("Tap the camera to add project photos")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                            Button(action: { onPhotoTap(index) }) {
                                PhotoThumbnail(url: url, project: project)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .wizardTarget(index == 0 ? "view_photo" : "")
                            .transition(.opacity)
                        }

                        // In-flight placeholders ride after the saved
                        // photos so the user sees their pick land on
                        // the right side of the carousel and slide left
                        // into the row once the upload finishes.
                        ForEach(pending) { upload in
                            UploadingPhotoTile(image: upload.image)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .animation(OPSStyle.Animation.fast, value: pending.map { $0.id })
                    .animation(OPSStyle.Animation.fast, value: photos.count)
                }
            }
        }
    }
}

/// Small tile showing the user's just-picked image dimmed under a
/// circular spinner. Replaces a `PhotoThumbnail` only while the upload
/// is in flight. Pulses gently so the user knows the upload is alive.
private struct UploadingPhotoTile: View {
    let image: UIImage
    @State private var pulse = false

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 72)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.imageOverlay)
                )
                .opacity(pulse ? 0.85 : 1.0)

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
        }
        .frame(width: 72, height: 72)
        .accessibilityLabel("Uploading photo")
        .onAppear {
            // Subtle 1.2s breathing pulse — not a strobe — so a slow
            // network feels alive without being distracting in the field.
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
