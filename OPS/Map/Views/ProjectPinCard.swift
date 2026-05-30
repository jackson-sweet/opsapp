//
//  ProjectPinCard.swift
//  OPS
//
//  Slide-up card shown when a project pin is tapped on the map.
//  Collapsed: project name, status badge, client, address, action buttons.
//  Expanded (swipe up): tasks, team avatars, photos.
//

import SwiftUI

struct ProjectPinCard: View {

    let project: Project
    let todaysTasks: [ProjectTask]
    let teamMembers: [User]
    let onNavigate: () -> Void
    let onDetails: () -> Void
    let onDismiss: () -> Void

    // Gesture state
    @State private var dragOffset: CGFloat = 0
    @State private var isExpanded = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Drag indicator ──
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 6)

            // ── Content ──
            VStack(alignment: .leading, spacing: 0) {

                // ── Header: Project name + Status badge ──
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title.uppercased())
                            .font(OPSStyle.Typography.caption)
                            .tracking(0.5)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        // Client name
                        if let client = project.client {
                            Text(client.displayName)
                                .font(OPSStyle.Typography.cardBody)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }

                        // Address (street + city only)
                        if let address = project.address, !address.isEmpty {
                            Text(simplifiedAddress(address))
                                .font(OPSStyle.Typography.smallBody)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Status badge
                    statusBadge
                }

                // ── Divider before buttons ──
                divider
                    .padding(.vertical, 12)

                // ── Action buttons ──
                HStack(spacing: 12) {
                    Button(action: onNavigate) {
                        Text("NAVIGATE")
                            .font(OPSStyle.Typography.caption)
                            .tracking(0.5)
                            .foregroundColor(OPSStyle.Colors.background)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onDetails) {
                        Text("DETAILS")
                            .font(OPSStyle.Typography.caption)
                            .tracking(0.5)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)

                // ── Expand hint (when collapsed) ──
                if !isExpanded {
                    HStack {
                        Spacer()
                        Text("SWIPE UP FOR MORE")
                            .font(OPSStyle.Typography.miniLabel)
                            .tracking(0.3)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Image(OPSStyle.Icons.chevronUp)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    .padding(.top, 4)
                }

                // ── Expanded content: Tasks, Team, Photos ──
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 4
            )
            .fill(.ultraThinMaterial)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 4
                )
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        )
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let translation = value.translation.height
                    if translation > 0 && !isExpanded {
                        // Only allow downward drag offset when collapsed
                        dragOffset = translation
                    } else if translation < -30 && !isExpanded {
                        // Swipe up to expand (collapsed → expanded)
                        withAnimation(OPSStyle.Animation.standard) {
                            isExpanded = true
                        }
                    }
                }
                .onEnded { value in
                    let translation = value.translation.height
                    if isExpanded && translation > 40 {
                        // Swipe down while expanded → collapse back to minimized
                        withAnimation(OPSStyle.Animation.standard) {
                            isExpanded = false
                            dragOffset = 0
                        }
                    } else if !isExpanded && translation > 50 {
                        // Swipe down while collapsed → dismiss
                        withAnimation(OPSStyle.Animation.standard) {
                            dragOffset = 400
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()
                        }
                    } else {
                        // Snap back
                        withAnimation(OPSStyle.Animation.standard) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    // MARK: - Computed

    /// All tasks for this project.
    private var allTasks: [ProjectTask] {
        project.tasks.filter { $0.deletedAt == nil }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        Text(project.status.displayName.uppercased())
            .font(OPSStyle.Typography.miniLabel)
            .tracking(0.3)
            .foregroundColor(project.status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(project.status.color.opacity(0.15))
            )
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        // ── Tasks ──
        if !allTasks.isEmpty {
            divider
                .padding(.top, 8)
                .padding(.bottom, 12)

            Text("TASKS")
                .font(OPSStyle.Typography.microLabel)
                .tracking(0.5)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            taskBadgesView
                .padding(.top, 6)
        }

        // ── Team ──
        if !teamMembers.isEmpty {
            divider
                .padding(.vertical, 12)

            Text("TEAM")
                .font(OPSStyle.Typography.microLabel)
                .tracking(0.5)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            teamAvatarsView
                .padding(.top, 6)
        }

        // ── Photos ──
        photoGallery
    }

    // MARK: - Task Badges

    private var taskBadgesView: some View {
        // Wrap badges in horizontal rows
        WrappingHStack(allTasks, id: \.id, spacing: 6, lineSpacing: 6) { task in
            taskBadge(task)
        }
    }

    private func taskBadge(_ task: ProjectTask) -> some View {
        let taskColor = Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent
        let isDone = task.status == .completed || task.status == .cancelled

        return HStack(spacing: 4) {
            Circle()
                .fill(taskColor)
                .frame(width: 6, height: 6)

            Text(task.displayTitle.uppercased())
                .font(OPSStyle.Typography.miniLabel)
                .tracking(0.3)
                .foregroundColor(isDone ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                .strikethrough(isDone, color: OPSStyle.Colors.tertiaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(taskColor.opacity(isDone ? 0.05 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(taskColor.opacity(isDone ? 0.08 : 0.20), lineWidth: 1)
        )
        .opacity(isDone ? 0.6 : 1.0)
    }

    // MARK: - Team Avatars

    private var teamAvatarsView: some View {
        HStack(spacing: -6) {
            let visible = Array(teamMembers.prefix(6))
            ForEach(visible.indices, id: \.self) { index in
                teamAvatar(visible[index])
                    .zIndex(Double(visible.count - index))
            }

            // Overflow count
            if teamMembers.count > 6 {
                Text("+\(teamMembers.count - 6)")
                    .font(OPSStyle.Typography.status)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }

    private func teamAvatar(_ user: User) -> some View {
        Group {
            if let urlString = user.profileImageURL, !urlString.isEmpty,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    default:
                        avatarInitials(user)
                    }
                }
            } else {
                avatarInitials(user)
            }
        }
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.5), lineWidth: 1.5)
        )
    }

    private func avatarInitials(_ user: User) -> some View {
        let initials = "\(user.firstName.prefix(1))\(user.lastName.prefix(1))"
        let color = userColor(user)

        return Text(initials.uppercased())
            .font(OPSStyle.Typography.status)
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(color)
            )
    }

    private func userColor(_ user: User) -> Color {
        if let hex = user.userColor, !hex.isEmpty,
           let color = Color(hex: hex) {
            return color
        }
        return OPSStyle.Colors.primaryAccent
    }

    // MARK: - Photo Gallery

    @ViewBuilder
    private var photoGallery: some View {
        let imageURLs = project.getProjectImageURLs().filter { !$0.isEmpty }

        if !imageURLs.isEmpty {
            divider
                .padding(.vertical, 12)

            Text("PHOTOS")
                .font(OPSStyle.Typography.microLabel)
                .tracking(0.5)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(imageURLs, id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
                                case .failure:
                                    photoPlaceholder
                                case .empty:
                                    ProgressView()
                                        .frame(width: 80, height: 80)
                                @unknown default:
                                    photoPlaceholder
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
            .fill(Color.white.opacity(0.05))
            .frame(width: 80, height: 80)
            .overlay(
                Image(OPSStyle.Icons.photo)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            )
    }

    // MARK: - Helpers

    private func simplifiedAddress(_ address: String) -> String {
        let parts = address.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2 {
            return "\(parts[0]), \(parts[1])"
        }
        return parts.first ?? address
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
    }
}

// MARK: - WrappingHStack

/// Horizontal wrapping layout for task badges — avoids FlowLayout name collision.
private struct WrappingHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let content: (Data.Element) -> Content

    init(_ data: Data, id: KeyPath<Data.Element, Data.Element.ID>, spacing: CGFloat = 6, lineSpacing: CGFloat = 6, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            generateContent(in: geometry)
        }
        .frame(height: calculateHeight())
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(data) { item in
                content(item)
                    .padding(.trailing, spacing)
                    .padding(.bottom, lineSpacing)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > geometry.size.width {
                            width = 0
                            height -= dimension.height + lineSpacing
                        }
                        let result = width
                        if item.id == data.last?.id {
                            width = 0
                        } else {
                            width -= dimension.width + spacing
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item.id == data.last?.id {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }

    private func calculateHeight() -> CGFloat {
        // Estimate: ~26pt per badge row, assume ~3 badges per row
        let estimatedRows = max(1, ceil(Double(data.count) / 3.0))
        return CGFloat(estimatedRows) * 26
    }
}
