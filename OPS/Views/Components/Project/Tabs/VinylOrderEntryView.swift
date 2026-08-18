//
//  VinylOrderEntryView.swift
//  OPS
//
//  The `vinyl_order` system entry in the project Activity feed.
//
//  A crew member scrolling this feed is reading a chronology of what happened on
//  the job. "The vinyl got ordered" belongs in that chronology, and the useful
//  part is WHAT — so the card leads with the disposition and then lists the
//  actual quantities, rather than announcing a state change and making the
//  reader go hunting for the numbers on another tab.
//
//  Renders from the note's structured `content_metadata`. A note written by a
//  newer build, or one that only carries plain text, falls back to the note body
//  verbatim — the entry degrades, it never disappears.
//

import SwiftUI

struct VinylOrderEntryView: View {
    let note: ProjectNote
    let authorName: String
    let teamMember: TeamMember?

    private var metadata: VinylOrderActivityMetadata? {
        VinylOrderActivityMetadata(json: note.contentMetadataJSON)
    }

    private var disposition: VinylOrderDisposition {
        metadata?.disposition ?? .supplier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let metadata {
                record(metadata)
            } else {
                // No structured payload — show exactly what was written.
                Text(note.content)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 14 / 28 are the feed's own card anatomy, matched verbatim from the
        // sibling entry cards (ActivityEntryView, AnnotationEntryView). There is
        // no 14pt spacing token; snapping to spacing3 would make this the one
        // card in the feed with a different inset.
        .padding(14)
        .glassSurface()
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if let teamMember {
                TeamMemberAvatar(teamMember: teamMember, size: 28)
            } else {
                Circle()
                    .fill(OPSStyle.Colors.background)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "shippingbox")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(authorName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(relativeTimestamp)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Text(disposition.activityTitle)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .tracking(0.8)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Record

    @ViewBuilder
    private func record(_ metadata: VinylOrderActivityMetadata) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if let color = metadata.color, !color.isEmpty {
                Text(color.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            if !metadata.vinylLines.isEmpty {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    ForEach(Array(metadata.vinylLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                    }
                }
            }

            ForEach(Array(metadata.consumables.enumerated()), id: \.offset) { _, consumable in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(consumable.label)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer(minLength: 0)
                        Text(consumable.value)
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                    }
                    if let shared = consumable.sharedSupportLine {
                        Text(shared)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.textMute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if metadata.vinylLines.isEmpty && metadata.consumables.isEmpty {
                Text(
                    disposition == .shop
                        ? "Nothing ordered — material came off the shop rack."
                        : "Marked ordered."
                )
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let po = metadata.po, !po.isEmpty {
                Text("PO \(po.uppercased())")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .monospacedDigit()
            }
        }
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
}
