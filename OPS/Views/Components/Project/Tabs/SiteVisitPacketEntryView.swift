//
//  SiteVisitPacketEntryView.swift
//  OPS
//
//  Bug 7649fd48 — the site-visit packet posted into project activity was a
//  wall of raw text ("SITE VISIT PACKET\n\nMEASURE :: …"). It is now a SITE
//  VISIT RECORD: a scannable card in the feed, and the full tokenized record
//  behind it (`SiteVisitRecordView`).
//
//  The record assembles from the note's synced `content_metadata` plus synced
//  `project_photos` rows — never from the capturing device's local artifacts —
//  so a teammate who was never on site sees exactly what the operator brought
//  back.
//
//  Financial visibility is resolved HERE, at the surface that knows the
//  viewer, and handed to the assembler as a single boolean. Everything money
//  is then filtered out before any view sees it.
//
//  Also renders `status_change` system notes (written by OPS-Web) as a quiet
//  one-line system row instead of the bogus "Team Member / Status changed"
//  user card they previously masqueraded as.
//

import SwiftUI
import SwiftData

// MARK: - Feed entry

struct SiteVisitPacketEntryView: View {
    let note: ProjectNote
    let authorName: String
    let teamMember: TeamMember?

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var projectPhotos: [ProjectPhoto]

    @State private var showRecord = false
    @State private var viewerState: RecordViewerState?

    private struct RecordViewerState: Identifiable {
        let id = UUID()
        let photos: [String]
        let index: Int
    }

    init(note: ProjectNote, authorName: String, teamMember: TeamMember?) {
        self.note = note
        self.authorName = authorName
        self.teamMember = teamMember
        let pid = note.projectId
        _projectPhotos = Query(
            filter: #Predicate<ProjectPhoto> { $0.projectId == pid && $0.deletedAt == nil },
            sort: [SortDescriptor(\ProjectPhoto.createdAt, order: .forward)]
        )
    }

    private var metadata: SiteVisitPacketMetadata? {
        SiteVisitPacketMetadata.decode(from: note.contentMetadataJSON)
    }

    /// Photos captured by THIS visit: matched by site_visit_id when the
    /// metadata carries one, else any site-visit-sourced photo on the project
    /// (legacy packets written before ids landed in metadata).
    private var visitPhotoURLs: [String] {
        let eligible = projectPhotos.filter { $0.isGalleryEligible }
        if let visitId = metadata?.siteVisitId, !visitId.isEmpty {
            let matched = eligible.filter { $0.siteVisitId == visitId }
            if !matched.isEmpty { return matched.map(\.url) }
        }
        return eligible.filter { $0.source == "site_visit" }.map(\.url)
    }

    /// The one place financial visibility is decided for this surface.
    /// `finances.view` is the app's money gate — the same key the lead day
    /// sheet, the Books tab, and the billable roll-up read.
    private var record: SiteVisitRecord {
        SiteVisitRecord.assemble(
            metadata: metadata,
            photoURLs: visitPhotoURLs,
            capturedAt: note.createdAt,
            operatorName: authorName,
            canViewFinancials: permissionStore.can("finances.view")
        )
    }

    var body: some View {
        SiteVisitRecordCard(
            record: record,
            teamMember: teamMember,
            onOpen: { showRecord = true }
        )
        .sheet(isPresented: $showRecord) {
            SiteVisitRecordView(
                record: record,
                onPhotoTap: { photos, index in
                    viewerState = RecordViewerState(photos: photos, index: index)
                }
            )
            .environmentObject(dataController)
        }
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
