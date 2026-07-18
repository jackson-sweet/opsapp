//
//  LeadTriageCard.swift
//  OPS
//
//  Leads redesign (2026-07-17) — the chase-console card, spec §4 / mockup
//  card-face-v3. One card, one job: tell the operator whose move it is and
//  let them flip it without drilling in. Structure, top to bottom:
//
//    • contact + estimated value
//    • the job ("Roof tear-off — 28 sq")
//    • CHASE STRIP — state left (→ YOUR MOVE · 2D / → CHASE · 3D LATE /
//      THEIR MOVE · BACK FRI / NEW · 2H), HANDLED ✓ / ADJUST chip right.
//      The whole strip is ONE 44pt control.
//    • meta row (information only) — 6-segment stage progress, the stage
//      chip hosting LeadStatusMenu (QUOTED · 9D ▾), source. Win % deleted.
//    • contact row — CALL / TEXT / EMAIL do-and-stamp + ✎ full log sheet
//    • summary footer band — // SUMMARY · 2D AGO ⌄, unfolds the agent
//      summary (lavender agent rail). Only when ai_summary exists.
//
//  Terminal leads (the by-stage drill reuses this card): outcome strip,
//  no contact row, no band, plain stage tag (no menu).
//

import SwiftUI

struct LeadTriageCard: View {
    @ObservedObject private var conversionVisibilityStore = LeadConversionVisibilityStore.shared
    @EnvironmentObject private var dataController: DataController

    let lead: Opportunity
    let viewModel: PipelineViewModel
    let bucket: PipelineViewModel.TriageBucket
    var canEdit: Bool = true
    var canConvert: Bool = true
    var onTap: () -> Void = {}
    var onLog: () -> Void = {}                 // ✎ full sheet
    var onHandled: () -> Void = {}             // strip button (yourMove/overdue/dueToday)
    var onAdjust: () -> Void = {}              // strip button (waiting) — opens date chooser
    var onStage: (PipelineStage) -> Void = { _ in }  // status menu stage pick
    var onWon: () -> Void = {}
    var onLost: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDiscard: () -> Void = {}
    var disableSwipe: Bool = false

    /// Per-card session state (spec §4) — collapsed by default, never persisted.
    @State private var summaryExpanded = false

    private var isTerminal: Bool { lead.stage.isTerminal }
    private var effectiveBucket: PipelineViewModel.TriageBucket {
        bucket == .all ? viewModel.bucketOf(lead) : bucket
    }
    private var valueText: String {
        guard let v = lead.estimatedValue, v > 0 else { return "—" }
        return BooksFormat.currency(v)
    }
    private var stageIndex: Int { PipelineStage.openStages.firstIndex(of: lead.stage) ?? 0 }
    private var hasPhone: Bool {
        guard let p = lead.contactPhone else { return false }
        return !p.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var hasEmail: Bool {
        guard let e = lead.contactEmail else { return false }
        return !e.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var showsSummaryBand: Bool {
        guard !isTerminal, let s = lead.aiSummary else { return false }
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

                // Chase strip / terminal outcome
                if isTerminal { outcomeStrip.padding(.top, OPSStyle.Layout.spacing2_5) }
                else { chaseStrip.padding(.top, OPSStyle.Layout.spacing2_5) }

                // Meta — stage progress · stage chip (status menu) · source
                metaRow
                    .padding(.top, OPSStyle.Layout.spacing2_5)

                // Quick contact — open leads only
                if !isTerminal {
                    contactRow
                        .padding(.top, OPSStyle.Layout.spacing2_5)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 15)

            // Summary footer band — full-bleed under a hairline
            if showsSummaryBand {
                summaryBandSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .commandCard()
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous))
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
        return "\(lead.displayContactName), \(lead.stage.displayName), \(chase.label)"
    }

    // MARK: Chase strip (spec §2.3)

    private enum ChaseAction { case handled, adjust }

    /// State copy + tone + the strip's single action, derived from the lead's
    /// effective bucket. Fresh leads have nothing to flip — strip is
    /// informational.
    private var chase: (label: String, tone: Color, action: ChaseAction?) {
        switch effectiveBucket {
        case .overdue:
            return ("→ CHASE · \(max(daysFromFollowUp(), 1))D LATE", OPSStyle.Colors.roseTextM, .handled)
        case .dueToday:
            return ("→ DUE TODAY", OPSStyle.Colors.tanTextM, .handled)
        case .waitingOnYou:
            return ("→ YOUR MOVE · \(yourMoveAge)", OPSStyle.Colors.opsAccent, .handled)
        case .waitingOnThem:
            let back = lead.nextFollowUpAt.map { " · BACK \(Self.comebackLabel($0))" } ?? ""
            return ("THEIR MOVE\(back)", OPSStyle.Colors.text2, .adjust)
        case .fresh:
            return ("NEW · \(freshAge())", OPSStyle.Colors.text2, nil)
        case .all:
            return ("OPEN", OPSStyle.Colors.text2, nil)
        }
    }

    @ViewBuilder
    private var chaseStrip: some View {
        let c = chase
        if let action = c.action {
            Button {
                // Medium impact — flipping the ball is a commit moment (spec §10).
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if action == .handled { onHandled() } else { onAdjust() }
            } label: {
                chaseStripBody(c)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chaseAccessibilityLabel(c, action: action))
        } else {
            chaseStripBody(c)
                .accessibilityElement(children: .combine)
        }
    }

    private func chaseStripBody(_ c: (label: String, tone: Color, action: ChaseAction?)) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text(c.label)
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(c.tone)
                .lineLimit(1)
                .monospacedDigit()
            Spacer(minLength: OPSStyle.Layout.spacing2)
            if let action = c.action {
                Text(action == .handled ? "HANDLED ✓" : "ADJUST")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundColor(c.tone)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous).fill(c.tone.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous).strokeBorder(c.tone.opacity(0.30), lineWidth: 1))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
        .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(c.tone.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).strokeBorder(c.tone.opacity(0.24), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func chaseAccessibilityLabel(_ c: (label: String, tone: Color, action: ChaseAction?), action: ChaseAction) -> String {
        let verb = action == .handled ? "mark handled" : "adjust the comeback date"
        return "\(c.label). Double-tap to \(verb)."
    }

    /// Age of the unanswered inbound — hours under a day, days after.
    private var yourMoveAge: String {
        guard let inbound = lead.lastInboundAt else { return "NOW" }
        let hours = Int(Date().timeIntervalSince(inbound) / 3600)
        if hours < 1 { return "NOW" }
        if hours < 24 { return "\(hours)H" }
        return "\(hours / 24)D"
    }

    /// TODAY / TMRW / FRI (within the week) / IN ND — the comeback vocabulary
    /// shared with the HANDLED toast.
    static func comebackLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        if days <= 0 { return "TODAY" }
        if days == 1 { return "TMRW" }
        if days < 7 {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: date).uppercased()
        }
        return "IN \(days)D"
    }

    // MARK: Terminal outcome strip (by-stage drill reuse)

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
            let projectState: String
            if conversionVisibilityStore.contains(lead.id) {
                projectState = "PROJECT SAVED"
            } else {
                projectState = lead.projectId == nil ? "NOT CONVERTED" : "PROJECT LINKED"
            }
            return ("WON", projectState, "checkmark", OPSStyle.Colors.oliveTextM)
        case .lost:
            let reason = lead.lostReason?
                .replacingOccurrences(of: "_", with: " ")
                .uppercased()
            return ("LOST", reason, "xmark", OPSStyle.Colors.roseTextM)
        default:
            return ("DISCARDED", nil, "xmark", OPSStyle.Colors.textMute)
        }
    }

    // MARK: Meta row (information only)

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
            .accessibilityHidden(true)

            if isTerminal {
                StageTag(stage: lead.stage, detail: "\(lead.daysInStage)D")
            } else {
                LeadStatusMenu(
                    lead: lead,
                    canEdit: canEdit,
                    canConvert: canConvert,
                    onStage: onStage,
                    onWon: onWon,
                    onLost: onLost,
                    onArchive: onArchive,
                    onDiscard: onDiscard
                ) {
                    StageTag(
                        stage: lead.stage,
                        detail: "\(lead.daysInStage)D",
                        showsChevron: canEdit || canConvert
                    )
                }
            }

            Spacer(minLength: 0)

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
            return lead.stage == .won ? OPSStyle.Colors.olive.opacity(0.5) : OPSStyle.Colors.fillNeutralDim
        }
        if idx < stageIndex { return OPSStyle.Colors.opsAccent.opacity(0.45) }
        if idx == stageIndex { return OPSStyle.Colors.opsAccent }
        return OPSStyle.Colors.fillNeutralDim
    }

    // MARK: Quick contact (do-and-stamp, spec §3)

    private var contactRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ContactChipButton(label: "CALL", isEnabled: hasPhone) { placeCall() }
            ContactChipButton(label: "TEXT", isEnabled: hasPhone) { touchText() }
            ContactChipButton(label: "EMAIL", isEnabled: hasEmail) { touchEmail() }
            if canEdit {
                LeadQuickGlyph(icon: "square.and.pencil", tint: OPSStyle.Colors.text2, action: onLog)
                    .accessibilityLabel("Log activity")
            }
        }
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .overlay(alignment: .top) {
            Rectangle().fill(OPSStyle.Colors.lineSoft).frame(height: 1)
        }
    }

    /// CALL keeps the shipped around-call contract (ContactCard.placeCall):
    /// record the outbound intent only when this operator can edit the lead,
    /// then dial. The post-call prompt / auto-log picks it up on return.
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

    /// TEXT/EMAIL do-and-stamp. A viewer without edit rights still gets the
    /// conversation (open only) — the stamp write is edit-gated so a doomed
    /// RLS insert never produces an error toast for an allowed action.
    private func touchText() {
        guard hasPhone else { return }
        if canEdit {
            LeadQuickTouchLogger.touch(.text, lead: lead, companyId: lead.companyId,
                                       userId: dataController.currentUser?.id)
        } else if let url = URL(string: LeadQuickTouchLogger.smsURLString(phone: lead.contactPhone ?? "")) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    private func touchEmail() {
        guard hasEmail else { return }
        if canEdit {
            LeadQuickTouchLogger.touch(.email, lead: lead, companyId: lead.companyId,
                                       userId: dataController.currentUser?.id)
        } else if let url = URL(string: LeadQuickTouchLogger.mailtoURLString(email: lead.contactEmail ?? "", threadSubject: nil)) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    private var sanitizedPhone: String {
        (lead.contactPhone ?? "").filter { "0123456789+".contains($0) }
    }

    // MARK: Summary footer band (spec §4.6)

    private var summaryBandSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(OPSStyle.Colors.lineSoft).frame(height: 1)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(OPSStyle.Animation.curve(OPSStyle.Animation.durationHover)) {
                    summaryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                        Text("SUMMARY").foregroundColor(OPSStyle.Colors.agent)
                    }
                    if let stamp = summaryStamp {
                        Text("· \(stamp)")
                            .foregroundColor(OPSStyle.Colors.textMute)
                            .monospacedDigit()
                    }
                    Spacer(minLength: OPSStyle.Layout.spacing2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .rotationEffect(.degrees(summaryExpanded ? 180 : 0))
                }
                .font(.custom("JetBrainsMono-Medium", size: 9.5))
                .tracking(1.2)
                .textCase(.uppercase)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summaryAccessibilityLabel)

            if summaryExpanded {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(OPSStyle.Colors.agentLine)
                        .frame(width: OPSStyle.Layout.Border.thick)
                    Text(lead.aiSummary ?? "")
                        .font(.custom("Mohave-Regular", size: 12.5))
                        .foregroundColor(OPSStyle.Colors.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OPSStyle.Colors.agentSoft)
                .transition(.opacity)
            }
        }
    }

    private var summaryStamp: String? {
        guard let updated = lead.aiSummaryUpdatedAt else { return nil }
        let interval = Date().timeIntervalSince(updated)
        if interval < 3600 { return "NOW" }
        let hours = Int(interval / 3600)
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
    }

    private var summaryAccessibilityLabel: String {
        let freshness = summaryStamp.map { ", updated \($0.lowercased())" } ?? ""
        return "Summary\(freshness), \(summaryExpanded ? "expanded" : "collapsed")"
    }

    // MARK: Derived copy

    private var jobLine: String? {
        if let d = lead.descriptionText, !d.isEmpty { return d }
        if let t = lead.title, !t.isEmpty { return t }
        return nil
    }

    private func daysFromFollowUp() -> Int {
        guard let due = lead.nextFollowUpAt else { return 0 }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: due), to: cal.startOfDay(for: Date())).day ?? 0
    }

    private func freshAge() -> String {
        let hours = Int(Date().timeIntervalSince(lead.createdAt) / 3600)
        if hours < 1 { return "NOW" }
        if hours < 24 { return "\(hours)H" }
        return "\(hours / 24)D"
    }
}

// MARK: - Contact chip button (36pt visual / 44pt hit target)

/// One quick-contact chip — CALL / TEXT / EMAIL. Neutral surface, no accent
/// (rows are for scanning; the strip owns urgency). Disabled = 35% opacity,
/// still in the VoiceOver tree so the action stays discoverable.
private struct ContactChipButton: View {
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.chipMinHeight)
                .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(OPSStyle.Colors.surfaceInput))
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).strokeBorder(OPSStyle.Colors.line, lineWidth: 1))
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.35)
        .accessibilityLabel(label)
        .accessibilityHint(isEnabled ? "" : "Unavailable — no contact detail on file")
    }
}

// MARK: - Quick-action glyph (36pt visual / 44pt hit target)

private struct LeadQuickGlyph: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); action() }) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(tint)
                .frame(width: OPSStyle.Layout.chipMinHeight, height: OPSStyle.Layout.chipMinHeight)
                .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).fill(OPSStyle.Colors.surfaceInput))
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous).strokeBorder(OPSStyle.Colors.line, lineWidth: 1))
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadTriageCard / chase states") {
    ScrollView {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            // OVERDUE — chase now
            LeadTriageCard(
                lead: Opportunity.preview(
                    title: "Roof tear-off — 28 sq", contactName: "Marcus Webb",
                    stage: .quoting, estimatedValue: 14_200, daysInStage: 5, nextFollowUpDaysFromNow: -3
                ),
                viewModel: .previewLoaded(), bucket: .overdue
            )
            // YOUR MOVE — inbound unanswered, with a summary band
            LeadTriageCard(
                lead: {
                    let o = Opportunity.preview(
                        title: "Window install — 8 units", contactName: "The Hensons",
                        stage: .quoted, estimatedValue: 11_800, daysInStage: 3
                    )
                    o.lastMessageDirection = "in"
                    o.lastInboundAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
                    o.aiSummary = "Quote sent Tuesday. They asked about triple-pane pricing; wife prefers the bronze frames. Decision expected after the 15th."
                    o.aiSummaryUpdatedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
                    return o
                }(),
                viewModel: .previewLoaded(), bucket: .waitingOnYou
            )
            // THEIR MOVE — comeback scheduled
            LeadTriageCard(
                lead: {
                    let o = Opportunity.preview(
                        title: "Gutter replacement — 140 lf", contactName: "Dana Ruiz",
                        stage: .quoted, estimatedValue: 8_600, daysInStage: 4, nextFollowUpDaysFromNow: 3
                    )
                    o.lastMessageDirection = "in"
                    o.lastInboundAt = Calendar.current.date(byAdding: .day, value: -4, to: Date())
                    o.handledAt = Calendar.current.date(byAdding: .day, value: -1, to: Date())
                    o.source = "referral"
                    return o
                }(),
                viewModel: .previewLoaded(), bucket: .waitingOnThem
            )
            // FRESH
            LeadTriageCard(
                lead: Opportunity.preview(
                    title: "Leak repair — kitchen ceiling", contactName: "Jamie Park",
                    stage: .newLead, estimatedValue: 2_200, daysInStage: 0
                ),
                viewModel: .previewLoaded(), bucket: .fresh
            )
        }
        .padding(OPSStyle.Layout.spacing3_5)
    }
    .background(OPSStyle.Colors.background)
    .leadsPreviewEnvironment()
    .preferredColorScheme(.dark)
}
#endif
