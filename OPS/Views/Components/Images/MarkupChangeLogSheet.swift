//
//  MarkupChangeLogSheet.swift
//  OPS
//
//  Collaborative markup change log. One row per author who marked up the photo,
//  each with a per-viewer show/hide eye toggle (local-only — never synced). An
//  expandable ACTIVITY disclosure shows the per-author change history newest-first.
//  Surfaced from the editor toolbar only when a collaborator's marks are present.
//

import SwiftUI
import SwiftData
import UIKit

struct MarkupChangeLogSheet: View {
    /// Active authors (z-order) — includes the current user when they have a layer.
    let authorLayers: [MarkupLayer]
    let changeLog: [MarkupChangeEvent]
    let currentUserId: String
    @Binding var hiddenAuthorIds: Set<String>

    @State private var showActivity = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(authorLayers.enumerated()), id: \.element.id) { pair in
                        MarkupAuthorRow(
                            layer: pair.element,
                            isCurrentUser: pair.element.authorId == currentUserId,
                            isHidden: hiddenAuthorIds.contains(pair.element.authorId),
                            onToggle: { toggleVisibility(of: pair.element.authorId) }
                        )
                        if pair.offset < authorLayers.count - 1 {
                            Divider().background(OPSStyle.Colors.separator)
                                .padding(.leading, OPSStyle.Layout.spacing3)
                        }
                    }

                    if !changeLog.isEmpty {
                        activitySection
                    }
                }
            }
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .presentationDetents([.height(280), .medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("MARKUP")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Text("\(authorLayers.count)")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    // MARK: Activity disclosure

    private var activitySection: some View {
        VStack(spacing: 0) {
            Divider().background(OPSStyle.Colors.separator)

            Button {
                withAnimation(OPSStyle.Animation.panel) { showActivity.toggle() }
            } label: {
                HStack {
                    Text("ACTIVITY")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Image(systemName: showActivity ? "chevron.up" : "chevron.down")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }

            if showActivity {
                VStack(spacing: 0) {
                    ForEach(changeLog.sorted { $0.at > $1.at }) { event in
                        MarkupActivityRow(event: event)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func toggleVisibility(of authorId: String) {
        // The current user's own marks are the editable canvas — always shown.
        guard authorId != currentUserId else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if hiddenAuthorIds.contains(authorId) {
            hiddenAuthorIds.remove(authorId)
        } else {
            hiddenAuthorIds.insert(authorId)
        }
    }
}

// MARK: - Author row

private struct MarkupAuthorRow: View {
    let layer: MarkupLayer
    let isCurrentUser: Bool
    let isHidden: Bool
    let onToggle: () -> Void

    @Query private var matchingUsers: [User]

    init(layer: MarkupLayer, isCurrentUser: Bool, isHidden: Bool, onToggle: @escaping () -> Void) {
        self.layer = layer
        self.isCurrentUser = isCurrentUser
        self.isHidden = isHidden
        self.onToggle = onToggle
        let authorId = layer.authorId
        _matchingUsers = Query(filter: #Predicate<User> { $0.id == authorId })
    }

    private var displayName: String {
        if isCurrentUser { return "You" }
        if let user = matchingUsers.first { return user.fullName }
        let name = layer.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Teammate" : name
    }

    private var subtitle: String {
        var parts: [String] = []
        if let count = layer.strokeCount, count > 0 {
            parts.append(count == 1 ? "1 mark" : "\(count) marks")
        }
        parts.append(MarkupRelativeTime.string(from: layer.updatedAt))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            avatar
                .frame(width: 36, height: 36)
                .opacity(isHidden ? 0.4 : 1.0)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(subtitle)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .opacity(isHidden ? 0.5 : 1.0)

            Spacer()

            if !isCurrentUser {
                Button(action: onToggle) {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(isHidden ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .accessibilityLabel(isHidden ? "Show \(displayName)'s marks" : "Hide \(displayName)'s marks")
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if let user = matchingUsers.first {
            UserAvatar(user: user, size: 36)
        } else {
            let parts = layer.authorName.split(separator: " ", maxSplits: 1).map(String.init)
            UserAvatar(
                firstName: parts.first ?? "·",
                lastName: parts.count > 1 ? parts[1] : "",
                size: 36
            )
        }
    }
}

// MARK: - Activity row

private struct MarkupActivityRow: View {
    let event: MarkupChangeEvent

    @Query private var matchingUsers: [User]

    init(event: MarkupChangeEvent) {
        self.event = event
        let authorId = event.authorId
        _matchingUsers = Query(filter: #Predicate<User> { $0.id == authorId })
    }

    private var name: String {
        if let user = matchingUsers.first { return user.fullName }
        let n = event.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Teammate" : n
    }

    private var phrase: String {
        switch event.action {
        case .added:
            if let delta = event.strokeDelta, delta > 0 {
                return delta == 1 ? "added 1 mark" : "added \(delta) marks"
            }
            return "added markup"
        case .edited:
            return "edited markup"
        case .cleared:
            return "cleared markup"
        }
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(name)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(phrase)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(MarkupRelativeTime.string(from: event.at))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }
}

// MARK: - Relative time

/// Compact, tactical relative time: "just now", "5m ago", "2h ago", "3d ago",
/// or a short date. Mirrors the terse OPS voice (mono numerals via the caller's
/// font token).
enum MarkupRelativeTime {
    static func string(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(seconds / 86_400)
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
