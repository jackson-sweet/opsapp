//
//  SiteVisitPacketEntryView.swift
//  OPS
//
//  Bug 7649fd48 — the site-visit packet posted into project activity was a
//  wall of raw text ("SITE VISIT PACKET\n\nMEASURE :: …"). The feed entry is
//  now a scannable system card — who visited, when, and what was captured —
//  and tapping it opens a structured packet sheet with the photos,
//  measurements, notes, and checklist, each tappable through to the content.
//
//  Also renders `status_change` system notes (written by OPS-Web) as a quiet
//  one-line system row instead of the bogus "Team Member / Status changed"
//  user card they previously masqueraded as.
//

import SwiftUI
import SwiftData

// MARK: - Packet Metadata

/// Decoded `project_notes.content_metadata` for `event_kind == "site_visit"`.
/// Written by `SiteVisitPacketNote.build`; every field optional so partial or
/// future shapes render gracefully.
struct SiteVisitPacketMetadata: Decodable {
    struct Measurement: Decodable {
        let label: String
        let value: String
    }

    let siteVisitId: String?
    let photoCount: Int?
    let measurements: [Measurement]?
    let notes: [String]?
    let checklist: [String]?

    enum CodingKeys: String, CodingKey {
        case siteVisitId = "site_visit_id"
        case photoCount  = "photo_count"
        case measurements
        case notes
        case checklist
    }

    static func decode(from json: String?) -> SiteVisitPacketMetadata? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SiteVisitPacketMetadata.self, from: data)
    }

    /// Mono summary line for the feed card — only the parts that exist.
    /// e.g. "4 PHOTOS · 2 MEASUREMENTS · NOTES · CHECKLIST"
    var summaryLine: String {
        var parts: [String] = []
        if let photoCount, photoCount > 0 {
            parts.append("\(photoCount) PHOTO\(photoCount == 1 ? "" : "S")")
        }
        if let measurements, !measurements.isEmpty {
            parts.append("\(measurements.count) MEASUREMENT\(measurements.count == 1 ? "" : "S")")
        }
        if let notes, !notes.isEmpty {
            parts.append(notes.count == 1 ? "1 NOTE" : "\(notes.count) NOTES")
        }
        if let checklist, !checklist.isEmpty {
            parts.append("CHECKLIST")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Feed Card

/// Activity-feed card for a completed site visit. Same header grammar as
/// every other feed card (avatar · name + timestamp · action subtitle), a
/// tan SITE VISIT tag (tan = the site-visit semantic tone), and a mono
/// summary of what was captured. The whole card opens the packet sheet.
struct SiteVisitPacketEntryView: View {
    let note: ProjectNote
    let authorName: String
    let teamMember: TeamMember?

    @EnvironmentObject private var dataController: DataController
    @State private var showPacketSheet = false

    private var metadata: SiteVisitPacketMetadata? {
        SiteVisitPacketMetadata.decode(from: note.contentMetadataJSON)
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showPacketSheet = true
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
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

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Text(authorName)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text(ActivityRelativeTimestamp.string(from: note.createdAt))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        Text("completed a site visit")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()

                    Text("SITE VISIT")
                        .font(OPSStyle.Typography.status)
                        .foregroundColor(OPSStyle.Colors.tanTextM)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OPSStyle.Colors.tanFillM)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.tanLineM, lineWidth: 1)
                        )
                        .cornerRadius(4)
                }

                if let summary = metadata?.summaryLine, !summary.isEmpty {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(summary)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Image(systemName: OPSStyle.Icons.chevronRight)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(14)
            .glassSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(packetAccessibilityLabel)
        .sheet(isPresented: $showPacketSheet) {
            SiteVisitPacketSheet(note: note, authorName: authorName, metadata: metadata)
                .environmentObject(dataController)
        }
    }

    private var packetAccessibilityLabel: String {
        var label = "\(authorName) completed a site visit"
        if let summary = metadata?.summaryLine, !summary.isEmpty {
            label += " — \(summary.lowercased())"
        }
        return label
    }
}

// MARK: - Packet Sheet

/// Structured, tappable view of everything a site visit captured. Renders
/// from the note's metadata plus synced `project_photos` rows — never from
/// device-local capture artifacts — so it works on every teammate's device.
struct SiteVisitPacketSheet: View {
    let note: ProjectNote
    let authorName: String
    let metadata: SiteVisitPacketMetadata?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Query private var projectPhotos: [ProjectPhoto]
    @State private var viewerState: PacketViewerState?

    private struct PacketViewerState: Identifiable {
        let id = UUID()
        let photos: [String]
        let index: Int
    }

    init(note: ProjectNote, authorName: String, metadata: SiteVisitPacketMetadata?) {
        self.note = note
        self.authorName = authorName
        self.metadata = metadata
        let pid = note.projectId
        _projectPhotos = Query(
            filter: #Predicate<ProjectPhoto> { $0.projectId == pid && $0.deletedAt == nil },
            sort: [SortDescriptor(\ProjectPhoto.createdAt, order: .forward)]
        )
    }

    /// Photos captured by THIS visit: matched by site_visit_id when the
    /// metadata carries one, else any site-visit-sourced photo on the project
    /// (legacy packets written before ids landed in metadata).
    private var visitPhotos: [ProjectPhoto] {
        let eligible = projectPhotos.filter { $0.isGalleryEligible }
        if let visitId = metadata?.siteVisitId, !visitId.isEmpty {
            let matched = eligible.filter { $0.siteVisitId == visitId }
            if !matched.isEmpty { return matched }
        }
        return eligible.filter { $0.source == "site_visit" }
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        return formatter.string(from: note.createdAt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                // Header
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("SITE VISIT")
                        .font(OPSStyle.Typography.section)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("\(authorName.uppercased()) · \(dateLine.uppercased())")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.top, OPSStyle.Layout.spacing3)

                if !visitPhotos.isEmpty {
                    packetSection(title: "// PHOTOS") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                ForEach(Array(visitPhotos.enumerated()), id: \.element.url) { index, photo in
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        viewerState = PacketViewerState(
                                            photos: visitPhotos.map { $0.url },
                                            index: index
                                        )
                                    }) {
                                        PhotoThumbnail(
                                            url: photo.url,
                                            project: nil,
                                            remoteThumbnailURL: photo.thumbnailURL
                                        )
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }

                if let measurements = metadata?.measurements, !measurements.isEmpty {
                    packetSection(title: "// MEASUREMENTS") {
                        VStack(spacing: 0) {
                            ForEach(Array(measurements.enumerated()), id: \.offset) { index, measurement in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(measurement.label)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Spacer()
                                    Text(measurement.value)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, OPSStyle.Layout.spacing2)

                                if index < measurements.count - 1 {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.line)
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                }

                if let notes = metadata?.notes, !notes.isEmpty {
                    packetSection(title: "// NOTES") {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                            ForEach(Array(notes.enumerated()), id: \.offset) { _, text in
                                Text(text)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if let checklist = metadata?.checklist, !checklist.isEmpty {
                    packetSection(title: "// CHECKLIST") {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            ForEach(Array(checklist.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                                        .foregroundColor(OPSStyle.Colors.olive)
                                    Text(line)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                // Legacy fallback: a packet note written before structured
                // metadata existed still shows its raw content.
                if metadata == nil && !note.content.isEmpty {
                    packetSection(title: "// PACKET") {
                        Text(note.content)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: OPSStyle.Layout.spacing5)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $viewerState) { state in
            PhotoCommentViewer(
                photos: state.photos,
                initialIndex: state.index,
                onDismiss: { viewerState = nil },
                projectId: note.projectId
            )
            .environmentObject(dataController)
        }
    }

    @ViewBuilder
    private func packetSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            content()
        }
        .padding(14)
        .glassSurface()
    }
}

// MARK: - Status Change Line

/// Quiet one-line system row for `event_kind == "status_change"` notes
/// (written by OPS-Web with `content_metadata: {from, to}`). Rendered without
/// card chrome so lifecycle metadata reads as history, not conversation.
struct StatusChangeEntryView: View {
    let note: ProjectNote
    let authorName: String

    private struct StatusChangeMetadata: Decodable {
        let from: String?
        let to: String?
    }

    private var transition: (from: String, to: String)? {
        guard let json = note.contentMetadataJSON,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(StatusChangeMetadata.self, from: data),
              let from = decoded.from, let to = decoded.to,
              !from.isEmpty, !to.isEmpty else { return nil }
        return (from, to)
    }

    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                // Name + timestamp on the top line; the status transition gets
                // its own full-width line so it never truncates (the transition
                // is the point of the entry).
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("\(authorName) changed status")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer(minLength: OPSStyle.Layout.spacing2)
                    Text(ActivityRelativeTimestamp.string(from: note.createdAt))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                if let transition {
                    Text("\(transition.from.uppercased()) → \(transition.to.uppercased())")
                        .font(OPSStyle.Typography.status)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let transition {
            return "\(authorName) changed status from \(transition.from) to \(transition.to)"
        }
        return "\(authorName) changed status"
    }
}

// MARK: - Shared Relative Timestamp

/// One relative-timestamp formatter for activity entries — the same output
/// grammar the note and annotation cards use ("just now", "5m ago", "2d ago",
/// then "MMM d").
enum ActivityRelativeTimestamp {
    static func string(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
