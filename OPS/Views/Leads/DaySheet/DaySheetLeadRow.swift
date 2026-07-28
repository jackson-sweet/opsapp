//
//  DaySheetLeadRow.swift
//  OPS
//
//  The day sheet's collapsed lead row — the scan surface. One line of sight:
//  what the job looks like (thumb), who it is, where it is, where it stands
//  (stage), and whose move it is (urgency). Two verbs and nothing else: the
//  runner is either calling this lead or driving to it. Everything that
//  authors, logs, or stamps lives in the expanded card behind a tap.
//
//  Press grammar:
//    • anywhere on the row     → expand (accordion, owned by the screen)
//    • the stage chip, tapped  → expand too (it is part of the row)
//    • the stage chip, held    → LeadStatusMenu, for honest corrections
//    • CALL / ROUTE            → their own 44pt targets, never the row
//
//  Deviation from the plan's letter, deliberately: the row is NOT wrapped in a
//  `Button`. A Button is a single leaf accessibility element, which would
//  swallow the CALL / ROUTE / stage-chip labels that spec §7 requires and
//  contradicts the `children: .contain` container this row must be. The
//  shipped `LeadTriageCard` mechanism — `contentShape` + `onTapGesture`, with
//  real Buttons as children — gives the same full-row tap while keeping every
//  control individually hit-testable and individually voiced, plus an explicit
//  VoiceOver action for the expand itself.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3.3
//

import SwiftUI
import UIKit

struct DaySheetLeadRow: View {

    let row: DaySheetViewModel.Row
    let canEdit: Bool
    let canConvert: Bool
    /// Accordion state, owned by the screen. The collapsed row looks the same
    /// either way — this only tells VoiceOver whether the card below is open.
    var isExpanded: Bool = false
    /// Set by `DaySheetLeadCard`, which owns the L1 shell for the whole
    /// accordion (face + expanded body under ONE glass panel and ONE clip).
    /// A row rendering its own card inside that shell would draw a second
    /// hairline across the seam. Default `false` keeps the standalone row —
    /// previews, harnesses, and any future non-accordion host — unchanged.
    var embedded: Bool = false
    var onExpand: () -> Void = {}
    // Stage-chip menu routing — wired by the screen.
    var onStage: (PipelineStage) -> Void = { _ in }
    var onWon: () -> Void = {}
    var onLost: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDiscard: () -> Void = {}

    /// Spec §3.3 — 80pt minimum row, the thumb plus breathing room.
    static let minHeight: CGFloat = 80

    /// Disabled icon controls stay legible-but-spent rather than vanishing, so
    /// the row's geometry never shifts between leads (ContactChipButton).
    private static let disabledOpacity: Double = 0.35

    private var lead: Opportunity { row.lead }

    var body: some View {
        // `spacing2` between the three blocks, and a Spacer that can collapse:
        // the row's fixed furniture (56pt tile, 88pt of touch targets, the
        // card's own padding) already claims more than half a 390pt screen, and
        // every point spent on air here is a point the stage chip does not get.
        // The identity block still clears the rule by 16pt (8 + 8).
        HStack(spacing: OPSStyle.Layout.spacing2) {
            LeadThumbView(lead: lead)

            identity

            Spacer(minLength: 0)

            trailing
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .frame(minHeight: Self.minHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(DaySheetRowShell(embedded: embedded))
        .contentShape(Rectangle())
        .onTapGesture { onExpand() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityAction(named: Text("Expand")) { onExpand() }
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(lead.displayContactName)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)
                .truncationMode(.tail)

            // No address, no line — a placeholder dash on a scan surface is
            // noise the operator has to read past.
            if let address = trimmedAddress {
                Text(address)
                    .font(OPSStyle.Typography.miniLabel)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            chips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chips (stage · urgency)

    /// Both chips are `.fixedSize()`: a chip that ellipsizes (`NEGOTIATI… · 6D`)
    /// has stopped being a token and started being a sentence fragment. The
    /// name and address lines above absorb the compression instead — they are
    /// prose, and prose truncates honestly.
    ///
    /// Which means the pair needs a way to give ground that is NOT truncation,
    /// or the row overflows its card on a 390pt phone (fixed furniture eats
    /// everything but ~120pt, and `QUOTED · 6D` + `3D LATE` wants ~175). The
    /// ladder spends the row's real width from the top down:
    ///
    ///   1. `QUOTED · 6D` + `3D LATE`   — everything, on a wide device
    ///   2. `QUOTED` + `3D LATE`        — the qualifier goes first; the spec
    ///                                    already treats it as optional (it is
    ///                                    omitted under a day), and the exact
    ///                                    age is one tap away in the card
    ///   3. `3D LATE`                   — last resort: the token the sheet is
    ///                                    ORDERED by always survives
    ///
    /// `ViewThatFits` picks the richest rung the actual width allows, so the
    /// same row shows more on a Pro Max than on a mini without a geometry read
    /// or a hardcoded breakpoint.
    private var chips: some View {
        ViewThatFits(in: .horizontal) {
            chipRow(detail: stageDetail, showsStage: true)
            chipRow(detail: nil, showsStage: true)
            chipRow(detail: nil, showsStage: false)
        }
    }

    private func chipRow(detail: String?, showsStage: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if showsStage {
                stageChip(detail: detail)
                    .fixedSize()
            }
            urgencyChip
                .fixedSize()
        }
    }

    /// The stage chip is neutralized here: on the day sheet urgency owns the
    /// only colour in the row, so a tan QUOTED chip would compete with the tan
    /// TODAY token sitting beside it.
    private func stageChip(detail: String?) -> some View {
        LeadStatusMenu(
            lead: lead,
            canEdit: canEdit,
            canConvert: canConvert,
            onStage: onStage,
            onWon: onWon,
            onLost: onLost,
            onArchive: onArchive,
            onDiscard: onDiscard,
            primaryAction: onExpand
        ) {
            StageTag(
                stage: lead.stage,
                detail: detail,
                showsChevron: canEdit || canConvert,
                neutralized: true,
                compact: true
            )
        }
    }

    /// Days-in-stage under a day reads as noise (`QUOTED · 0D`) — omit it.
    private var stageDetail: String? {
        lead.daysInStage >= 1 ? "\(lead.daysInStage)D" : nil
    }

    @ViewBuilder
    private var urgencyChip: some View {
        switch row.urgency {
        case .late(let days):
            ToneTag("\(days)D LATE", tone: .rose)
        case .today:
            ToneTag("TODAY", tone: .tan)
        case .yourMove:
            ToneTag("YOUR MOVE", tone: .neutral)
        case .newLead(let age):
            // NEW and WAITING are facts, not calls to action — plain mono, no
            // chip, so a chip in this row always means "act" (spec §3.2).
            plainToken(age)
        case .waiting(let back):
            if let back {
                plainToken(back)
            }
        }
    }

    private func plainToken(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.nanoLabel)
            .tracking(0.8)
            .foregroundColor(OPSStyle.Colors.text3)
            .monospacedDigit()
    }

    // MARK: - Trailing (rule · call · route)

    /// The rule and the two verbs are ONE block, hugging: at a real list width
    /// (390pt device minus the 20pt gutters) the row's fixed furniture — 56pt
    /// thumb, 88pt of touch targets, card padding — leaves the chips barely
    /// more than a hundred points. Four separate 12pt gaps out here were
    /// spending that budget on air, and the row overflowed its own card.
    private var trailing: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Rectangle()
                .fill(OPSStyle.Colors.lineSoft)
                .frame(width: OPSStyle.Layout.Border.standard,
                       height: OPSStyle.Layout.touchTargetMin)

            verbs
        }
    }

    // MARK: - Verbs (call · route)

    private var verbs: some View {
        HStack(spacing: 0) {
            DaySheetVerbButton(
                icon: OPSStyle.Icons.phone,
                isEnabled: hasPhone,
                tint: OPSStyle.Colors.text2,
                dimsWhenDisabled: true,
                disabledOpacity: Self.disabledOpacity,
                label: "CALL \(lead.displayContactName)",
                hint: "Unavailable — no phone number on file",
                action: placeCall
            )

            DaySheetVerbButton(
                icon: OPSStyle.Icons.route,
                isEnabled: canRoute,
                // A route with nowhere to go dims the glyph rather than the
                // control — the address line is already absent above it.
                tint: canRoute ? OPSStyle.Colors.text2 : OPSStyle.Colors.textMute,
                dimsWhenDisabled: false,
                disabledOpacity: Self.disabledOpacity,
                label: trimmedAddress.map { "DIRECTIONS TO \($0)" } ?? "DIRECTIONS",
                hint: "Unavailable — no address on file",
                action: openRoute
            )
        }
    }

    /// CALL keeps the shipped around-call contract verbatim
    /// (`LeadTriageCard.placeCall`): record the outbound intent only when this
    /// operator can edit the lead, then dial. The post-call prompt / auto-log
    /// picks it up on return.
    private func placeCall() {
        guard hasPhone else { return }
        if PermissionStore.shared.isFeatureEnabled("pipeline"), canEdit {
            CallLogStore.shared.recordOutbound(
                opportunityId: lead.id,
                contactName: lead.contactName,
                phone: lead.contactPhone ?? sanitizedPhone
            )
        }
        guard let url = URL(string: "tel:\(sanitizedPhone)") else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIApplication.shared.open(url)
    }

    /// Coordinates when we have them (exact, no lookup), else the address
    /// string as a query — Apple Maps resolves it the same way the operator
    /// would by typing it.
    private func openRoute() {
        guard let url = routeURL else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIApplication.shared.open(url)
    }

    private var routeURL: URL? {
        if let latitude = lead.latitude, let longitude = lead.longitude {
            return URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)")
        }
        guard let address = trimmedAddress,
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(encoded)")
    }

    // MARK: - Derived

    private var canRoute: Bool {
        (lead.latitude != nil && lead.longitude != nil) || trimmedAddress != nil
    }

    private var hasPhone: Bool {
        guard let phone = lead.contactPhone else { return false }
        return !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sanitizedPhone: String {
        (lead.contactPhone ?? "").filter { "0123456789+".contains($0) }
    }

    private var trimmedAddress: String? {
        guard let address = lead.address?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty
        else { return nil }
        return address
    }

    /// Spoken form mirrors the printed token — a runner listening to the sheet
    /// and a runner reading it are told the same thing.
    private var accessibilityLabelText: String {
        "\(lead.displayContactName), \(lead.stage.displayName), \(spokenUrgency)"
    }

    private var spokenUrgency: String {
        switch row.urgency {
        case .late(let days):   return "\(days) day\(days == 1 ? "" : "s") late"
        case .today:            return "due today"
        case .yourMove:         return "your move"
        case .newLead(let age): return "new \(age.lowercased())"
        case .waiting(let back): return back?.lowercased() ?? "waiting"
        }
    }
}

// MARK: - Row shell

/// The row's own L1 glass panel — present when the row stands alone, absent
/// when `DaySheetLeadCard` has already drawn one around the whole accordion.
private struct DaySheetRowShell: ViewModifier {
    let embedded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .commandCard()
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius,
                                            style: .continuous))
        }
    }
}

// MARK: - Verb button (44pt icon control)

/// One trailing verb — 20pt glyph in a 44pt target. CALL dims the whole
/// control when there is no number (ContactChipButton treatment); ROUTE dims
/// only its glyph. Both stay in the VoiceOver tree with a reason.
private struct DaySheetVerbButton: View {
    let icon: String
    let isEnabled: Bool
    let tint: Color
    let dimsWhenDisabled: Bool
    let disabledOpacity: Double
    let label: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .regular))
                .foregroundColor(tint)
                .frame(width: OPSStyle.Layout.touchTargetMin,
                       height: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || !dimsWhenDisabled ? 1.0 : disabledOpacity)
        .accessibilityLabel(label)
        .accessibilityHint(isEnabled ? "" : hint)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("DaySheetLeadRow / urgency variants") {
    ScrollView {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            // LATE — the loudest row on the sheet.
            DaySheetLeadRow(
                row: DaySheetViewModel.Row(
                    lead: {
                        let lead = Opportunity.preview(
                            title: "Roof tear-off — 28 sq", contactName: "Marcus Webb",
                            stage: .quoting, estimatedValue: 14_200, daysInStage: 5
                        )
                        lead.address = "1841 Beckwith Ave, Burnaby"
                        lead.contactPhone = "604-555-0142"
                        return lead
                    }(),
                    urgency: .late(days: 3),
                    milestone: .quoteSent
                ),
                canEdit: true,
                canConvert: true
            )

            // TODAY — with a photo thumb + count badge.
            DaySheetLeadRow(
                row: DaySheetViewModel.Row(
                    lead: {
                        let lead = Opportunity.preview(
                            title: "Window install — 8 units", contactName: "The Hensons",
                            stage: .quoted, estimatedValue: 11_800, daysInStage: 3
                        )
                        lead.address = "22 Wharf Road, North Vancouver"
                        lead.contactPhone = "604-555-0199"
                        lead.images = [
                            "https://example.com/a.jpg",
                            "https://example.com/b.jpg",
                            "https://example.com/c.jpg"
                        ]
                        return lead
                    }(),
                    urgency: .today,
                    milestone: .won
                ),
                canEdit: true,
                canConvert: true
            )

            // YOUR MOVE — coordinates only, so the thumb is the map tile.
            DaySheetLeadRow(
                row: DaySheetViewModel.Row(
                    lead: {
                        let lead = Opportunity.preview(
                            title: "Gutter replacement — 140 lf", contactName: "Dana Ruiz",
                            stage: .followUp, daysInStage: 4
                        )
                        lead.latitude = 49.2827
                        lead.longitude = -123.1207
                        lead.contactPhone = "604-555-0177"
                        return lead
                    }(),
                    urgency: .yourMove,
                    milestone: .won
                ),
                canEdit: true,
                canConvert: true
            )

            // NEW — plain age token, no chip.
            DaySheetLeadRow(
                row: DaySheetViewModel.Row(
                    lead: {
                        let lead = Opportunity.preview(
                            title: "Leak repair — kitchen ceiling", contactName: "Jamie Park",
                            stage: .newLead, daysInStage: 0
                        )
                        lead.address = "310 Alder St, Vancouver"
                        lead.contactPhone = "604-555-0108"
                        return lead
                    }(),
                    urgency: .newLead(age: "3H AGO"),
                    milestone: .contacted
                ),
                canEdit: true,
                canConvert: true
            )

            // WAITING, viewer scope — no menu chevron, both verbs spent.
            DaySheetLeadRow(
                row: DaySheetViewModel.Row(
                    lead: Opportunity.preview(
                        title: "Cedar Ridge roof", contactName: "Cedar Ridge HOA",
                        stage: .negotiation, daysInStage: 6
                    ),
                    urgency: .waiting(back: "BACK FRI"),
                    milestone: nil
                ),
                canEdit: false,
                canConvert: false
            )
        }
        .padding(OPSStyle.Layout.spacing3_5)
    }
    .background(OPSStyle.Colors.background)
    .leadsPreviewEnvironment()
}
#endif
