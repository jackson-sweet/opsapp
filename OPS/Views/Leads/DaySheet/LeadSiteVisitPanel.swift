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
//  `SiteVisit` reaches Supabase: `SiteVisitRepository` (`site_visits`),
//  `SiteVisitOutboundSync`, and a realtime subscription on that table. So a
//  visit a teammate ran on their phone DOES arrive here once it syncs, and this
//  row reads whatever the local store holds rather than speaking only for the
//  capturing device. (`SiteVisitCaptureViewModel.completeVisit` still posts the
//  timeline activity app-side — no DB trigger does it.) Until a visit syncs,
//  the row shows no visit rather than inventing one.
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
        /// A real appointment (`bookedAt` non-nil, still scheduled) — the row
        /// leads with the commitment, not the verb: `BOOKED — THU 10:30AM`.
        case booked(token: String)
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

        case .booked(let token):
            // The appointment IS the row. Pressing raises the same NOW/BOOK
            // branch as the verb — start early, or move/cancel the booking.
            row(glyph: OPSStyle.Icons.calendar,
                title: "BOOKED — \(token)",
                meta: nil,
                action: onCapture,
                spoken: "Site visit booked, \(token.lowercased())")

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
            if openVisit.isBookedAppointment,
               openVisit.status == .scheduled,
               let scheduledAt = openVisit.scheduledAt {
                LeadSiteVisitPanel(
                    state: .booked(token: SiteVisitBookingLookup.bookedToken(for: scheduledAt)),
                    onCapture: onCapture
                )
            } else {
                LeadSiteVisitPanel(state: .open(token: Self.openToken(for: openVisit)),
                                   onCapture: onCapture)
            }
        } else if let completedVisit = completedVisit {
            LeadSiteVisitRecord(visit: completedVisit, opportunity: opportunity)
        } else {
            LeadSiteVisitPanel(state: .absent, onCapture: onCapture)
        }
    }

    /// How long the visit has been open. Booked visits never reach here (they
    /// render `.booked` above), and an unbooked visit's `scheduledAt` is junk
    /// by definition — the legacy guard: never trust a date without
    /// `bookedAt`, so the age token is the only honest open-row grammar.
    private static func openToken(for visit: SiteVisit) -> String {
        DaySheetDateToken.age(visit.createdAt)
    }
}

// MARK: - Completed record

/// The completed visit, and the record behind it.
///
/// The packet still comes from `SiteVisitPacketNote.build` — the SHIPPED
/// transform that turns a visit's local artifacts into what the project
/// activity feed renders — and the summary line comes from `SiteVisitRecord`,
/// which now owns that vocabulary. Going through both rather than counting
/// artifacts here means a lead's visit and a project's visit are described in
/// one vocabulary (`4 PHOTOS · 2 MEASUREMENTS · NOTES`) by one piece of code.
///
/// Lead and project records now share one sheet. The assembler supplies local
/// artifact URLs here and synced project-photo URLs after conversion; the
/// presentation and deck action cannot drift between the two surfaces.
private struct LeadSiteVisitRecord: View {

    let visit: SiteVisit
    let opportunity: Opportunity

    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var artifacts: [SiteVisitCaptureArtifact]
    @Query private var answers: [SiteVisitChecklistAnswer]
    @Query private var identityDrafts: [SiteVisitIdentityDraft]
    @Query private var recorders: [TeamMember]
    @State private var showingRecord = false

    init(visit: SiteVisit, opportunity: Opportunity) {
        self.visit = visit
        self.opportunity = opportunity
        let visitId = visit.id
        let recorderId = visit.createdBy ?? ""
        _artifacts = Query(
            filter: #Predicate<SiteVisitCaptureArtifact> { $0.siteVisitId == visitId }
        )
        _answers = Query(
            filter: #Predicate<SiteVisitChecklistAnswer> { $0.siteVisitId == visitId }
        )
        _identityDrafts = Query(
            filter: #Predicate<SiteVisitIdentityDraft> { $0.siteVisitId == visitId }
        )
        _recorders = Query(filter: #Predicate<TeamMember> { $0.id == recorderId })
    }

    private var recorder: TeamMember? { recorders.first }

    private var operatorName: String {
        recorder?.fullName ?? "Team Member"
    }

    private var record: SiteVisitRecord {
        SiteVisitRecord.assembleFromLocalCapture(
            visit: visit,
            artifacts: artifacts,
            checklistAnswers: answers,
            identity: identityDrafts.first,
            opportunity: opportunity,
            capturedAt: visit.completedAt ?? visit.createdAt,
            operatorName: operatorName,
            canViewFinancials: permissionStore.can("finances.view")
        ) ?? SiteVisitRecord.assemble(
            metadata: nil,
            photoURLs: visit.photos,
            capturedAt: visit.completedAt ?? visit.createdAt,
            operatorName: operatorName,
            estimatedValue: opportunity.estimatedValue,
            canViewFinancials: permissionStore.can("finances.view")
        )
    }

    var body: some View {
        LeadSiteVisitPanel(
            state: .completed(
                token: DaySheetDateToken.age(visit.completedAt ?? visit.createdAt),
                summary: record.summaryLine
            ),
            onOpenRecord: { showingRecord = true }
        )
        .sheet(isPresented: $showingRecord) {
            SiteVisitRecordSheet(
                record: record,
                opportunityId: opportunity.id,
                companyId: opportunity.companyId,
                deckTitle: opportunity.deckDesignTitle
            )
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
            LeadSiteVisitPanel(state: .booked(token: "THU 10:30AM"), onCapture: {})
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
