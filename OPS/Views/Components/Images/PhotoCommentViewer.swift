//
//  PhotoCommentViewer.swift
//  OPS
//
//  Full-screen photo viewer with comment panel for discussing individual photos.
//

import SwiftUI
import SwiftData

struct PhotoCommentViewer: View {
    let photos: [String]
    let initialIndex: Int
    let onDismiss: () -> Void
    var projectId: String

    @StateObject private var viewModel: PhotoCommentsViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var currentIndex: Int
    @State private var showingAnnotation = false
    @State private var isCommentsExpanded = false
    @FocusState private var isComposeFocused: Bool

    init(photos: [String], initialIndex: Int, onDismiss: @escaping () -> Void, projectId: String) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self.projectId = projectId
        self._currentIndex = State(initialValue: initialIndex)
        let url = initialIndex < photos.count ? photos[initialIndex] : ""
        self._viewModel = StateObject(wrappedValue: PhotoCommentsViewModel(photoURL: url, projectId: projectId))
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            // Photo gallery with swipe
            TabView(selection: $currentIndex) {
                ForEach(0..<photos.count, id: \.self) { index in
                    ZoomablePhotoView(url: photos[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .onChange(of: currentIndex) { _, newIndex in
                guard newIndex < photos.count else { return }
                viewModel.switchPhoto(to: photos[newIndex])
                isCommentsExpanded = false
            }

            // UI overlay
            VStack(spacing: 0) {
                // Top bar
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 48)

                Spacer()

                // Comment panel at bottom
                commentPanel
            }
        }
        .statusBar(hidden: true)
        .preferredColorScheme(.dark)
        .onAppear {
            setupViewModel()
            Task { await viewModel.loadComments() }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: OPSStyle.Icons.xmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(12)
                    .background(OPSStyle.Colors.background)
                    .clipShape(Circle())
            }

            Spacer()

            Text("\(currentIndex + 1) of \(photos.count)")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(8)
                .background(OPSStyle.Colors.background)
                .cornerRadius(OPSStyle.Layout.largeCornerRadius)
        }
    }

    // MARK: - Comment Panel

    private var commentPanel: some View {
        VStack(spacing: 0) {
            // Toggle bar
            commentToggleBar

            // Expanded comment list
            if isCommentsExpanded && !viewModel.comments.isEmpty {
                commentList
            }

            // Mention suggestions
            if viewModel.showMentionPicker {
                mentionSuggestionsBar
            }

            // Compose bar
            composeBar

            // Annotate button
            annotateBar
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Toggle Bar

    private var commentToggleBar: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCommentsExpanded.toggle()
            }
        }) {
            HStack {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text("\(viewModel.comments.count) COMMENT\(viewModel.comments.count == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Image(systemName: isCommentsExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Comment List

    private var commentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.comments, id: \.id) { comment in
                        PhotoCommentRow(
                            comment: comment,
                            authorName: viewModel.authorName(for: comment.authorId),
                            teamMember: viewModel.teamMember(for: comment.authorId),
                            isOwn: viewModel.isOwnComment(comment),
                            isEditing: viewModel.editingNoteId == comment.id,
                            editText: $viewModel.editText,
                            onEdit: { viewModel.startEditing(comment) },
                            onCancelEdit: { viewModel.cancelEditing() },
                            onSaveEdit: { Task { await viewModel.saveEdit() } },
                            onDelete: { Task { await viewModel.deleteComment(comment) } }
                        )
                        .id(comment.id)

                        if comment.id != viewModel.comments.last?.id {
                            Rectangle()
                                .fill(OPSStyle.Colors.separator)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 250)
        }
    }

    // MARK: - Mention Suggestions

    private var mentionSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // @All Team pill
                if viewModel.showAllTeamOption {
                    Button(action: { viewModel.insertAllTeamMention() }) {
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
                    Button(action: { viewModel.insertMention(member) }) {
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
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing1)
        }
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // @ mention trigger
            Button(action: {
                if !viewModel.newCommentText.contains("@") {
                    viewModel.newCommentText += "@"
                    viewModel.handleMentionInput(viewModel.newCommentText)
                }
            }) {
                Text("@")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PlainButtonStyle())

            TextField("Comment...", text: $viewModel.newCommentText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .focused($isComposeFocused)
                .onChange(of: viewModel.newCommentText) { _, newValue in
                    viewModel.handleMentionInput(newValue)
                }
                .onSubmit {
                    Task { await viewModel.postComment() }
                }

            Button(action: {
                Task { await viewModel.postComment() }
            }) {
                Image(systemName: OPSStyle.Icons.sendFill)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(
                        viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? OPSStyle.Colors.tertiaryText
                            : OPSStyle.Colors.primaryAccent
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Annotate Bar

    private var annotateBar: some View {
        HStack {
            Spacer()
            Button(action: { showingAnnotation = true }) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    Text("ANNOTATE")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.background)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
        .fullScreenCover(isPresented: $showingAnnotation) {
            if currentIndex < photos.count {
                PhotoAnnotationView(
                    photoURL: photos[currentIndex],
                    projectId: projectId
                )
            }
        }
    }

    // MARK: - Setup

    private func setupViewModel() {
        guard let user = dataController.currentUser,
              let companyId = user.companyId,
              let company = dataController.getCurrentUserCompany(),
              let modelContext = dataController.modelContext else { return }

        viewModel.setup(
            companyId: companyId,
            currentUserId: user.id,
            teamMembers: Array(company.teamMembers),
            modelContext: modelContext
        )
    }
}

// MARK: - Photo Comment Row

struct PhotoCommentRow: View {
    let comment: ProjectNote
    let authorName: String
    let teamMember: TeamMember?
    let isOwn: Bool
    let isEditing: Bool
    @Binding var editText: String
    let onEdit: () -> Void
    let onCancelEdit: () -> Void
    let onSaveEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            // Header: avatar + name + timestamp + menu
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let member = teamMember {
                    UserAvatar(teamMember: member, size: 28)
                } else {
                    ZStack {
                        Circle()
                            .fill(OPSStyle.Colors.subtleBackground)
                            .frame(width: 28, height: 28)
                        Text(initials)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(authorName.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(formatTimestamp(comment.createdAt))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if isOwn && !isEditing {
                    Menu {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                }
            }

            // Content or edit field
            if isEditing {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    TextField("Edit comment...", text: $editText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)

                    Button(action: onSaveEdit) {
                        Text("Save")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: onCancelEdit) {
                        Text("Cancel")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                highlightedContent(comment.content)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .confirmationDialog("Delete Comment", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This comment will be permanently deleted.")
        }
    }

    private var initials: String {
        let parts = authorName.split(separator: " ")
        let first = parts.first?.first?.uppercased() ?? ""
        let last = parts.count > 1 ? (parts.last?.first?.uppercased() ?? "") : ""
        return "\(first)\(last)"
    }

    private func highlightedContent(_ text: String) -> Text {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var result = Text("")
        var inMention = false
        var isFirst = true

        for word in words {
            let separator = isFirst ? "" : " "
            isFirst = false
            if word.hasPrefix("@") {
                inMention = true
                result = result + Text(separator + word)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            } else if inMention {
                result = result + Text(separator + word)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                inMention = false
            } else {
                result = result + Text(separator + word)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
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
