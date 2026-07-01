//
//  LeadTriageCard.swift
//  OPS
//
//  Money & Leads redesign (2026-06-30) — design direction "2a · TRIAGE LEADS".
//  The reimagined chase-queue card. Leads with one job: tell the operator the
//  single next action and let them take it without drilling in. Structure:
//    • contact + estimated value
//    • the job ("Roof tear-off — 28 sq")
//    • a tinted ACTION STRIP — the next move (CHASE QUOTE / FOLLOW UP / …) +
//      the follow-up due tag, colored by urgency
//    • a meta row — stage progress, days in stage, win likelihood, source
//    • quick actions surfaced on the card: log · advance · won · lost
//

import SwiftUI

struct LeadTriageCard: View {
    let lead: Opportunity
    let viewModel: PipelineViewModel
    let bucket: PipelineViewModel.TriageBucket
    var canManage: Bool = true
    var onTap: () -> Void = {}
    var onLog: () -> Void = {}
    var onAdvance: () -> Void = {}
    var onWon: () -> Void = {}
    var onLost: () -> Void = {}

    private static let openStages: [PipelineStage] = [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]

    private var tone: PipelineViewModel.UrgencyTone { viewModel.toneFor(bucket, lead: lead) }
    private var toneColor: Color {
        switch tone {
        case .rose:    return OPSStyle.Colors.roseTextM
        case .tan:     return OPSStyle.Colors.tanTextM
        case .steel:   return OPSStyle.Colors.opsAccent
        case .neutral: return OPSStyle.Colors.text2
        }
    }
    private var verb: String { viewModel.verbFor(lead, bucket: bucket) }
    private var winPct: Int { lead.winProbabilityOverride ?? lead.stage.winProbability }
    private var winColor: Color {
        if winPct >= 65 { return OPSStyle.Colors.olive }
        if winPct >= 45 { return OPSStyle.Colors.tan }
        return OPSStyle.Colors.rose
    }
    private var valueText: String {
        guard let v = lead.estimatedValue, v > 0 else { return "—" }
        return BooksFormat.currency(v)
    }
    private var stageIndex: Int { Self.openStages.firstIndex(of: lead.stage) ?? 0 }
    private var isTerminal: Bool { lead.stage.isTerminal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Contact + value
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2_5) {
                Text(lead.displayContactName)
                    .font(.custom("Mohave-Medium", size: 16))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(valueText)
                    .font(.custom("JetBrainsMono-Medium", size: 16))
                    .foregroundColor((lead.estimatedValue ?? 0) > 0 ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                    .monospacedDigit()
            }

            // Job
            if let job = jobLine {
                Text(job)
                    .font(.custom("Mohave-Regular", size: 13.5))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.top, 2)
            }

            // Action strip — the next move + due tag
            actionStrip
                .padding(.top, OPSStyle.Layout.spacing2_5)

            // Meta — stage progress · days · win · source
            metaRow
                .padding(.top, OPSStyle.Layout.spacing2_5)

            // Quick actions — open leads only. A closed lead has nothing to
            // advance / win / lose; edit + archive stay reachable via the
            // long-press context menu the parent attaches.
            if canManage && !isTerminal {
                quickActions
                    .padding(.top, OPSStyle.Layout.spacing2_5)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .commandCard()
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        if isTerminal {
            let tail = outcome.detail.map { ", \($0)" } ?? ""
            return "\(lead.displayContactName), \(outcome.label)\(tail)"
        }
        return "\(lead.displayContactName), \(verb), \(dueTag.text)"
    }

    // MARK: Action strip

    /// Open leads lead with the next move; closed leads state the outcome. The
    /// triage queue only ever hands this card open leads — the terminal branch
    /// serves the by-stage drill (PipelineStageListView), which reuses this card.
    @ViewBuilder
    private var actionStrip: some View {
        if isTerminal { outcomeStrip } else { followUpStrip }
    }

    /// Open-lead strip — the next move + the follow-up due tag, tinted by urgency.
    private var followUpStrip: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("→")
                    .font(.system(size: 13))
                    .foregroundColor(toneColor)
                Text(verb)
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundColor(toneColor)
                    .lineLimit(1)
            }
            Spacer(minLength: OPSStyle.Layout.spacing2)
            Text(dueTag.text)
                .font(.custom("JetBrainsMono-Medium", size: 8.5))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(dueTag.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(dueTag.color.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(dueTag.color.opacity(0.30), lineWidth: 1))
                .fixedSize()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(toneColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).strokeBorder(toneColor.opacity(0.24), lineWidth: 1))
    }

    /// Terminal-lead strip — states the outcome (WON / LOST / DISCARDED) with a
    /// compact qualifier: won → converted vs not, lost → the loss reason.
    private var outcomeStrip: some View {
        let color = outcome.color
        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: outcome.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Text(outcome.label)
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundColor(color)
                    .lineLimit(1)
            }
            Spacer(minLength: OPSStyle.Layout.spacing2)
            if let detail = outcome.detail {
                Text(detail)
                    .font(.custom("JetBrainsMono-Medium", size: 8.5))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(color.opacity(0.30), lineWidth: 1))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).strokeBorder(color.opacity(0.24), lineWidth: 1))
    }

    /// Resolved outcome copy for a terminal lead — label, qualifier, glyph, tone.
    private var outcome: (label: String, detail: String?, icon: String, color: Color) {
        switch lead.stage {
        case .won:
            return ("WON",
                    lead.projectId == nil ? "NOT CONVERTED" : "PROJECT LINKED",
                    "checkmark",
                    OPSStyle.Colors.oliveTextM)
        case .lost:
            let reason = lead.lostReason?
                .replacingOccurrences(of: "_", with: " ")
                .uppercased()
            return ("LOST", reason, "xmark", OPSStyle.Colors.roseTextM)
        default:
            return ("DISCARDED", nil, "xmark", OPSStyle.Colors.textMute)
        }
    }

    // MARK: Meta row

    private var metaRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Stage progress — 6 segments filled to the current stage
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(segmentColor(idx))
                        .frame(height: 3)
                }
            }
            .frame(width: 62)

            Text("\(lead.stage.shortLabel) · \(lead.daysInStage)D")
                .font(.custom("JetBrainsMono-Regular", size: 9))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle().fill(winColor).frame(width: 6, height: 6)
                Text("\(winPct)%")
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(winColor)
                    .monospacedDigit()
            }

            if let source = lead.source, !source.isEmpty {
                Text(source.uppercased())
                    .font(.custom("JetBrainsMono-Regular", size: 8.5))
                    .tracking(0.7)
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
    }

    private func segmentColor(_ idx: Int) -> Color {
        if isTerminal {
            // Won reads as a completed bar (all olive); lost / discarded carry no
            // progress meaning, so the track stays neutral.
            return lead.stage == .won ? OPSStyle.Colors.olive.opacity(0.5) : Color.white.opacity(0.10)
        }
        if idx < stageIndex { return OPSStyle.Colors.opsAccent.opacity(0.45) }
        if idx == stageIndex { return OPSStyle.Colors.opsAccent }
        return Color.white.opacity(0.10)
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            LeadQuickGlyph(icon: "square.and.pencil", tint: OPSStyle.Colors.text2, action: onLog)
                .accessibilityLabel("Log activity")

            Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); onAdvance() }) {
                HStack(spacing: 7) {
                    Text("ADVANCE")
                        .font(.custom("JetBrainsMono-Medium", size: 10))
                        .tracking(0.9)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(OPSStyle.Colors.opsAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(OPSStyle.Colors.opsAccent.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).strokeBorder(OPSStyle.Colors.opsAccent.opacity(0.40), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(lead.stage.isTerminal || lead.stage.next == nil)
            .opacity(lead.stage.isTerminal || lead.stage.next == nil ? 0.4 : 1)
            .accessibilityLabel("Advance stage")

            LeadQuickGlyph(icon: "checkmark", tint: OPSStyle.Colors.olive, action: onWon)
                .accessibilityLabel("Mark won")
            LeadQuickGlyph(icon: "xmark", tint: OPSStyle.Colors.textMute, action: onLost)
                .accessibilityLabel("Mark lost")
        }
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: Derived copy

    private var jobLine: String? {
        if let d = lead.descriptionText, !d.isEmpty { return d }
        if let t = lead.title, !t.isEmpty { return t }
        return nil
    }

    private var dueTag: (text: String, color: Color) {
        switch bucket {
        case .overdue:
            return ("\(daysFromFollowUp().magnitude)D OVERDUE", toneColor)
        case .dueToday:
            return ("DUE TODAY", toneColor)
        case .waitingOnYou:
            return ("YOUR MOVE", toneColor)
        case .waitingOnThem:
            return ("WAITING \(daysSinceActivity())D", toneColor)
        case .fresh:
            return ("NEW · \(freshAge())", toneColor)
        case .all:
            return (genericDue(), toneColor)
        }
    }

    private func daysFromFollowUp() -> Int {
        guard let due = lead.nextFollowUpAt else { return 0 }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: due), to: cal.startOfDay(for: Date())).day ?? 0
    }

    private func daysSinceActivity() -> Int {
        let ref = lead.lastActivityAt ?? lead.stageEnteredAt
        let cal = Calendar.current
        return max(cal.dateComponents([.day], from: cal.startOfDay(for: ref), to: cal.startOfDay(for: Date())).day ?? 0, 0)
    }

    private func freshAge() -> String {
        let hours = Int(Date().timeIntervalSince(lead.createdAt) / 3600)
        if hours < 1 { return "NOW" }
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
    }

    private func genericDue() -> String {
        guard let due = lead.nextFollowUpAt else { return "OPEN" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: due)).day ?? 0
        if days < 0 { return "\(abs(days))D OVERDUE" }
        if days == 0 { return "DUE TODAY" }
        if days == 1 { return "DUE TOMORROW" }
        return "DUE IN \(days)D"
    }
}

// MARK: - Quick-action glyph (38pt visual / 44pt hit target)

private struct LeadQuickGlyph: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); action() }) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(OPSStyle.Colors.surfaceInput))
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).strokeBorder(OPSStyle.Colors.line, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
