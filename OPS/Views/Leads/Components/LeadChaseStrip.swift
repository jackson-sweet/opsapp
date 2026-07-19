//
//  LeadChaseStrip.swift
//  OPS
//
//  THE chase control (Leads redesign spec §2.3 / §5.6) — one 44pt strip,
//  two hosts: the triage card and the lead detail. State left, action chip
//  right:
//
//      → CHASE · 3D LATE        [HANDLED ✓]     rose    (overdue)
//      → DUE TODAY              [HANDLED ✓]     tan
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
    var onHandled: () -> Void = {}
    var onAdjust: () -> Void = {}

    enum Action { case handled, adjust }

    var body: some View {
        let c = chase
        if let action = c.action, canAct {
            Button {
                // Medium impact — flipping the ball is a commit moment (spec §10).
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if action == .handled { onHandled() } else { onAdjust() }
            } label: {
                stripBody(c, showsAction: true)
            }
            .buttonStyle(.plain)
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
                Text(action == .handled ? "HANDLED ✓" : "ADJUST")
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
        let verb = action == .handled ? "mark handled" : "adjust the comeback date"
        return "\(c.label). Double-tap to \(verb)."
    }

    // MARK: - Ages & vocabulary

    /// Age of the unanswered inbound — hours under a day, days after.
    private var yourMoveAge: String {
        guard let inbound = lead.lastInboundAt else { return "NOW" }
        let hours = Int(Date().timeIntervalSince(inbound) / 3600)
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
