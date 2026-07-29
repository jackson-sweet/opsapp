//
//  DetailHero.swift
//  OPS
//
//  Top hero block on LeadDetailView — the dossier head (Leads redesign
//  spec §5): the job as the header, the people under it, and the three
//  numbers that matter now. Weighted probability retired.
//
//  Composition (top to bottom, no decorative chrome):
//
//      // L-XXXXXX · 9D IN STAGE
//      Roof tear-off, 28 sq                     ← title-as-header (Cake Mono)
//      Helen Calloway · Calloway Homes          ← contact · client
//      1240 Maple Ave                           ← address, plain
//      // ASSIGNED TO row                       ← exactly as shipped
//      ┌──────────┬──────────┬──────────┐
//      │ VALUE    │NEXT TOUCH│ SOURCE   │      ← L2 nested card, 3 cols
//      │ $14.2K   │ FRI      │ MANUAL   │
//      │ ESTIMATED│ JUL 21   │ LEAD ·…  │
//      └──────────┴──────────┴──────────┘
//
//  The stage tag moved to the nav row (LeadStatusMenu host). All values
//  trace to OPSStyle tokens.
//
import SwiftUI

struct DetailHero: View {
    let opportunity: Opportunity
    /// Resolved client name (LeadDetailViewModel.client) — nil until loaded
    /// or when the lead has no client.
    let clientName: String?
    let assigneeName: String
    let canChangeAssignee: Bool
    let onAssigneeTap: () -> Void

    init(
        opportunity: Opportunity,
        clientName: String? = nil,
        assigneeName: String = "Unassigned",
        canChangeAssignee: Bool = false,
        onAssigneeTap: @escaping () -> Void = {}
    ) {
        self.opportunity = opportunity
        self.clientName = clientName
        self.assigneeName = assigneeName
        self.canChangeAssignee = canChangeAssignee
        self.onAssigneeTap = onAssigneeTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            assigneeRow

            kpiStrip
                .padding(.top, OPSStyle.Layout.spacing2)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing1)
        .padding(.bottom, 18)
    }

    // MARK: - Assignee

    /// Compact assignment command near the lead identity. It is a button only
    /// when the row-specific policy permits assignment; everyone else gets the
    /// same information without a misleading affordance.
    @ViewBuilder
    private var assigneeRow: some View {
        if canChangeAssignee {
            Button(action: onAssigneeTap) {
                assigneeRowContent
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Assigned to \(assigneeName). Change assignee")
        } else {
            assigneeRowContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Assigned to \(assigneeName)")
        }
    }

    private var assigneeRowContent: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: OPSStyle.Icons.teamMember)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(
                    width: OPSStyle.Layout.touchTargetMin,
                    height: OPSStyle.Layout.touchTargetMin
                )

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// ASSIGNED TO")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)

                // Value line renders verbatim — names are content, not chrome.
                // The // ASSIGNED TO label above keeps its uppercase authority.
                Text(assigneeName)
                    .font(OPSStyle.Typography.bodyEmphasis)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
            }

            Spacer(minLength: OPSStyle.Layout.spacing2)

            if canChangeAssignee {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .contentShape(Rectangle())
        .nestedCard()
    }

    // MARK: - 3-col KPI strip

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            KvCell(
                label: "VALUE",
                value: estimatedValue.map(Self.formatMoneyCompact) ?? "—",
                sub: "ESTIMATED",
                useMono: false
            )

            KpiDivider()

            KvCell(
                label: "NEXT TOUCH",
                value: nextTouch.day,
                sub: nextTouch.date,
                useMono: false
            )

            KpiDivider()

            KvCell(
                label: "SOURCE",
                value: formattedSource,
                sub: "LEAD · \(displayIdShort)",
                useMono: true
            )
        }
        .nestedCard()
    }

    // MARK: - Derived

    /// NEXT TOUCH cell — weekday short on top, MMM d under, `—` when unset.
    private var nextTouch: (day: String, date: String) {
        guard let due = opportunity.nextFollowUpAt else { return ("—", "—") }
        let dayF = DateFormatter()
        dayF.dateFormat = "EEE"
        let dateF = DateFormatter()
        dateF.dateFormat = "MMM d"
        return (dayF.string(from: due).uppercased(), dateF.string(from: due).uppercased())
    }

    private var displayIdShort: String {
        opportunity.shortIdSuffix
    }

    private var estimatedValue: Double? {
        guard let v = opportunity.estimatedValue, v > 0 else { return nil }
        return v
    }

    private var formattedSource: String {
        guard let s = opportunity.source, !s.isEmpty else { return "—" }
        return s.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    /// Hero-scale compact money — deliberately chunkier than
    /// `BooksFormat.compact` (whole K above $10K). Number rendering pins to
    /// the shared canon locale so the hero never reads "1,4M" or "US$".
    private static func formatMoneyCompact(_ v: Double) -> String {
        if v >= 1_000_000 {
            return "$\((v / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(BooksFormat.locale)))M"
        }
        if v >= 10_000 {
            return "$\(Int(v / 1_000))K"
        }
        if v >= 1_000 {
            return "$\((v / 1_000).formatted(.number.precision(.fractionLength(1)).locale(BooksFormat.locale)))K"
        }
        return BooksFormat.currency(v)
    }
}


// MARK: - Pinned identity header

/// The lead's identity — id, days-in-stage, the job title, the people, the
/// address — pinned to the top of the dossier while the rest scrolls under it.
///
/// Bug 73f7381b: this block used to live inside `DetailHero` and scrolled away
/// with everything else, so halfway down a dossier there was nothing on screen
/// saying which lead you were reading. `LeadDetailView` now hosts it as a
/// `Section` header inside a `LazyVStack(pinnedViews: [.sectionHeaders])` — the
/// same mechanism ProjectDetailsView uses for its title.
///
/// The solid background is load-bearing: a pinned header with a transparent
/// background lets the scrolling document run underneath it and read as smear.
struct LeadDetailStickyHeader: View {
    let opportunity: Opportunity
    /// Resolved client name (LeadDetailViewModel.client) — nil until loaded or
    /// when the lead has no client.
    let clientName: String?

    static let accessibilityID = "lead-detail-sticky-header"
    static let titleAccessibilityID = "lead-detail-sticky-title"

    init(opportunity: Opportunity, clientName: String? = nil) {
        self.opportunity = opportunity
        self.clientName = clientName
    }

    var body: some View {
        identityBlock
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2_5)
            .padding(.bottom, OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.background)
    }

    /// Lead identity (id, days-in-stage, title, people, address) grouped into
    /// ONE VoiceOver element so it reads as a coherent unit instead of ~6
    /// disjoint fragments. (review W-3)
    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            idRow
                .padding(.bottom, 10)

            // Title as header — the JOB leads the dossier. Fallback chain:
            // title → description → contact name → "Unnamed lead"; the
            // detail view never renders blank.
            Text(heroTitle)
                .font(OPSStyle.Typography.screenTitle(for: heroTitle))
                .foregroundColor(OPSStyle.Colors.text)
                .textCase(.uppercase)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(Self.titleAccessibilityID)

            if let people = peopleSubtitle {
                Text(people)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 6)
            }

            if let address = opportunity.address, !address.isEmpty {
                Text(address)
                    .font(.custom("Mohave-Regular", size: 13))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(identityLabel)
        // The identifier belongs on the element the combine above creates —
        // SwiftUI drops an identifier applied to a container that is not itself
        // an accessibility element, which is what made the pinned header
        // unfindable from tests.
        .accessibilityIdentifier(LeadDetailStickyHeader.accessibilityID)
    }

    private var identityLabel: String {
        var parts: [String] = [
            "Lead \(displayId)",
            heroTitle
        ]
        if let people = peopleSubtitle { parts.append(people) }
        if let address = opportunity.address, !address.isEmpty { parts.append(address) }
        parts.append("\(opportunity.daysInStage) days in stage")
        return parts.joined(separator: ", ")
    }

    // MARK: - ID + days-in-stage row (one line)

    private var idRow: some View {
        HStack(spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(displayId)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
            Text(" · ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text("\(opportunity.daysInStage)D IN STAGE")
                .foregroundColor(OPSStyle.Colors.textMute)
                .monospacedDigit()
        }
        .font(OPSStyle.Typography.miniLabel)
        .kerning(1.4)
        .textCase(.uppercase)
        // Bug e13be3bb: an id + days pair is a fixed one-liner. Without a cap
        // it grows past the viewport at accessibility type sizes.
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The job leads (spec §5.3): title → description → contact name.
    private var heroTitle: String {
        if let t = opportunity.title, !t.isEmpty { return t }
        if let d = opportunity.descriptionText, !d.isEmpty { return d }
        if !opportunity.contactName.isEmpty { return opportunity.contactName }
        return "Unnamed lead"
    }

    /// "Contact · Client" — the contact drops out when it IS the header
    /// (nothing else to lead with) or when it mirrors the client name
    /// (web's mirrorsClient rule); nil hides the line entirely.
    private var peopleSubtitle: String? {
        var parts: [String] = []
        let contact = opportunity.contactName.trimmingCharacters(in: .whitespaces)
        let client = clientName?.trimmingCharacters(in: .whitespaces) ?? ""
        let contactMirrorsClient = !client.isEmpty
            && contact.lowercased() == client.lowercased()
        if !contact.isEmpty, contact != heroTitle, !contactMirrorsClient {
            parts.append(contact)
        }
        if !client.isEmpty {
            parts.append(client)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "L-AB12CD" — shared lead identifier (Opportunity.shortDisplayId) so the
    /// hero, edit sheet, and convert sheet all read the same number.
    private var displayId: String {
        opportunity.shortDisplayId
    }

}

// StageTag moved to LeadStatusMenu.swift — it is now the SHARED chip label
// for both status-menu hosts (detail nav chip + card meta chip).

// MARK: - KvCell (private)

/// One column in the hero's KPI strip. Three lines:
///   - LABEL  : JBM Mono 9.5pt 600, kerning 1.26, text3, uppercase
///   - VALUE  : Mohave Light 18pt (non-mono) OR JBM Mono Medium 13pt (mono mode)
///   - SUB    : JBM Mono 9.5pt 600, kerning 1.02, textMute, uppercase
///
/// `useMono` switches the value to monospaced 13pt — used for SOURCE which
/// reads as an enum-y label rather than a numeric value.
private struct KvCell: View {
    let label: String
    let value: String
    let sub: String
    var useMono: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(OPSStyle.Typography.nanoLabel)
                .fontWeight(.semibold)
                .kerning(1.26)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)
                // Bug e13be3bb: a 3-column strip has no room to grow — every
                // line in a cell truncates rather than widening the page.
                .lineLimit(1)
                .truncationMode(.tail)

            if useMono {
                Text(value)
                    .font(.custom("JetBrainsMono-Medium", size: 13))
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(value)
                    .font(.custom("Mohave-Light", size: 18))
                    .foregroundColor(OPSStyle.Colors.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(sub)
                .font(OPSStyle.Typography.nanoLabel)
                .fontWeight(.semibold)
                .kerning(1.02)
                .foregroundColor(OPSStyle.Colors.textMute)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 1pt vertical hairline between KPI cells. 6% white per prototype.
private struct KpiDivider: View {
    var body: some View {
        Rectangle()
            .fill(OPSStyle.Colors.fillNeutralDim)
            .frame(width: OPSStyle.Layout.Border.standard)
            .frame(maxHeight: .infinity)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("DetailHero / states") {
    ScrollView {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            DetailHero(opportunity: .preview(
                title: "Roof tear-off, 28 sq",
                contactName: "Helen Calloway",
                stage: .quoted,
                estimatedValue: 14_200,
                daysInStage: 9
            ))

            DetailHero(opportunity: .preview(
                title: "Storm damage assessment",
                contactName: "Trevor Akinola",
                stage: .negotiation,
                estimatedValue: 86_500,
                daysInStage: 3
            ))

            DetailHero(opportunity: .preview(
                title: "Single skylight install",
                contactName: "Aimee Watari",
                stage: .newLead,
                estimatedValue: nil,
                daysInStage: 0
            ))

            DetailHero(opportunity: {
                let o = Opportunity.preview(
                    title: "Maple Lane porch",
                    contactName: "Tom Liu",
                    stage: .won,
                    estimatedValue: 11_200,
                    daysInStage: 12
                )
                o.source = "referral"
                return o
            }())

            DetailHero(opportunity: {
                let o = Opportunity.preview(
                    title: "Beacon Hill addition",
                    contactName: "Beacon Hill LLC",
                    stage: .lost,
                    estimatedValue: 26_500,
                    daysInStage: 20
                )
                o.source = "web_form"
                return o
            }())
        }
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
