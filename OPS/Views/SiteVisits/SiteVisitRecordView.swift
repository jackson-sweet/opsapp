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
            .padding(OPSStyle.Layout.spacing3)
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

/// Geometry that keeps the field document pinned to the sheet's real width.
/// Photo count is deliberately presentation input, but never affects the
/// document width: evidence scrolls inside a bounded rail instead of asking
/// SwiftUI for an ever-wider sheet.
struct SiteVisitRecordPresentationMetrics: Equatable {
    let availableWidth: CGFloat
    let photoCount: Int

    var documentWidth: CGFloat { max(.zero, availableWidth) }
    var photoTargetSize: CGFloat {
        max(PhotoThumbnail.tileSize, OPSStyle.Layout.touchTargetMin)
    }
    var showsEvidenceRail: Bool { photoCount > 0 }
}

/// The full site-visit record. Evidence gets a horizontal rail; the actual
/// field facts stay in one raised document with internal hairlines. Sections
/// still render only when the visit filled them.
struct SiteVisitRecordView: View {
    let record: SiteVisitRecord
    /// Tapping a thumbnail opens the viewer. Nil disables photo tap-through
    /// (a lead-side record has no project gallery to open into).
    var onPhotoTap: (([String], Int) -> Void)?

    private enum DocumentSection: Int, CaseIterable {
        case site, measurements, deck, checklist, notes, value
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        formatter.locale = BooksFormat.locale
        return formatter.string(from: record.capturedAt).uppercased()
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset = OPSStyle.Layout.spacing3_5
            let metrics = SiteVisitRecordPresentationMetrics(
                availableWidth: geometry.size.width - (horizontalInset * 2),
                photoCount: record.photoCount
            )

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    header

                    if metrics.showsEvidenceRail {
                        photosSection(metrics: metrics)
                    }

                    if hasDocumentContent {
                        document
                    } else if record.isEmpty {
                        emptyState
                    }

                    Spacer(minLength: OPSStyle.Layout.spacing5)
                }
                .frame(width: metrics.documentWidth, alignment: .leading)
                .padding(.horizontal, horizontalInset)
            }
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

            Text(record.operatorName.uppercased())
                .font(OPSStyle.Typography.section)
                .foregroundColor(OPSStyle.Colors.text)

            Text(dateLine)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()

            if let summary = record.summaryLine {
                Text(summary)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: Photos

    private func photosSection(metrics: SiteVisitRecordPresentationMetrics) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            documentLabel("PHOTOS")

            if record.photoURLs.isEmpty {
                Text("\(record.photoCount) NOT DOWNLOADED")
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .monospacedDigit()
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(Array(record.photoURLs.enumerated()), id: \.offset) { index, url in
                            photoTile(
                                url: url,
                                index: index,
                                targetSize: metrics.photoTargetSize
                            )
                        }
                    }
                }

                if record.missingPhotoCount > 0 {
                    Text("\(record.missingPhotoCount) NOT DOWNLOADED")
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func photoTile(url: String, index: Int, targetSize: CGFloat) -> some View {
        let thumbnail = PhotoThumbnail(url: url, project: nil, remoteThumbnailURL: nil)
            .frame(width: targetSize, height: targetSize)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(
                        OPSStyle.Colors.cardBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )

        if let onPhotoTap {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onPhotoTap(record.photoURLs, index)
            } label: {
                thumbnail
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("View photo \(index + 1) of \(record.photoURLs.count)")
        } else {
            thumbnail
                .accessibilityLabel("Photo \(index + 1) of \(record.photoURLs.count)")
        }
    }

    // MARK: Field document

    private var hasDocumentContent: Bool {
        DocumentSection.allCases.contains(where: shows)
    }

    private var document: some View {
        VStack(spacing: 0) {
            if shows(.site) {
                documentDivider(above: .site)
                siteSection
            }
            if shows(.measurements) {
                documentDivider(above: .measurements)
                measurementsSection
            }
            if shows(.deck) {
                documentDivider(above: .deck)
                deckSection
            }
            if shows(.checklist) {
                documentDivider(above: .checklist)
                checklistSection
            }
            if shows(.notes) {
                documentDivider(above: .notes)
                notesSection
            }
            // Money stays last and `record.value` is already permission-gated.
            if shows(.value) {
                documentDivider(above: .value)
                valueSection
            }
        }
        .commandCard()
    }

    private func shows(_ section: DocumentSection) -> Bool {
        switch section {
        case .site:
            return record.sections.contains(.identity) || record.sections.contains(.address)
        case .measurements:
            return record.sections.contains(.measurements)
        case .deck:
            return record.sections.contains(.deck)
        case .checklist:
            return record.sections.contains(.checklist)
        case .notes:
            return record.sections.contains(.notes)
        case .value:
            return record.sections.contains(.value)
        }
    }

    @ViewBuilder
    private func documentDivider(above section: DocumentSection) -> some View {
        if DocumentSection.allCases.prefix(section.rawValue).contains(where: shows) {
            Rectangle()
                .fill(OPSStyle.Colors.lineSoft)
                .frame(height: OPSStyle.Layout.Border.standard)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private var siteSection: some View {
        documentSection("SITE") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                if let identity = record.identityLine {
                    Text(identity)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let address = record.address {
                    Text(address.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var measurementsSection: some View {
        documentSection("MEASUREMENTS") {
            VStack(spacing: 0) {
                ForEach(Array(record.measurements.enumerated()), id: \.offset) { index, measurement in
                    factRow(label: measurement.label, value: measurement.value)

                    if index < record.measurements.count - 1 {
                        factDivider
                    }
                }
            }
        }
    }

    private var deckSection: some View {
        documentSection("DECK DESIGN") {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.grid)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                Text("DESIGN ATTACHED")
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.text2)
                Spacer(minLength: .zero)
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .accessibilityElement(children: .combine)
        }
    }

    private var checklistSection: some View {
        documentSection("CHECKLIST") {
            VStack(spacing: 0) {
                ForEach(Array(record.checklistItems.enumerated()), id: \.offset) { index, item in
                    checklistRow(item)

                    if index < record.checklistItems.count - 1 {
                        factDivider
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func checklistRow(_ item: SiteVisitRecord.ChecklistItem) -> some View {
        if let label = item.label {
            if item.prefersStackedPresentation {
                stackedFact(label: label, value: item.value)
            } else {
                ViewThatFits(in: .horizontal) {
                    inlineFact(label: label, value: item.value)
                    stackedFact(label: label, value: item.value)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.checkmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
                Text(item.value)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: .zero)
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var notesSection: some View {
        documentSection("NOTES") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(record.notes.enumerated()), id: \.offset) { index, text in
                    Text(text)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: OPSStyle.Layout.touchTargetMin,
                            alignment: .leading
                        )

                    if index < record.notes.count - 1 {
                        factDivider
                    }
                }
            }
        }
    }

    private var valueSection: some View {
        documentSection("VALUE") {
            Text(record.value ?? "")
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
                .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
        }
    }

    private func factRow(label: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            inlineFact(label: label, value: value)
            stackedFact(label: label, value: value)
        }
    }

    private func inlineFact(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            factLabel(label, keepsSingleLine: true)
            Spacer(minLength: OPSStyle.Layout.spacing2)
            Text(value)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .accessibilityElement(children: .combine)
    }

    private func stackedFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            factLabel(label, keepsSingleLine: false)
            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: OPSStyle.Layout.touchTargetMin,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }

    private func factLabel(_ label: String, keepsSingleLine: Bool) -> some View {
        Text(label)
            .font(OPSStyle.Typography.miniLabel)
            .textCase(.uppercase)
            .foregroundColor(OPSStyle.Colors.text3)
            .lineLimit(keepsSingleLine ? 1 : nil)
            .fixedSize(horizontal: keepsSingleLine, vertical: !keepsSingleLine)
    }

    private var factDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.lineSoft)
            .frame(height: OPSStyle.Layout.Border.standard)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("—")
                .font(OPSStyle.Typography.section)
                .foregroundColor(OPSStyle.Colors.text3)
            Text("// NOTHING CAPTURED")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .commandCard()
    }

    // MARK: Section chrome

    private func documentLabel(_ title: String) -> some View {
        Text("// \(title)")
            .font(OPSStyle.Typography.panelTitle)
            .foregroundColor(OPSStyle.Colors.text3)
    }

    private func documentSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            documentLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
    }
}
