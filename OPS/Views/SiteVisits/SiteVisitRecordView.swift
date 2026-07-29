//
//  SiteVisitRecordView.swift
//  OPS
//
//  The SITE VISIT RECORD — what came back from site, rendered as a field
//  document rather than a feed post.
//
//  Two presentations over one assembled `SiteVisitRecord`:
//
//    SiteVisitRecordCard — the compact row that sits in an activity feed. Who
//      went, when, and the capture tally. Enough to decide whether to open it.
//
//    SiteVisitRecordView — the full record. A tactical `// SITE VISIT` header,
//      then only the sections the visit actually filled: identity, address,
//      photos, measurements, deck, checklist, notes, value.
//
//  Everything renders from `SiteVisitRecord`, which has already applied the
//  financial-visibility filter — so no view here can leak a number a viewer is
//  not cleared for. There is no "hidden" affordance to find: a restricted
//  viewer sees a record that simply has no money in it.
//
//  Native SwiftUI, not a bitmap: the record stays crisp at any size, inherits
//  the design system, and reads correctly under Dynamic Type.
//

import SwiftUI

// MARK: - Compact card

/// Activity-feed card for a completed site visit. Header grammar matches the
/// other feed cards (avatar · name + timestamp · action line) so the feed
/// still scans as one column; the tan SITE VISIT tag and the mono capture
/// tally are what mark it as a record.
struct SiteVisitRecordCard: View {
    let record: SiteVisitRecord
    let teamMember: TeamMember?
    var onOpen: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                header

                if let identity = record.identityLine {
                    Text(identity)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let summary = record.summaryLine {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(summary)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: OPSStyle.Layout.spacing1)
                        Image(systemName: OPSStyle.Icons.chevronRight)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if let teamMember {
                TeamMemberAvatar(teamMember: teamMember, size: 28)
            } else {
                Circle()
                    .fill(OPSStyle.Colors.surfaceInput)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(String(record.operatorName.prefix(1)).uppercased())
                            .font(OPSStyle.Typography.status)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(record.operatorName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Text(ActivityRelativeTimestamp.string(from: record.capturedAt))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
                Text("completed a site visit")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            SiteVisitRecordTag()
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(record.operatorName) completed a site visit"]
        if let identity = record.identityLine { parts.append(identity.lowercased()) }
        if let summary = record.summaryLine { parts.append(summary.lowercased()) }
        return parts.joined(separator: ", ")
    }
}

/// The record's mark. Tan is the site-visit semantic tone — never the steel
/// accent, which belongs to the screen's primary action.
struct SiteVisitRecordTag: View {
    var body: some View {
        Text("SITE VISIT")
            .font(OPSStyle.Typography.status)
            .foregroundColor(OPSStyle.Colors.tanTextM)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(OPSStyle.Colors.tanFillM)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.tanLineM, lineWidth: 1)
            )
            .cornerRadius(OPSStyle.Layout.chipRadius)
            .accessibilityHidden(true)
    }
}

// MARK: - Full record

/// The full site-visit record. Sections render only when the visit filled
/// them — a record of a photos-only walkthrough is a header and a photo strip,
/// not a page of empty headings.
struct SiteVisitRecordView: View {
    let record: SiteVisitRecord
    /// Tapping a thumbnail opens the viewer. Nil disables photo tap-through
    /// (a lead-side record has no project gallery to open into).
    var onPhotoTap: (([String], Int) -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        formatter.locale = BooksFormat.locale
        return formatter.string(from: record.capturedAt).uppercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header

                if record.sections.contains(.identity) || record.sections.contains(.address) {
                    siteBlock
                }

                if record.sections.contains(.photos) { photosSection }
                if record.sections.contains(.measurements) { measurementsSection }
                if record.sections.contains(.deck) { deckSection }
                if record.sections.contains(.checklist) { checklistSection }
                if record.sections.contains(.notes) { notesSection }
                // Money renders last and only when the viewer is cleared for
                // it — `record.value` is already nil otherwise.
                if record.sections.contains(.value) { valueSection }

                if record.isEmpty { emptyState }

                Spacer(minLength: OPSStyle.Layout.spacing5)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("// SITE VISIT")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.textMute)
                .kerning(1.6)

            Text(record.operatorName.uppercased())
                .font(OPSStyle.Typography.section)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(dateLine)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .monospacedDigit()

            if let summary = record.summaryLine {
                Text(summary)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .kerning(1.2)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: Site (identity + address)

    private var siteBlock: some View {
        section("// SITE") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                if let identity = record.identityLine {
                    Text(identity)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let address = record.address {
                    Text(address.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Photos

    private var photosSection: some View {
        section("// PHOTOS") {
            if record.visiblePhotoURLs.isEmpty {
                // The count travelled with the record but the images have not
                // reached this device yet. Say so in numbers, not apology.
                Text("\(record.photoCount) NOT DOWNLOADED")
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .kerning(1.2)
                    .monospacedDigit()
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(Array(record.visiblePhotoURLs.enumerated()), id: \.element) { index, url in
                        Button {
                            guard let onPhotoTap else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onPhotoTap(record.visiblePhotoURLs, index)
                        } label: {
                            PhotoThumbnail(url: url, project: nil, remoteThumbnailURL: nil)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(onPhotoTap == nil)
                    }

                    if record.additionalPhotoCount > 0 {
                        Text("+\(record.additionalPhotoCount)")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .monospacedDigit()
                            .frame(width: 72, height: 72)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .fill(OPSStyle.Colors.surfaceInput)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Measurements

    private var measurementsSection: some View {
        section("// MEASUREMENTS") {
            VStack(spacing: 0) {
                ForEach(Array(record.measurements.enumerated()), id: \.offset) { index, measurement in
                    HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                        Text(measurement.label.uppercased())
                            .font(OPSStyle.Typography.miniLabel)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .kerning(1.2)
                        Spacer(minLength: OPSStyle.Layout.spacing2)
                        Text(measurement.value)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing2)

                    if index < record.measurements.count - 1 {
                        Rectangle()
                            .fill(OPSStyle.Colors.line)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: Deck

    private var deckSection: some View {
        section("// DECK DESIGN") {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                Text("DESIGN ATTACHED")
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .kerning(1.2)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Checklist

    private var checklistSection: some View {
        section("// CHECKLIST") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                ForEach(Array(record.checklist.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "checkmark")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.oliveTextM)
                        Text(line)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Notes

    private var notesSection: some View {
        section("// NOTES") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                ForEach(Array(record.notes.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Value (financial — permission-filtered upstream)

    private var valueSection: some View {
        section("// VALUE") {
            Text(record.value ?? "")
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .monospacedDigit()
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("—")
                .font(OPSStyle.Typography.section)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("// NOTHING CAPTURED")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.textMute)
                .kerning(1.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, OPSStyle.Layout.spacing4)
    }

    // MARK: Section chrome

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .kerning(1.4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassSurface()
    }
}
