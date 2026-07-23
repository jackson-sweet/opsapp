//
//  LeadChaseStrip.swift
//  OPS
//
//  THE chase control (Leads redesign spec §2.3 / §5.6) — one 44pt strip,
//  two hosts: the triage card and the lead detail. State left, action chip
//  right:
//
//      → CHASE · 3D LATE        [SEND FOLLOW-UP] rose    (eligible quote)
//      → DUE TODAY              [SEND FOLLOW-UP] tan     (eligible quote)
//      → YOUR MOVE · 2D         [HANDLED ✓]     steel
//      THEIR MOVE · BACK FRI    [ADJUST]        neutral (waiting)
//      NEW · 2H                                 neutral (informational)
//
//  The whole strip is ONE control. `canAct` (edit rights) hides the chip
//  and makes the strip informational without hiding the state.
//

import SwiftUI
import UIKit

struct LeadChaseStrip: View {
    let lead: Opportunity
    /// The lead's EFFECTIVE bucket (never .all — callers resolve via
    /// `PipelineViewModel.bucketOf`).
    let bucket: PipelineViewModel.TriageBucket
    var canAct: Bool = true
    var canSendFollowUp: Bool = false
    var followUpProgress: PipelineViewModel.FollowUpProgress = .idle
    var onHandled: () -> Void = {}
    var onSendFollowUp: () -> Void = {}
    var onAdjust: () -> Void = {}

    enum Action: Equatable {
        case handled
        case sendFollowUp
        case adjust
    }

    var body: some View {
        let c = chase
        if let action = c.action, canAct {
            Button {
                // Medium impact — flipping the ball is a commit moment (spec §10).
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                switch action {
                case .handled:
                    onHandled()
                case .sendFollowUp:
                    onSendFollowUp()
                case .adjust:
                    onAdjust()
                }
            } label: {
                stripBody(c, showsAction: true)
            }
            .buttonStyle(.plain)
            .disabled(action == .sendFollowUp && followUpProgress != .idle)
            .accessibilityLabel(accessibilityLabel(c, action: action))
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
        progress: PipelineViewModel.FollowUpProgress
    ) -> String {
        switch action {
        case .handled:
            return "HANDLED ✓"
        case .sendFollowUp:
            switch progress {
            case .idle:    return "SEND FOLLOW-UP"
            case .sending: return "SENDING…"
            case .syncing: return "SYNCING…"
            case .unknown: return "CHECK EMAIL"
            }
        case .adjust:
            return "ADJUST"
        }
    }

    private func stripBody(_ c: (label: String, tone: Color, action: Action?), showsAction: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text(c.label)
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(c.tone)
                .lineLimit(1)
                .monospacedDigit()
            Spacer(minLength: OPSStyle.Layout.spacing2)
            if showsAction, let action = c.action {
                Text(Self.actionLabel(
                    for: action,
                    progress: followUpProgress
                ))
                    .font(OPSStyle.Typography.miniLabelBold)
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

    private func accessibilityLabel(_ c: (label: String, tone: Color, action: Action?), action: Action) -> String {
        if action == .sendFollowUp, followUpProgress != .idle {
            return "\(c.label). \(Self.actionLabel(for: action, progress: followUpProgress))."
        }

        let verb: String
        switch action {
        case .handled:
            verb = "mark handled"
        case .sendFollowUp:
            verb = "send the standard follow-up email"
        case .adjust:
            verb = "adjust ownership or the next touch date"
        }
        return "\(c.label). Double-tap to \(verb)."
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
