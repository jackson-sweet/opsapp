//
//  LeadTriageCard.swift
//  OPS
//
//  Leads redesign (2026-07-17) — the chase-console card, spec §4 / mockup
//  card-face-v3, compressed by the round-2 addendum (§14). One card, one job:
//  tell the operator whose move it is and let them flip it without drilling in.
//  Four bands, top to bottom:
//
//    • stage chip (hosting LeadStatusMenu — QUOTED · 9D ▾) + estimated value.
//      The value slot is OMITTED, not dashed, when the lead carries no money:
//      a scan card does not reserve space for a figure that does not exist.
//    • contact name, with `assigneeLabel · source` on the trailing edge. The
//      name flexes; the meta cluster is what truncates.
//    • CHASE STRIP — state left (→ YOUR MOVE · 2D / → CHASE · 3D LATE /
//      THEIR MOVE · BACK FRI / NEW · 2H), HANDLED ✓ / ADJUST chip right.
//      The whole strip is ONE 44pt control.
//    • contact row — CALL / TEXT / EMAIL / VISIT do-and-stamp + ✎ full log
//      sheet, under a hairline.
//    • summary footer band — // SUMMARY · 2D AGO ⌄, unfolds the agent
//      summary (lavender agent rail). Only when ai_summary exists.
//
//  Two things the round-1 card drew are gone. The 6-segment stage progress
//  bar (addendum §14.1): the stage chip already states the stage in words, and
//  the bar was the card's only accent while carrying nothing the chip lacked —
//  the card is now monochrome. And the job subtitle (Jackson, 2026-08-06):
//  re-sourcing it to `title` was the round-2 plan, but the queue is scanned by
//  WHO and WHAT'S DUE, and a job name the operator must read is a second
//  reading pass on every row. The name and the chase strip carry the card; the
//  job is one tap away in the dossier.
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
    /// Who owns this lead — `JASON W` / `UNASSIGNED` / `UNKNOWN`, resolved once
    /// per render by the console from its roster (spec §6.4). nil hides the
    /// token entirely: a solo operator, or any surface where assignment carries
    /// no information, never sees it. Cards never look a name up themselves.
    var assigneeLabel: String? = nil
    /// The VISIT chip's action. nil hides the chip outright (addendum §14.3),
    /// so every call site that has no site-visit path — the day sheet's own
    /// card, the previews — is untouched by its arrival.
    var onStartSiteVisit: (() -> Void)? = nil
    var onTap: () -> Void = {}
    var onLog: () -> Void = {}                 // ✎ full sheet
    var onHandled: () -> Void = {}             // strip button (yourMove/overdue/dueToday)
    var onSendFollowUp: () -> Void = {}         // due/overdue provider-backed stock reply
    var onAdjust: () -> Void = {}              // strip button (waiting) — opens date chooser
    var onStage: (PipelineStage) -> Void = { _ in }  // status menu stage pick
    var onWon: () -> Void = {}
    var onLost: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDiscard: () -> Void = {}
    var disableSwipe: Bool = false

    /// Per-card session state (spec §4) — collapsed by default, never
    /// persisted. `summaryInitiallyExpanded` exists for the snapshot harness
    /// (ImageRenderer captures initial state only); production always starts
    /// collapsed.
    @State private var summaryExpanded: Bool

    init(
        lead: Opportunity,
        viewModel: PipelineViewModel,
        bucket: PipelineViewModel.TriageBucket,
        canEdit: Bool = true,
        canConvert: Bool = true,
        assigneeLabel: String? = nil,
        onStartSiteVisit: (() -> Void)? = nil,
        onTap: @escaping () -> Void = {},
        onLog: @escaping () -> Void = {},
        onHandled: @escaping () -> Void = {},
        onSendFollowUp: @escaping () -> Void = {},
        onAdjust: @escaping () -> Void = {},
        onStage: @escaping (PipelineStage) -> Void = { _ in },
        onWon: @escaping () -> Void = {},
        onLost: @escaping () -> Void = {},
        onArchive: @escaping () -> Void = {},
        onDiscard: @escaping () -> Void = {},
        disableSwipe: Bool = false,
        summaryInitiallyExpanded: Bool = false
    ) {
        self.lead = lead
        self.viewModel = viewModel
        self.bucket = bucket
        self.canEdit = canEdit
        self.canConvert = canConvert
        self.assigneeLabel = assigneeLabel
        self.onStartSiteVisit = onStartSiteVisit
        self.onTap = onTap
        self.onLog = onLog
        self.onHandled = onHandled
        self.onSendFollowUp = onSendFollowUp
        self.onAdjust = onAdjust
        self.onStage = onStage
        self.onWon = onWon
        self.onLost = onLost
        self.onArchive = onArchive
        self.onDiscard = onDiscard
        self.disableSwipe = disableSwipe
        _summaryExpanded = State(initialValue: summaryInitiallyExpanded)
    }

    // Swipe = stage (spec §4 gestures) — the Job Board grammar in miniature:
    // drag reveals the destination stage behind the card, ≥40% commits with
    // a flash-confirm, otherwise snap back. Axis discrimination lives in
    // DirectionalDragModifier (verbatim Job Board mechanics).
    @State private var swipeOffset: CGFloat = 0
    @State private var cardWidth: CGFloat = 0
    @State private var hasTriggeredSwipeHaptic = false
    @State private var isCommittingSwipe = false
    @State private var committedStage: PipelineStage? = nil
    @State private var committedDirection: SwipeDirection? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum SwipeDirection { case left, right }

    private var isTerminal: Bool { lead.stage.isTerminal }
    private var effectiveBucket: PipelineViewModel.TriageBucket {
        bucket == .all ? viewModel.bucketOf(lead) : bucket
    }
    /// nil when the lead carries no money, and the slot then disappears
    /// entirely (addendum §14.1). `—` is the empty-state rule for a metric
    /// that OWNS a slot — a KPI line, where the reader is asking "how much?"
    /// and deserves an answer. A scan card is not asking; it should not spend
    /// a column of the value tier on a lead that has no value yet.
    private var valueText: String? {
        guard let v = lead.estimatedValue, v > 0 else { return nil }
        return BooksFormat.currency(v)
    }
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
        ZStack(alignment: .leading) {
            // Destination-stage layer fades in behind the dragged card.
            if swipeOffset > 0, let target = targetStage(.right) {
                revealLayer(target, direction: .right)
                    .opacity(revealOpacity)
            } else if swipeOffset < 0, let target = targetStage(.left) {
                revealLayer(target, direction: .left)
                    .opacity(revealOpacity)
            }

            cardBody
                .offset(x: reduceMotion ? 0 : swipeOffset)
                .opacity(cardOpacity)
                .directionalDrag(
                    isEnabled: canSwipeAny,
                    onChanged: { translation in swipeChanged(translation) },
                    onEnded: { translation in swipeEnded(translation) }
                )

            // Flash-confirm layer while the stage commit lands.
            if isCommittingSwipe, let stage = committedStage, let dir = committedDirection {
                revealLayer(stage, direction: dir)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { cardWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in cardWidth = w }
            }
        )
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Stage + value — the card's primary scan anchors
                HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2_5) {
                    stageControl

                    Spacer(minLength: 0)

                    if let valueText {
                        Text(valueText)
                            .font(.custom("JetBrainsMono-Medium", size: 16))
                            .foregroundColor(OPSStyle.Colors.text)
                            .monospacedDigit()
                    }
                }

                // Contact — name flexes, `DANA W · WEBSITE` rides the trailing
                // edge and is the side that gives up width (addendum §14.2).
                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                    Text(lead.displayContactName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)

                    Spacer(minLength: 0)

                    metaCluster
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, OPSStyle.Layout.spacing2)

                // Chase strip / terminal outcome
                if isTerminal {
                    outcomeStrip.padding(.top, OPSStyle.Layout.spacing2)
                } else {
                    LeadChaseStrip(
                        lead: lead,
                        bucket: effectiveBucket,
                        canAct: canEdit,
                        canSendFollowUp: viewModel.canSendFollowUp(for: lead),
                        followUpProgress: viewModel.followUpProgress(for: lead.id),
                        actorUserId: viewModel.currentUserId,
                        onHandled: onHandled,
                        onReviewFollowUp: {
                            await viewModel.previewFollowUp(opportunityId: lead.id)
                        },
                        onSendFollowUp: onSendFollowUp,
                        onAdjust: onAdjust
                    )
                    .padding(.top, OPSStyle.Layout.spacing2_5)
                }

                // Quick contact — open leads only
                if !isTerminal {
                    contactRow
                        .padding(.top, OPSStyle.Layout.spacing2_5)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 12)

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
        var label: String
        if isTerminal {
            let tail = outcome.detail.map { ", \($0)" } ?? ""
            label = "\(lead.displayContactName), \(outcome.label)\(tail)"
        } else {
            label = "\(lead.displayContactName), \(lead.stage.displayName)"
        }
        if let assigneeLabel {
            label += assigneeLabel == Self.unassignedToken
                ? ", unassigned"
                : ", assigned to \(assigneeLabel.capitalized)"
        }
        return label
    }

    // MARK: Swipe = stage (Job Board grammar, spec §4)

    private func targetStage(_ direction: SwipeDirection) -> PipelineStage? {
        guard !isTerminal else { return nil }
        switch direction {
        case .right:
            return lead.stage.next   // .won commits through onWon, never direct
        case .left:
            guard let idx = PipelineStage.openStages.firstIndex(of: lead.stage), idx > 0 else { return nil }
            return PipelineStage.openStages[idx - 1]
        }
    }

    private func canSwipe(_ direction: SwipeDirection) -> Bool {
        guard !disableSwipe, !isTerminal, let target = targetStage(direction) else { return false }
        return target == .won ? canConvert : canEdit
    }

    private var canSwipeAny: Bool { canSwipe(.left) || canSwipe(.right) }

    /// Reveal fades in over the first 40% of the card width — the commit
    /// threshold — so full opacity means "release to commit".
    private var revealOpacity: Double {
        guard cardWidth > 0 else { return 0 }
        return min(abs(swipeOffset) / (cardWidth * 0.4), 1.0)
    }

    /// Reduced motion: the card never translates — it fades where the offset
    /// would have moved it, revealing the destination layer beneath
    /// (opacity-only fallback, spec §11).
    private var cardOpacity: Double {
        if isCommittingSwipe { return 0 }
        if reduceMotion, swipeOffset != 0 { return 1.0 - (revealOpacity * 0.85) }
        return 1
    }

    private func swipeChanged(_ translation: CGFloat) {
        guard !isCommittingSwipe else { return }
        let direction: SwipeDirection = translation > 0 ? .right : .left
        guard canSwipe(direction) else { return }
        swipeOffset = max(min(translation, cardWidth), -cardWidth)
        if cardWidth > 0, abs(swipeOffset) / cardWidth >= 0.4, !hasTriggeredSwipeHaptic {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            hasTriggeredSwipeHaptic = true
        }
    }

    private func swipeEnded(_ translation: CGFloat) {
        guard !isCommittingSwipe else { return }
        let direction: SwipeDirection = translation > 0 ? .right : .left
        let pct = cardWidth > 0 ? abs(translation) / cardWidth : 0
        if pct >= 0.4, canSwipe(direction), let target = targetStage(direction) {
            committedStage = target
            committedDirection = direction
            isCommittingSwipe = true
            withAnimation(OPSStyle.Animation.standard) { swipeOffset = 0 }
            // Flash-confirm beat, then commit — the Job Board sequence.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if target == .won { onWon() } else { onStage(target) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(OPSStyle.Animation.standard) {
                        isCommittingSwipe = false
                        committedStage = nil
                        committedDirection = nil
                    }
                    hasTriggeredSwipeHaptic = false
                }
            }
        } else {
            withAnimation(OPSStyle.Animation.standard) { swipeOffset = 0 }
            hasTriggeredSwipeHaptic = false
        }
    }

    private func revealLayer(_ stage: PipelineStage, direction: SwipeDirection) -> some View {
        let tone = OPSStyle.Colors.pipelineStageColor(for: stage)
        return HStack {
            if direction == .left { Spacer() }
            Text(stage == .won ? "WON →" : stage.displayName)
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(tone)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            if direction == .right { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous).fill(tone.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous).strokeBorder(tone, lineWidth: 1))
        .accessibilityHidden(true)
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

    // MARK: Stage control + meta cluster (information only)

    @ViewBuilder
    private var stageControl: some View {
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
    }

    /// The engine's word for "nobody" (spec §13). An empty slot is an absence,
    /// not an operator, so it renders one step dimmer than a real name.
    private static let unassignedToken = "UNASSIGNED"

    private var sourceText: String? {
        guard let source = lead.source, !source.isEmpty else { return nil }
        return source.uppercased()
    }

    /// `JASON W · REFERRAL` on the trailing edge of the name row. Assignee is
    /// operational (text-3), source is provenance (textMute): one step apart so
    /// the eye lands on the name first. Source keeps its slot; a long assignee
    /// truncates before provenance is sacrificed, and the whole cluster yields
    /// to the contact name beside it.
    private var metaCluster: some View {
        HStack(spacing: 4) {
            if let assigneeLabel {
                Text(assigneeLabel)
                    .foregroundColor(assigneeLabel == Self.unassignedToken
                                     ? OPSStyle.Colors.textMute
                                     : OPSStyle.Colors.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if assigneeLabel != nil, sourceText != nil {
                Text("·")
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .layoutPriority(1)
            }
            if let sourceText {
                Text(sourceText)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.custom("JetBrainsMono-Regular", size: 8.5))
        .tracking(0.7)
    }

    // MARK: Quick contact (do-and-stamp, spec §3 / addendum §14.3)

    /// VISIT rides the same gate `LeadDetailView`'s START SITE VISIT menu item
    /// uses — convert scope on THIS lead, and the lead still open. Hidden, not
    /// disabled: an operator without convert scope has no visit path anywhere
    /// else either, so a dimmed chip would only advertise a door that is not
    /// his. `onStartSiteVisit == nil` closes it at the call site (the day
    /// sheet's own card owns the visit panel and passes nothing here).
    private var showsVisitChip: Bool {
        onStartSiteVisit != nil && canConvert && !isTerminal
    }

    private var contactRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ContactChipButton(label: "CALL", isEnabled: hasPhone) { placeCall() }
            ContactChipButton(label: "TEXT", isEnabled: hasPhone) { touchText() }
            ContactChipButton(label: "EMAIL", isEnabled: hasEmail) { touchEmail() }
            if showsVisitChip, let onStartSiteVisit {
                ContactChipButton(label: "VISIT", isEnabled: true) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onStartSiteVisit()
                }
            }
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
            LeadQuickTouchLogger.touch(
                .text,
                lead: lead,
                companyId: lead.companyId
            )
        } else if let url = URL(string: LeadQuickTouchLogger.smsURLString(phone: lead.contactPhone ?? "")) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    private func touchEmail() {
        guard hasEmail else { return }
        if canEdit {
            LeadQuickTouchLogger.touch(
                .email,
                lead: lead,
                companyId: lead.companyId
            )
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
                .font(OPSStyle.Typography.miniLabelBold)
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
                viewModel: .previewLoaded(), bucket: .waitingOnThem,
                // Crew of two or more — the name row reads `JASON W · REFERRAL`.
                assigneeLabel: "JASON W"
            )
            // FRESH — nobody owns it yet, no source to pair with, no value on
            // file (the value slot disappears rather than printing a dash), and
            // a convert grant, so the fourth VISIT chip is in the row.
            LeadTriageCard(
                lead: Opportunity.preview(
                    title: "Leak repair — kitchen ceiling", contactName: "Jamie Park",
                    stage: .newLead, daysInStage: 0
                ),
                viewModel: .previewLoaded(), bucket: .fresh,
                assigneeLabel: "UNASSIGNED",
                onStartSiteVisit: {}
            )
        }
        .padding(OPSStyle.Layout.spacing3_5)
    }
    .background(OPSStyle.Colors.background)
    .leadsPreviewEnvironment()
    .preferredColorScheme(.dark)
}
#endif
