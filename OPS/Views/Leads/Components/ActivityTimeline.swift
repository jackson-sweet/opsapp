//
//  ActivityTimeline.swift
//  OPS
//
//  ONE activity stream on LeadDetailView (Leads redesign spec §5.10) —
//  activities and stage changes merge-sorted into a single reverse-
//  chronological rail. Rows:
//
//      ↓  Quote question — email               2D  ⌄
//         └ expanded: the note / email gist (inline, mono-quiet)
//      ●  Stage: QUOTING → QUOTED              4D
//      ↑  Text to Helen — text                 5D
//
//  Direction glyphs: ↓ steel inbound (their touch — the YOUR MOVE tone),
//  ↑ olive outbound (your touch landed), type icon otherwise. Rows with a
//  body unfold inline (150ms, reduced-motion aware). Capped at `maxItems`
//  with a VIEW ALL → N footer pushing the full history.
//
//  Empty state: a single muted `// NO ACTIVITY LOGGED` line inside the
//  card. Card itself always renders so the section heading stays anchored.
//
//  One row breaks the rail's grammar on purpose: a completed SITE VISIT. A
//  message is one touch in a conversation; a visit is somebody standing on the
//  property with a tape measure, and it carries everything the estimate will be
//  built from. It renders as the SITE VISIT RECORD card — the same card the
//  project activity tab shows — and opens the same full record. Prominence
//  proportional to weight; it is the thing you scan this rail to find.
//

import SwiftUI
import SwiftData
import UIKit

/// Geometry the lead rail shares across its pieces.
enum LeadStreamMetrics {
    /// The rail's horizontal inset. Every row, every hairline, and the
    /// site-visit record card sit on it, so the column reads as one edge —
    /// the value lives here once precisely so they cannot drift apart.
    static let rowInset: CGFloat = 14
}

/// One stream entry — an activity or a stage change folded into the rail.
enum LeadStreamEntry: Identifiable {
    case activity(Activity)
    case stage(StageTransition)

    var id: String {
        switch self {
        case .activity(let a): return "a-\(a.id)"
        case .stage(let t):    return "s-\(t.id)"
        }
    }

    var date: Date {
        switch self {
        case .activity(let a): return a.createdAt
        case .stage(let t):    return t.transitionedAt
        }
    }

    /// Merge-sort both sources newest-first.
    static func merged(activities: [Activity], transitions: [StageTransition]) -> [LeadStreamEntry] {
        (activities.map(LeadStreamEntry.activity) + transitions.map(LeadStreamEntry.stage))
            .sorted { $0.date > $1.date }
    }
}

struct ActivityTimeline: View {
    let activities: [Activity]
    let transitions: [StageTransition]
    /// The lead this rail belongs to. Supplies the site-visit record its
    /// identity and its value; nil keeps every row plain.
    var opportunity: Opportunity? = nil
    var maxItems: Int = 6
    var onViewAll: () -> Void = {}

    /// Inline-expanded rows, per presentation (never persisted).
    @State private var expanded: Set<String> = []

    private var entries: [LeadStreamEntry] {
        LeadStreamEntry.merged(activities: activities, transitions: transitions)
    }

    var body: some View {
        let entries = self.entries
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(label: "ACTIVITY", count: entries.isEmpty ? nil : entries.count)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 10)

            content(entries)
                .commandCard()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    @ViewBuilder
    private func content(_ entries: [LeadStreamEntry]) -> some View {
        if entries.isEmpty {
            EmptyLine(text: "// NO ACTIVITY LOGGED")
        } else {
            let shown = Array(entries.prefix(maxItems))
            VStack(spacing: 0) {
                ForEach(shown) { entry in
                    LeadStreamEntryView(
                        entry: entry,
                        opportunity: opportunity,
                        isExpanded: expanded.contains(entry.id),
                        onToggle: { toggle(entry.id) }
                    )
                    if entry.id != shown.last?.id {
                        Rectangle()
                            .fill(OPSStyle.Colors.surfaceInput)
                            .frame(height: 1)
                            .padding(.horizontal, LeadStreamMetrics.rowInset)
                    }
                }

                if entries.count > maxItems {
                    Rectangle()
                        .fill(OPSStyle.Colors.lineSoft)
                        .frame(height: 1)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onViewAll()
                    } label: {
                        HStack(spacing: 6) {
                            Text("VIEW ALL")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                            Spacer(minLength: 0)
                            Text("\(entries.count)")
                                .monospacedDigit()
                        }
                        .font(.custom("JetBrainsMono-Medium", size: 9.5))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .padding(.horizontal, LeadStreamMetrics.rowInset)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all \(entries.count) activities")
                }
            }
        }
    }

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(OPSStyle.Animation.curve(OPSStyle.Animation.durationHover)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}

// MARK: - Entry (row, or the site-visit record behind it)

/// One rail entry. Everything renders as `LeadStreamRow` except a completed
/// site visit whose visit is on this device — that becomes the SITE VISIT
/// RECORD card.
///
/// The device check is the whole gate, and it is not a technicality: site
/// visits and their capture artifacts never leave the phone that took them, so
/// on anyone else's phone there is no record to build. Rather than invent one
/// from an empty shell, the row stays exactly the plain row it has always been.
struct LeadStreamEntryView: View {
    let entry: LeadStreamEntry
    var opportunity: Opportunity? = nil
    let isExpanded: Bool
    var onToggle: () -> Void = {}

    var body: some View {
        if case .activity(let activity) = entry,
           activity.type == .siteVisit,
           let visitId = activity.siteVisitId,
           !visitId.isEmpty {
            LeadSiteVisitEntryView(
                entry: entry,
                activity: activity,
                visitId: visitId,
                opportunity: opportunity,
                isExpanded: isExpanded,
                onToggle: onToggle
            )
        } else {
            LeadStreamRow(entry: entry, isExpanded: isExpanded, onToggle: onToggle)
        }
    }
}

/// Resolves a site-visit activity against this device's local capture and
/// renders the record card when it is all there.
private struct LeadSiteVisitEntryView: View {
    let entry: LeadStreamEntry
    let activity: Activity
    let visitId: String
    let opportunity: Opportunity?
    let isExpanded: Bool
    var onToggle: () -> Void = {}

    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var visits: [SiteVisit]
    @Query private var artifacts: [SiteVisitCaptureArtifact]
    @Query private var checklistAnswers: [SiteVisitChecklistAnswer]
    @Query private var identityDrafts: [SiteVisitIdentityDraft]
    @Query private var authors: [TeamMember]

    @State private var showRecord = false

    init(
        entry: LeadStreamEntry,
        activity: Activity,
        visitId: String,
        opportunity: Opportunity?,
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.entry = entry
        self.activity = activity
        self.visitId = visitId
        self.opportunity = opportunity
        self.isExpanded = isExpanded
        self.onToggle = onToggle

        _visits = Query(filter: #Predicate<SiteVisit> { $0.id == visitId })
        _artifacts = Query(
            filter: #Predicate<SiteVisitCaptureArtifact> { $0.siteVisitId == visitId },
            sort: [SortDescriptor(\SiteVisitCaptureArtifact.capturedAt, order: .forward)]
        )
        _checklistAnswers = Query(
            filter: #Predicate<SiteVisitChecklistAnswer> { $0.siteVisitId == visitId }
        )
        _identityDrafts = Query(
            filter: #Predicate<SiteVisitIdentityDraft> { $0.siteVisitId == visitId }
        )
        let authorId = activity.createdBy ?? ""
        _authors = Query(filter: #Predicate<TeamMember> { $0.id == authorId })
    }

    private var teamMember: TeamMember? { authors.first }

    /// Matches the project feed's author fallback so one visit reads the same
    /// on both surfaces.
    private var operatorName: String { teamMember?.fullName ?? "Team Member" }

    private var record: SiteVisitRecord? {
        guard let visit = visits.first else { return nil }
        return SiteVisitRecord.assembleFromLocalCapture(
            visit: visit,
            artifacts: artifacts,
            checklistAnswers: checklistAnswers,
            identity: identityDrafts.first,
            opportunity: opportunity,
            capturedAt: activity.createdAt,
            operatorName: operatorName,
            canViewFinancials: permissionStore.can("finances.view")
        )
    }

    var body: some View {
        if let record {
            SiteVisitRecordCard(
                record: record,
                teamMember: teamMember,
                onOpen: { showRecord = true }
            )
            // Sits on the rail's own inset so the card's edges line up with
            // the hairlines above and below it.
            .padding(.horizontal, LeadStreamMetrics.rowInset)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .sheet(isPresented: $showRecord) {
                // No photo tap-through: a lead has no project gallery to open
                // into, and a dead-end tap is worse than no tap.
                SiteVisitRecordView(record: record)
            }
        } else {
            LeadStreamRow(entry: entry, isExpanded: isExpanded, onToggle: onToggle)
        }
    }
}

// MARK: - Row (shared with LeadActivityHistoryView)

struct LeadStreamRow: View {
    let entry: LeadStreamEntry
    let isExpanded: Bool
    var onToggle: () -> Void = {}

    var body: some View {
        switch entry {
        case .activity(let activity):
            activityRow(activity)
        case .stage(let transition):
            stageRow(transition)
        }
    }

    // MARK: Activity row

    @ViewBuilder
    private func activityRow(_ activity: Activity) -> some View {
        let body = expandableBody(activity)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if body != nil { onToggle() }
            } label: {
                HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2_5) {
                    // Direction reads at row level, not as a 13pt arrow you
                    // have to hunt for: a leading rule in the direction's tone
                    // runs the height of the row, so a feed of inbound and
                    // outbound messages separates at a glance on a bright
                    // job-site screen.
                    directionRule(activity)

                    glyph(activity)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(titleText(activity))
                            .font(.custom("Mohave-Medium", size: 14))
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let metadata = metadataText(activity) {
                            Text(metadata)
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(metadataColor(activity))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(Self.ageString(entry.date))
                        .font(OPSStyle.Typography.nanoLabel)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .kerning(1.0)
                        .textCase(.uppercase)
                        .monospacedDigit()

                    if body != nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.textMute)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, LeadStreamMetrics.rowInset)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(body == nil)
            .accessibilityLabel(accessibilityLabel(activity, hasBody: body != nil))

            if isExpanded, let body {
                Text(body)
                    .font(.custom("Mohave-Regular", size: 12.5))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LeadStreamMetrics.rowInset)
                    .padding(.leading, 20 + OPSStyle.Layout.spacing2_5)
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)
                    .transition(.opacity)
            }
        }
    }

    /// Direction glyph — ↓ tan inbound (their move), ↑ olive outbound (yours),
    /// the type icon otherwise. Shares `directionTone` with the row rule so the
    /// two cues can never disagree, and keeps the steel accent reserved for the
    /// screen's primary CTA.
    @ViewBuilder
    private func glyph(_ activity: Activity) -> some View {
        switch activity.direction {
        case "inbound":
            Text("↓")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tanTextM)
        case "outbound":
            Text("↑")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.oliveTextM)
        default:
            Image(systemName: activity.type.icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(OPSStyle.Colors.text3)
        }
    }

    /// Leading rule carrying the message's direction — tan (attention: they
    /// moved, it may be your turn) versus olive (handled: you moved). Invisible
    /// for anything with no direction (notes, stage changes) so the feed never
    /// grows decorative furniture.
    ///
    /// Earth tones, never the steel accent: the accent is the primary CTA and
    /// focus ring only, and a feed of six inbound messages would put six accent
    /// marks on one screen.
    @ViewBuilder
    private func directionRule(_ activity: Activity) -> some View {
        Rectangle()
            .fill(directionTone(activity) ?? Color.clear)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func directionTone(_ activity: Activity) -> Color? {
        switch activity.direction {
        case "inbound":  return OPSStyle.Colors.tanTextM
        case "outbound": return OPSStyle.Colors.oliveTextM
        default:         return nil
        }
    }

    /// Who the message was between, from the operator's side. Bug 183f7ec9: the
    /// title used to be the SUBJECT, and every message in a thread shares one
    /// subject — so a five-message exchange rendered as five identical rows and
    /// the feed read as a thread dump. Naming the two ends makes each row a
    /// distinct fact; the subject drops to the metadata line where it belongs.
    private func titleText(_ activity: Activity) -> String {
        if let participants = participantsText(activity) { return participants }
        if let subject = activity.subject, !subject.isEmpty { return subject }
        if let body = activity.displayBody, !body.isEmpty {
            return EmailBodyCleaner.preview(body, limit: 80)
        }
        return activity.type.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    /// `Helen Calloway → You` / `You → Helen Calloway`. Nil when the row has no
    /// email identity, which is every note, call, and pre-sync row.
    private func participantsText(_ activity: Activity) -> String? {
        guard let counterparty = Self.displayName(for: activity.counterpartyEmail) else {
            return nil
        }
        switch activity.direction {
        case "inbound":  return "\(counterparty) → You"
        case "outbound": return "You → \(counterparty)"
        default:         return counterparty
        }
    }

    /// The local part of an address, title-cased — `helen.calloway@x.com`
    /// reads as `Helen Calloway`. Falls back to the raw address when that
    /// would produce nothing useful.
    static func displayName(for email: String?) -> String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else { return nil }
        guard let local = email.split(separator: "@").first, !local.isEmpty else {
            return email
        }
        let words = local
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".")
            .split(separator: ".")
            .filter { !$0.isEmpty }
        // A local part that is all digits or a single opaque token (`info`,
        // `x7fa92`) is not a name — show the address, which at least identifies.
        guard words.count > 1 else { return email }
        return words
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// The inline-expandable body — only when it adds something beyond the
    /// title line. Quoted reply chains and signatures are stripped so an
    /// expanded email shows what its sender actually wrote, not the thread.
    private func expandableBody(_ activity: Activity) -> String? {
        guard let raw = activity.displayBody, !raw.isEmpty else { return nil }
        let cleaned = EmailBodyCleaner.clean(raw)
        guard !cleaned.isEmpty, cleaned != activity.subject else { return nil }
        // With participants as the title, the subject is no longer the title —
        // so a body that merely repeats it still adds nothing.
        if participantsText(activity) == nil,
           activity.subject == nil || activity.subject?.isEmpty == true {
            return nil
        }
        return cleaned
    }

    /// Subject, duration, and/or outcome, joined with a middot. The subject
    /// lives here now that the title names the two ends of the message.
    private func metadataText(_ activity: Activity) -> String? {
        var parts: [String] = []
        if participantsText(activity) != nil,
           let subject = activity.subject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subject.isEmpty {
            parts.append(subject)
        }
        if let duration = activity.durationMinutes.flatMap(formatDuration) {
            parts.append(duration)
        }
        if let outcome = activity.outcome.flatMap(formatOutcome) {
            parts.append(outcome)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func metadataColor(_ activity: Activity) -> Color {
        guard let outcome = activity.outcome else { return OPSStyle.Colors.text3 }
        return outcomeColor(outcome)
    }

    private func formatDuration(_ minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }

    private func formatOutcome(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// Semantic allowlist ONLY — never color by anything else. Defaults to text3.
    private func outcomeColor(_ raw: String) -> Color {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        let positive: Set<String> = ["connected", "answered", "reached", "spoke"]
        let negative: Set<String> = [
            "no answer", "voicemail", "left voicemail", "declined", "not interested", "no show"
        ]
        if positive.contains(normalized) { return OPSStyle.Colors.oliveTextM }
        if negative.contains(normalized) { return OPSStyle.Colors.roseTextM }
        return OPSStyle.Colors.text3
    }

    private func accessibilityLabel(_ activity: Activity, hasBody: Bool) -> String {
        var parts: [String] = []
        switch activity.direction {
        case "inbound":  parts.append("Inbound")
        case "outbound": parts.append("Outbound")
        default:         break
        }
        // Spoken, an arrow is noise — say the relationship instead.
        if let counterparty = Self.displayName(for: activity.counterpartyEmail) {
            switch activity.direction {
            case "inbound":  parts.append("from \(counterparty)")
            case "outbound": parts.append("to \(counterparty)")
            default:         parts.append(counterparty)
            }
        } else {
            parts.append(titleText(activity))
        }
        if let metadata = metadataText(activity) { parts.append(metadata) }
        parts.append(Self.ageString(entry.date).lowercased())
        if hasBody { parts.append(isExpanded ? "expanded" : "collapsed") }
        return parts.joined(separator: ", ")
    }

    // MARK: Stage row (folded-in transition)

    private func stageRow(_ transition: StageTransition) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text("●")
                .font(.system(size: 6))
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(width: 20)

            // Bug e13be3bb: a stage transition is a one-line fact. Uncapped,
            // two long stage names side by side pushed the feed wider than the
            // screen and the whole dossier panned.
            HStack(spacing: 5) {
                Text("Stage:")
                    .font(.custom("Mohave-Regular", size: 13))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
                    .layoutPriority(-1)
                if let from = transition.fromStage {
                    Text(from.shortLabel)
                        .font(OPSStyle.Typography.nanoLabel)
                        .fontWeight(.semibold)
                        .kerning(1.0)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
                Text(transition.toStage.displayName)
                    .font(OPSStyle.Typography.nanoLabel)
                    .fontWeight(.semibold)
                    .kerning(1.0)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.ageString(entry.date))
                .font(OPSStyle.Typography.nanoLabel)
                .foregroundColor(OPSStyle.Colors.textMute)
                .kerning(1.0)
                .textCase(.uppercase)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, LeadStreamMetrics.rowInset)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stageAccessibilityLabel(transition))
    }

    private func stageAccessibilityLabel(_ transition: StageTransition) -> String {
        let from = transition.fromStage.map { "\($0.displayName) to " } ?? ""
        return "Stage change, \(from)\(transition.toStage.displayName), \(Self.ageString(entry.date).lowercased())"
    }

    // MARK: Age

    static func ageString(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60      { return "NOW" }
        let mins = Int(interval / 60)
        if mins < 60          { return "\(mins)M" }
        let hours = mins / 60
        if hours < 24         { return "\(hours)H" }
        let days = hours / 24
        if days < 7           { return "\(days)D" }
        let weeks = days / 7
        if weeks < 5          { return "\(weeks)W" }
        let months = days / 30
        return "\(months)MO"
    }
}

// MARK: - Empty inline line (private)

private struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OPSStyle.Typography.miniLabel)
            .kerning(1.6)
            .foregroundColor(OPSStyle.Colors.textMute)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, LeadStreamMetrics.rowInset)
            .padding(.vertical, LeadStreamMetrics.rowInset)
    }
}
