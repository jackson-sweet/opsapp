//
//  LeadSiteVisitPanel.swift
//  OPS
//
//  The site visit on the expanded day-sheet card — one row in the artifact
//  zone, directly under the drawing. Photos, deck and visit are the same kind
//  of thing to a runner standing at the door: EVIDENCE of the job. He scans
//  them together, so they sit together, above the prose the agent wrote and
//  above the number he might dial.
//
//  Exactly one of three states renders, never a menu of all three:
//
//    • nothing on file       START SITE VISIT, routed to the ONE capture
//                            presentation the LEADS tab already owns
//                            (`activeSiteVisitLead`) — never a second cover.
//    • a visit still open    SITE VISIT · <when>; tapping resumes it, because
//                            `SiteVisitCaptureViewModel.loadOrCreateVisit`
//                            picks up this lead's open visit rather than
//                            starting a new one.
//    • a visit completed     VISITED · <when> plus what it captured, tapping
//                            through to the record.
//
//  ── Two honesty notes ───────────────────────────────────────────────────────
//  `SiteVisit` is LOCAL-ONLY — it never reaches Supabase (see the model, and
//  `SiteVisitCaptureViewModel.completeVisit`, which posts the timeline activity
//  app-side precisely because no DB trigger can). So this row speaks for the
//  DEVICE that did the capturing: a visit a teammate ran on their phone is not
//  on this one, and the row shows no visit rather than inventing one.
//
//  A visit's `status` is `.scheduled` from the moment it is created and nothing
//  in the app ever writes `scheduledAt` (`SiteVisitCaptureViewModel.createVisit`
//  sets neither), so "scheduled" means OPEN, not "booked for Tuesday". The row
//  says what is true: a date when one exists, otherwise how long the visit has
//  been sitting open.
//  ────────────────────────────────────────────────────────────────────────────
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3.4
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Date vocabulary

/// The day sheet's two date grammars, in one place.
///
/// `age` is the sheet's backward-looking token (NOW / 3H AGO / 2D AGO) — the
/// caption under a NEW lead, the stamp on the card's SUMMARY head. `day` is the
/// forward-looking one (TODAY / TMRW / FRI / AUG 4) — the tail of `BACK FRI` on
/// a parked lead, without the verb.
///
/// Both are `DaySheetViewModel`'s, to the character, so the site-visit row can
/// never drift into a third way of writing a date. The view model keeps its own
/// private copies — it is a pure transform that must stay free of view code —
/// so what this type actually collapses is the duplicate that was already
/// living inside `DaySheetLeadCard.summaryStamp`.
enum DaySheetDateToken {

    /// NOW / 3H AGO / 2D AGO — how long ago it happened.
    static func age(_ date: Date, now: Date = Date()) -> String {
        let hours = Int(now.timeIntervalSince(date) / 3600)
        if hours < 1 { return "NOW" }
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
    }

    /// TODAY / TMRW / FRI / AUG 4 — when it lands.
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days <= 0 { return "TODAY" }
        if days == 1 { return "TMRW" }
        if days < 7 { return weekdayFormatter.string(from: date).uppercased() }
        return monthDayFormatter.string(from: date).uppercased()
    }

    // en_US_POSIX so a row reads the same on every device locale — these are
    // OPS labels, not localized dates.
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

// MARK: - Panel

/// The row itself — deliberately dumb, like `LeadDeckPanel`: it takes a
/// resolved state and two closures. Resolution lives in
/// `LeadSiteVisitResolver`, so a preview or a snapshot harness renders any
/// state without a ModelContainer.
struct LeadSiteVisitPanel: View {

    /// What this lead's visit IS, already reduced to the strings the row
    /// prints. Tokens rather than dates on purpose: a harness renders a fixed
    /// string instead of something that reads differently depending on when the
    /// suite happens to run.
    enum State: Equatable {
        case absent
        case open(token: String)
        case completed(token: String, summary: String?)
    }

    let state: State
    /// Start or resume the capture. Nil when this operator holds no convert
    /// grant on this lead — a lead with no visit then renders NOTHING, because
    /// a button that can only refuse is worse than no button at all.
    var onCapture: (() -> Void)?
    /// Open the record. Only ever non-nil for `.completed`.
    var onOpenRecord: (() -> Void)?

    var body: some View {
        switch state {
        case .absent:
            if let onCapture {
                row(glyph: OPSStyle.Icons.camera,
                    title: "START SITE VISIT",
                    meta: nil,
                    action: onCapture,
                    spoken: "Start site visit")
            }

        case .open(let token):
            // Readable without a grant — that a visit is open on this lead is a
            // fact worth knowing — but tappable only with one.
            row(glyph: OPSStyle.Icons.camera,
                title: "SITE VISIT · \(token)",
                meta: onCapture == nil ? nil : "RESUME",
                action: onCapture,
                spoken: "Site visit open, \(token.lowercased())")

        case .completed(let token, let summary):
            // Reading a record needs no grant. Only capturing does.
            row(glyph: OPSStyle.Icons.checkmarkCircle,
                title: "VISITED · \(token)",
                meta: summary,
                action: onOpenRecord,
                spoken: spokenRecord(token: token, summary: summary))
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(
        glyph: String,
        title: String,
        meta: String?,
        action: (() -> Void)?,
        spoken: String
    ) -> some View {
        if let action {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                plate(glyph: glyph, title: title, meta: meta, showsChevron: true)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(spoken)
        } else {
            plate(glyph: glyph, title: title, meta: meta, showsChevron: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spoken)
        }
    }

    /// The artifact zone's one anatomy — `LeadDeckPanel`'s caption plate, so the
    /// drawing and the visit read as siblings rather than as two designers'
    /// work: L2 nested card (`surfaceInput` fill, `nestedBorder` hairline, r6),
    /// 44pt floor, identity left, affordance right. Neutral throughout — the
    /// milestone button owns the only accent on this screen.
    private func plate(
        glyph: String,
        title: String,
        meta: String?,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: glyph)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .regular))
                .foregroundColor(OPSStyle.Colors.text3)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(title)
                    .font(OPSStyle.Typography.buttonLabel)
                    .kerning(0.27)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Absent, never a dash: a visit that captured nothing says
                // nothing about what it captured.
                if let meta = meta, !meta.isEmpty {
                    Text(meta)
                        .font(OPSStyle.Typography.nanoLabel)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.nestedBorder,
                              lineWidth: OPSStyle.Layout.Border.standard)
        )
        .contentShape(Rectangle())
    }

    private func spokenRecord(token: String, summary: String?) -> String {
        let tail = summary.map { ", \($0.lowercased())" } ?? ""
        return "Site visit completed \(token.lowercased())\(tail)"
    }
}

// MARK: - Resolver

/// Production resolution, hosted for the card — the site-visit half of what
/// `DaySheetDeckResolver` does for the drawing, and only ever constructed for
/// the ONE open card.
///
/// Reads every visit and filters in Swift rather than predicating the fetch.
/// That is `SiteVisitCaptureViewModel.openVisits()`'s shape verbatim, and it is
/// the right one here: `opportunityId` is OPTIONAL (unlinked FAB visits carry
/// nil), optional comparisons inside `#Predicate` are the part of SwiftData
/// most likely to silently match nothing, and the table is device-local — a
/// runner's phone holds the visits he personally captured, not a company's
/// history.
struct LeadSiteVisitResolver: View {

    let opportunity: Opportunity
    var onCapture: (() -> Void)?

    @Query private var allVisits: [SiteVisit]

    /// Cancelled visits are not history — they are a visit that did not happen.
    /// Newest first, sorted here rather than in the query so the fetch stays
    /// the bare form the deck resolver already uses.
    private var attached: [SiteVisit] {
        allVisits
            .filter {
                $0.companyId == opportunity.companyId
                    && $0.opportunityId == opportunity.id
                    && $0.status != .cancelled
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// An open visit outranks a finished one: live work is what the runner has
    /// to act on, and the finished one is still reachable once he closes it.
    private var openVisit: SiteVisit? { attached.first { $0.completedAt == nil } }
    private var completedVisit: SiteVisit? { attached.first { $0.completedAt != nil } }

    var body: some View {
        if let openVisit = openVisit {
            LeadSiteVisitPanel(state: .open(token: Self.openToken(for: openVisit)),
                               onCapture: onCapture)
        } else if let completedVisit = completedVisit {
            LeadSiteVisitRecord(visit: completedVisit)
        } else {
            LeadSiteVisitPanel(state: .absent, onCapture: onCapture)
        }
    }

    /// A booked date when one exists; otherwise how long the visit has been
    /// open. Nothing in the app writes `scheduledAt` today — the age fallback
    /// IS the shipped path, and the date branch is here so a visit booked by
    /// any future surface reads correctly without a second row design.
    private static func openToken(for visit: SiteVisit) -> String {
        if let scheduled = visit.scheduledAt {
            return DaySheetDateToken.day(scheduled)
        }
        return DaySheetDateToken.age(visit.createdAt)
    }
}

// MARK: - Completed record

/// The completed visit, and the record behind it.
///
/// The summary line and the sheet both come from `SiteVisitPacketNote.build` —
/// the SHIPPED transform that turns a visit's local artifacts into the packet
/// the project activity feed renders. Going through it rather than counting
/// artifacts here means a lead's visit and a project's visit are described in
/// one vocabulary (`4 PHOTOS · 2 MEASUREMENTS · NOTES`) by one piece of code.
///
/// `SiteVisitPacketSheet` itself cannot be reused: it is initialized from a
/// `ProjectNote` and reads its photos from a `@Query<ProjectPhoto>` filtered by
/// `projectId`. A lead has no project, and its visit photos are still local
/// files, so the sheet below renders the same sections from the artifacts.
private struct LeadSiteVisitRecord: View {

    let visit: SiteVisit

    @Query private var artifacts: [SiteVisitCaptureArtifact]
    @Query private var answers: [SiteVisitChecklistAnswer]
    @State private var showingRecord = false

    init(visit: SiteVisit) {
        self.visit = visit
        let visitId = visit.id
        _artifacts = Query(
            filter: #Predicate<SiteVisitCaptureArtifact> { $0.siteVisitId == visitId }
        )
        _answers = Query(
            filter: #Predicate<SiteVisitChecklistAnswer> { $0.siteVisitId == visitId }
        )
    }

    var body: some View {
        LeadSiteVisitPanel(
            state: .completed(token: completedToken, summary: summaryLine),
            onOpenRecord: { showingRecord = true }
        )
        .sheet(isPresented: $showingRecord) {
            LeadSiteVisitRecordSheet(
                visit: visit,
                photoArtifacts: photoArtifacts,
                metadata: metadata
            )
        }
    }

    private var completedToken: String {
        DaySheetDateToken.age(visit.completedAt ?? visit.createdAt)
    }

    private var summaryLine: String? {
        guard let line = metadata?.summaryLine, !line.isEmpty else { return nil }
        return line
    }

    /// Re-derived per evaluation rather than cached. The visit's artifacts are
    /// a handful of local rows and only ONE card is ever open, so a JSON
    /// round-trip here costs less than a second source of truth for what a
    /// visit captured.
    private var metadata: SiteVisitPacketMetadata? {
        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: visit.id,
            opportunityId: visit.opportunityId ?? "",
            address: visit.address,
            artifacts: artifacts,
            checklistAnswers: answers
        )
        guard let packet = SiteVisitPacketNote.build(artifacts: artifacts, payload: payload)
        else { return nil }
        return SiteVisitPacketMetadata.decode(from: packet.metadataJSON)
    }

    /// The same set the packet counted, in the same order, so the strip and the
    /// `N PHOTOS` it is labelled with can never disagree.
    private var photoArtifacts: [SiteVisitCaptureArtifact] {
        artifacts
            .filter { $0.isActive && $0.includedInProjectReview && $0.pipesToProjectPhotos }
            .sorted { $0.capturedAt < $1.capturedAt }
    }
}

// MARK: - Record sheet

/// What the visit captured, for a lead that has not become a project yet.
/// `SiteVisitPacketSheet`'s sections, its order and its labels; the photos come
/// from the visit's own local assets, because that is where they still live.
private struct LeadSiteVisitRecordSheet: View {

    let visit: SiteVisit
    let photoArtifacts: [SiteVisitCaptureArtifact]
    let metadata: SiteVisitPacketMetadata?

    @State private var preview: PreviewAsset?

    private struct PreviewAsset: Identifiable {
        let id = UUID()
        let url: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header

                if !photoArtifacts.isEmpty {
                    packetSection(title: "// PHOTOS") { photoStrip }
                }

                if let measurements = metadata?.measurements, !measurements.isEmpty {
                    packetSection(title: "// MEASUREMENTS") {
                        measurementList(measurements)
                    }
                }

                if let notes = metadata?.notes, !notes.isEmpty {
                    packetSection(title: "// NOTES") { noteList(notes) }
                }

                if let checklist = metadata?.checklist, !checklist.isEmpty {
                    packetSection(title: "// CHECKLIST") { checklistList(checklist) }
                }

                // A completed visit with nothing left to show (every artifact
                // deleted) says so, rather than presenting an empty scroll.
                if isEmptyRecord {
                    Text("// NOTHING CAPTURED")
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(1.6)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: OPSStyle.Layout.spacing4)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $preview) { asset in
            photoViewer(asset)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("SITE VISIT")
                .font(OPSStyle.Typography.section)
                .foregroundColor(OPSStyle.Colors.text)
            Text(dateLine)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
        }
        .padding(.top, OPSStyle.Layout.spacing3)
        .accessibilityElement(children: .combine)
    }

    private var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy · h:mm a"
        return formatter.string(from: visit.completedAt ?? visit.createdAt).uppercased()
    }

    // MARK: Sections

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(photoArtifacts, id: \.id) { artifact in
                    Button {
                        guard let url = artifact.previewAssetURL else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        preview = PreviewAsset(url: url)
                    } label: {
                        LeadSiteVisitArtifactThumbnail(artifact: artifact)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(artifact.previewAssetURL == nil)
                    .accessibilityLabel("Site visit photo")
                }
            }
        }
    }

    private func measurementList(
        _ measurements: [SiteVisitPacketMetadata.Measurement]
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(measurements.enumerated()), id: \.offset) { index, measurement in
                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2_5) {
                    Text(measurement.label)
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(OPSStyle.Colors.text)
                    Spacer(minLength: 0)
                    Text(measurement.value)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                .padding(.vertical, OPSStyle.Layout.spacing2)

                if index < measurements.count - 1 {
                    Rectangle()
                        .fill(OPSStyle.Colors.lineSoft)
                        .frame(height: OPSStyle.Layout.Border.standard)
                }
            }
        }
    }

    private func noteList(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func checklistList(_ checklist: [String]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            ForEach(Array(checklist.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.checkmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.olive)
                    Text(line)
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(OPSStyle.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func packetSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.miniLabelBold)
                .tracking(1.2)
                .foregroundColor(OPSStyle.Colors.text3)
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.nestedBorder,
                              lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: Photo viewer

    private func photoViewer(_ asset: PreviewAsset) -> some View {
        ZStack(alignment: .topLeading) {
            OPSStyle.Colors.background.ignoresSafeArea()
            ZoomablePhotoView(url: asset.url)
                .ignoresSafeArea()
            Button {
                preview = nil
            } label: {
                Text("CLOSE")
                    .font(OPSStyle.Typography.buttonLabel)
                    .kerning(0.27)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(minWidth: OPSStyle.Layout.touchTargetMin,
                           minHeight: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .preferredColorScheme(.dark)
    }

    private var isEmptyRecord: Bool {
        photoArtifacts.isEmpty
            && (metadata?.measurements?.isEmpty ?? true)
            && (metadata?.notes?.isEmpty ?? true)
            && (metadata?.checklist?.isEmpty ?? true)
    }
}

// MARK: - Artifact thumbnail

/// A visit photo still living on this device. Loads through the SAME pair the
/// capture console's own thumbnail uses — composited render first (a photo the
/// operator marked up shows the markup), raw local asset second.
private struct LeadSiteVisitArtifactThumbnail: View {

    let artifact: SiteVisitCaptureArtifact

    private static let side: CGFloat = 72

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceHover)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: OPSStyle.Icons.camera)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .light))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.nestedBorder,
                              lineWidth: OPSStyle.Layout.Border.standard)
        )
        .task(id: artifact.previewAssetURL ?? artifact.id) {
            guard let url = artifact.previewAssetURL else {
                image = nil
                return
            }
            image = ImageFileManager.shared.loadCompositedImage(forURL: url)
                ?? ImageFileManager.shared.loadImage(localID: url)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadSiteVisitPanel / states") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            LeadSiteVisitPanel(state: .absent, onCapture: {})
            LeadSiteVisitPanel(state: .open(token: "3H AGO"), onCapture: {})
            LeadSiteVisitPanel(state: .open(token: "TMRW"))
            LeadSiteVisitPanel(
                state: .completed(token: "2D AGO",
                                  summary: "4 PHOTOS · 2 MEASUREMENTS · NOTES"),
                onOpenRecord: {}
            )
        }
        .padding(OPSStyle.Layout.spacing3_5)
    }
    .preferredColorScheme(.dark)
}
#endif
