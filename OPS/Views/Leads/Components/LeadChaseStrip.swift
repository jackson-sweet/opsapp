//
//  LeadChaseStrip.swift
//  OPS
//
//  THE chase control (Leads redesign spec §2.3 / §5.6) — one 44pt strip,
//  two hosts: the triage card and the lead detail. State left, action chip
//  right:
//
//      → CHASE · 3D LATE        [HOLD TO REVIEW] rose   (eligible quote)
//      → DUE TODAY              [HOLD TO REVIEW] tan    (eligible quote)
//      → YOUR MOVE · 2D         [HANDLED ✓]     steel
//      THEIR MOVE · BACK FRI    [ADJUST]        neutral (waiting)
//      NEW · 2H                                 neutral (informational)
//
//  The whole strip is ONE control. Follow-up uses a bounded long press that
//  recognizes simultaneously with the card's horizontal stage drag; movement
//  cancels the hold so the nested control never steals the card gesture.
//  `canAct` (edit rights) hides the chip and makes the strip informational
//  without hiding the state.
//

import SwiftUI
import UIKit

struct LeadChaseStrip: View {
    static let followUpHoldMinimumDuration =
        OPSStyle.Animation.durationIntentHold
    static let followUpHoldMaximumDistance =
        OPSStyle.Layout.spacing3

    let lead: Opportunity
    /// The lead's EFFECTIVE bucket (never .all — callers resolve via
    /// `PipelineViewModel.bucketOf`).
    let bucket: PipelineViewModel.TriageBucket
    var canAct: Bool = true
    var canSendFollowUp: Bool = false
    var followUpProgress: PipelineViewModel.FollowUpProgress = .idle
    var actorUserId: String?
    var onHandled: () -> Void = {}
    var onReviewFollowUp: () async -> LeadFollowUpPreviewResult = {
        .unavailable(reason: "follow_up_not_available")
    }
    var onSendFollowUp: () -> Void = {}
    var onAdjust: () -> Void = {}

    @State private var reviewPreview: LeadFollowUpPreview?
    @State private var skipReviewNextTime = false
    @State private var preferenceRevision = 0

    enum Action: Equatable {
        case handled
        case sendFollowUp
        case adjust
    }

    var body: some View {
        let c = chase
        if let action = c.action, canAct {
            if action == .sendFollowUp {
                followUpHoldControl(c)
            } else {
                Button {
                    // Medium impact — flipping the ball is a commit moment (spec §10).
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    switch action {
                    case .handled:
                        onHandled()
                    case .sendFollowUp:
                        break
                    case .adjust:
                        onAdjust()
                    }
                } label: {
                    stripBody(c, showsAction: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(c, action: action))
            }
        } else {
            stripBody(c, showsAction: false)
                .accessibilityElement(children: .combine)
        }
    }

    // MARK: - State derivation (spec §2.3 vocabulary)

    private var chase: (label: String, tone: Color, action: Action?) {
        switch bucket {
        case .overdue:
            return (
                "→ CHASE · \(max(daysFromFollowUp(), 1))D LATE",
                OPSStyle.Colors.roseTextM,
                Self.action(for: bucket, canSendFollowUp: canSendFollowUp)
            )
        case .dueToday:
            return (
                "→ DUE TODAY",
                OPSStyle.Colors.tanTextM,
                Self.action(for: bucket, canSendFollowUp: canSendFollowUp)
            )
        case .waitingOnYou:
            return (
                "→ YOUR MOVE · \(yourMoveAge)",
                OPSStyle.Colors.opsAccent,
                Self.action(for: bucket, canSendFollowUp: canSendFollowUp)
            )
        case .waitingOnThem:
            let back = lead.nextFollowUpAt.map { " · BACK \(Self.comebackLabel($0))" } ?? ""
            return (
                "THEIR MOVE\(back)",
                OPSStyle.Colors.text2,
                Self.action(for: bucket, canSendFollowUp: canSendFollowUp)
            )
        case .fresh:
            return ("NEW · \(freshAge())", OPSStyle.Colors.text2, nil)
        case .all:
            return ("OPEN", OPSStyle.Colors.text2, nil)
        }
    }

    static func action(
        for bucket: PipelineViewModel.TriageBucket,
        canSendFollowUp: Bool
    ) -> Action? {
        switch bucket {
        case .overdue, .dueToday:
            return canSendFollowUp ? .sendFollowUp : .handled
        case .waitingOnYou:
            return .handled
        case .waitingOnThem:
            return .adjust
        case .fresh, .all:
            return nil
        }
    }

    static func actionLabel(
        for action: Action,
        progress: PipelineViewModel.FollowUpProgress,
        skipsReview: Bool = false
    ) -> String {
        switch action {
        case .handled:
            return "HANDLED ✓"
        case .sendFollowUp:
            switch progress {
            case .idle:      return skipsReview ? "HOLD TO SEND" : "HOLD TO REVIEW"
            case .reviewing: return "REVIEWING…"
            case .sending:   return "SENDING…"
            case .syncing:   return "SYNCING…"
            case .unknown:   return "CHECK EMAIL"
            }
        case .adjust:
            return "ADJUST"
        }
    }

    private func stripBody(_ c: (label: String, tone: Color, action: Action?), showsAction: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text(c.label)
                .font(OPSStyle.Typography.category)
                .tracking(OPSStyle.Typography.trackingStandard)
                .textCase(.uppercase)
                .foregroundColor(c.tone)
                .lineLimit(1)
                .monospacedDigit()
            Spacer(minLength: OPSStyle.Layout.spacing2)
            if showsAction, let action = c.action {
                Text(Self.actionLabel(
                    for: action,
                    progress: followUpProgress,
                    skipsReview: skipsReview
                ))
                    .font(OPSStyle.Typography.miniLabelBold)
                    .tracking(OPSStyle.Typography.trackingCompact)
                    .textCase(.uppercase)
                    .foregroundColor(c.tone)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(
                        RoundedRectangle(
                            cornerRadius: OPSStyle.Layout.chipRadius,
                            style: .continuous
                        )
                        .fill(c.tone.opacity(OPSStyle.Layout.Opacity.subtle))
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: OPSStyle.Layout.chipRadius,
                            style: .continuous
                        )
                        .strokeBorder(
                            c.tone.opacity(OPSStyle.Layout.Opacity.light),
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                    )
                    // Bug e13be3bb: bare .fixedSize() let this chip claim its
                    // full intrinsic width, and at accessibility type sizes
                    // `SEND FOLLOW-UP` alone ran wider than the strip and panned
                    // the whole dossier sideways. Keep the vertical fix (the
                    // chip must never be squashed) and let the width negotiate;
                    // minimumScaleFactor shrinks the label a little before
                    // truncation so the verb stays readable rather than
                    // ending as `SEND FOL…`.
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
        .background(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.sidebarHoverRadius,
                style: .continuous
            )
            .fill(c.tone.opacity(OPSStyle.Layout.Opacity.subtle))
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.sidebarHoverRadius,
                style: .continuous
            )
            .strokeBorder(
                c.tone.opacity(OPSStyle.Layout.Opacity.light),
                lineWidth: OPSStyle.Layout.Border.standard
            )
        )
        .contentShape(Rectangle())
    }

    private func accessibilityLabel(_ c: (label: String, tone: Color, action: Action?), action: Action) -> String {
        if action == .sendFollowUp, followUpProgress != .idle {
            let statusLabel = Self.actionLabel(
                for: action,
                progress: followUpProgress,
                skipsReview: skipsReview
            )
            return "\(c.label). \(statusLabel)."
        }

        let verb: String
        switch action {
        case .handled:
            verb = "mark handled"
        case .sendFollowUp:
            verb = skipsReview
                ? "send the standard follow-up email"
                : "review the standard follow-up email"
        case .adjust:
            verb = "adjust ownership or the next touch date"
        }
        return "\(c.label). Double-tap to \(verb)."
    }

    // MARK: - Deliberate follow-up

    private var skipsReview: Bool {
        _ = preferenceRevision
        guard let actorUserId else { return false }
        return UserDefaultsLeadFollowUpReviewPreferenceStore.shared.skipsReview(
            companyId: lead.companyId,
            actorUserId: actorUserId
        )
    }

    @ViewBuilder
    private func followUpHoldControl(
        _ chase: (label: String, tone: Color, action: Action?)
    ) -> some View {
        Button(action: commitFollowUp) {
            stripBody(chase, showsAction: true)
        }
            .buttonStyle(DeliberateHoldButtonStyle(
                isEnabled: followUpProgress == .idle
            ))
            .disabled(followUpProgress != .idle)
            .accessibilityLabel(accessibilityLabel(chase, action: .sendFollowUp))
            .accessibilityHint(
                skipsReview
                    ? "Hold to send. Double-tap with VoiceOver."
                    : "Hold to review. Double-tap with VoiceOver."
            )
            .sheet(item: $reviewPreview) { preview in
                LeadFollowUpReviewSheet(
                    preview: preview,
                    skipReviewNextTime: $skipReviewNextTime,
                    onCancel: {
                        reviewPreview = nil
                    },
                    onSend: {
                        saveReviewPreferenceIfNeeded()
                        reviewPreview = nil
                        UIImpactFeedbackGenerator(style: .medium)
                            .impactOccurred()
                        onSendFollowUp()
                    }
                )
            }
    }

    private func commitFollowUp() {
        guard followUpProgress == .idle else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if skipsReview {
            onSendFollowUp()
        } else {
            requestReview()
        }
    }

    private func requestReview() {
        Task {
            switch await onReviewFollowUp() {
            case .ready(let preview):
                skipReviewNextTime = false
                reviewPreview = preview
            case .unavailable:
                ToastCenter.shared.present(Feedback.Lead.followUpUnavailable)
            case .permissionDenied:
                ToastCenter.shared.present(Feedback.Lead.followUpPermissionDenied)
            case .networkError:
                ToastCenter.shared.present(Feedback.Lead.followUpNetworkError)
            }
        }
    }

    private func saveReviewPreferenceIfNeeded() {
        guard skipReviewNextTime, let actorUserId else { return }
        UserDefaultsLeadFollowUpReviewPreferenceStore.shared.setSkipsReview(
            true,
            companyId: lead.companyId,
            actorUserId: actorUserId
        )
        preferenceRevision += 1
    }

    // MARK: - Ages & vocabulary

    /// Age of the newest event that put the lead in YOUR MOVE.
    private var yourMoveAge: String {
        Self.yourMoveAge(
            lastInboundAt: lead.lastInboundAt,
            operatorActionRequiredAt: lead.operatorActionRequiredAt
        )
    }

    static func yourMoveAge(
        lastInboundAt: Date?,
        operatorActionRequiredAt: Date?,
        now: Date = Date()
    ) -> String {
        let reference = [lastInboundAt, operatorActionRequiredAt]
            .compactMap { $0 }
            .max()
        guard let reference else { return "NOW" }
        let hours = Int(now.timeIntervalSince(reference) / 3600)
        if hours < 1 { return "NOW" }
        if hours < 24 { return "\(hours)H" }
        return "\(hours / 24)D"
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

    /// TODAY / TMRW / FRI (within the week) / IN ND — the comeback vocabulary
    /// shared by the strip, the HANDLED toast, and the chooser rows.
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
}

/// Keeps semantic Button behavior for VoiceOver while ordinary sighted taps do
/// nothing. The bounded hold is simultaneous with the card's directional drag;
/// its movement allowance ends before that drag's 20pt recognition threshold.
private struct DeliberateHoldButtonStyle: PrimitiveButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(
                    minimumDuration:
                        LeadChaseStrip.followUpHoldMinimumDuration,
                    maximumDistance:
                        LeadChaseStrip.followUpHoldMaximumDistance
                )
                .onEnded { _ in
                    guard isEnabled else { return }
                    configuration.trigger()
                }
            )
    }
}
