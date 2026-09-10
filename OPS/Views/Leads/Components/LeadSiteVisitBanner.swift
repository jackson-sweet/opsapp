//
//  LeadSiteVisitBanner.swift
//  OPS
//
//  Bug 52cc8dae — the standing appointment, stated at the top of the dossier.
//
//  A booked site visit was already on this screen, but only as a value inside
//  the KPI strip's NEXT TOUCH cell, three lines down and behind a tap that
//  opened a sheet to find out what it was. When a lead has an appointment on
//  the calendar, that appointment IS the state of the lead: it is the reason
//  the operator opened the dossier, and the three things they might do about
//  it — go, move it, kill it — are the only actions that matter until it
//  passes. So it leads, directly under the header, and the verbs are on it.
//
//  It is the appointment's only statement on this screen: NEXT TOUCH went back
//  to the follow-up nudge rather than printing the same day and time again
//  200pt lower, truncated. The rest of the appointment — who is going, how
//  long, how far off — is one tap behind the headline, in the sheet that
//  already held it.
//
//  State-aware, never a menu of possibilities:
//    · no open booking          → nothing renders. No empty banner, no "—".
//    · booked, day not here yet → REBOOK / CANCEL. No START: a visit you are
//                                 not at cannot be started, and a button that
//                                 can only be wrong is worse than no button.
//    · booked, window open      → START leads, REBOOK / CANCEL behind it.
//    · no convert grant         → the FACT, and no verbs. That a visit is
//                                 booked is worth knowing to anyone who can
//                                 read the lead; acting on it is not.
//
//  No accent. The sticky bar's MARK WON keeps this screen's only accent
//  (DESIGN.md §3) — START earns its weight from the active white surface, the
//  same emphasis the design system gives an active toggle.
//

import SwiftUI

// MARK: - State (pure)

/// What the dossier's visit banner shows right now.
///
/// Resolved from the booking alone so the rule is assertable without a store:
/// a banner that appeared for a cancelled visit, or offered START three days
/// early, would be a worse defect than the missing banner it replaces.
enum LeadSiteVisitBannerState: Equatable {
    case hidden
    case booked(token: String, windowOpen: Bool)

    /// - Parameter scheduledAt: the lead's OPEN booking's time, or nil when it
    ///   has none. `SiteVisitBookingLookup.openBooking` is the one definition
    ///   of "open" — booked, still scheduled, not deleted — so a completed or
    ///   cancelled visit arrives here as nil and the banner disappears.
    static func resolve(
        scheduledAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LeadSiteVisitBannerState {
        guard let scheduledAt else { return .hidden }
        return .booked(
            token: SiteVisitBookingLookup.bookedToken(
                for: scheduledAt,
                now: now,
                calendar: calendar
            ),
            // The same today-rule the appointment sheet and the calendar's
            // branch dialog use: START is honest from the morning of the visit
            // day onward.
            windowOpen: calendar.isDate(scheduledAt, inSameDayAs: now)
                || scheduledAt <= now
        )
    }

    var token: String? {
        if case let .booked(token, _) = self { return token }
        return nil
    }

    var windowOpen: Bool {
        if case let .booked(_, open) = self { return open }
        return false
    }
}

// MARK: - Banner

/// Value-driven by design (SiteVisitAppointmentContent's discipline): resolved
/// values in, pixels out, so the snapshot harness renders every state without
/// a ModelContainer or a signed-in controller.
struct LeadSiteVisitBanner: View {
    let state: LeadSiteVisitBannerState
    /// The convert grant. Facts are readable by anyone who can read the lead;
    /// the verbs are not.
    let canManage: Bool
    /// The cancel RPC is in flight — every verb stands down rather than
    /// offering a second press against a write already going out.
    var isCancelling: Bool = false
    var onStart: () -> Void = {}
    var onRebook: () -> Void = {}
    var onCancel: () -> Void = {}
    /// The rest of the appointment — who is going, how long, how far off.
    /// The banner states the commitment and the three verbs; the sheet behind
    /// the headline holds the detail nobody needs at a glance. Nil renders a
    /// plain, inert headline (snapshot and preview hosts).
    var onDetails: (() -> Void)? = nil

    static let accessibilityID = "lead-site-visit-banner"

    var body: some View {
        if case let .booked(token, windowOpen) = state {
            // The headline carries its own 44pt row, so the stack rides tight
            // against it rather than adding a second gap.
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                headline(token)

                if canManage {
                    actions(windowOpen: windowOpen)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Solid command surface + the mobile-bright tan edge. Tan is the
            // site-visit semantic (DESIGN.md §3); the -M line clears the
            // outdoor-glare contrast commandCard(tone:)'s 0.30 border would not
            // — the same treatment WonNotConvertedCard gives its olive.
            .commandCard()
            .overlay(
                RoundedRectangle(
                    cornerRadius: OPSStyle.Layout.panelRadius,
                    style: .continuous
                )
                .strokeBorder(OPSStyle.Colors.tanLineM, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .accessibilityIdentifier(Self.accessibilityID)
        }
    }

    @ViewBuilder
    private func headline(_ token: String) -> some View {
        if let onDetails {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDetails()
            } label: {
                headlineRow(token, showsDisclosure: true)
            }
            .buttonStyle(PlainButtonStyle())
            .bugReportPickable(.button, label: "SITE VISIT · \(token)")
            .accessibilityLabel("Site visit booked, \(token.lowercased()). Opens visit details")
        } else {
            headlineRow(token, showsDisclosure: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Site visit booked, \(token.lowercased())")
        }
    }

    private func headlineRow(_ token: String, showsDisclosure: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("SITE VISIT · \(token)")
                    .foregroundColor(OPSStyle.Colors.tanTextM)
            }
            .font(OPSStyle.Typography.miniLabel)
            .fontWeight(.semibold)
            .kerning(1.6)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func actions(windowOpen: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if windowOpen {
                verb(
                    "START",
                    emphasis: .lead,
                    action: onStart,
                    spoken: "Start this site visit"
                )
            }
            verb(
                "REBOOK",
                emphasis: .standard,
                action: onRebook,
                spoken: "Move this site visit"
            )
            verb(
                "CANCEL",
                emphasis: .destructive,
                action: onCancel,
                spoken: "Cancel this site visit"
            )
        }
        .disabled(isCancelling)
        .opacity(isCancelling ? OPSStyle.Layout.suspendedOpacity : 1)
    }

    /// Three weights, no accent. LEAD is the active-toggle surface — the
    /// design system's way of saying "this one" without spending the screen's
    /// single accent (MOBILE.md §9 toggles, DESIGN.md §9).
    private enum Emphasis {
        case lead
        case standard
        case destructive
    }

    private func verb(
        _ label: String,
        emphasis: Emphasis,
        action: @escaping () -> Void,
        spoken: String
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(
                style: emphasis == .lead ? .medium : .light
            ).impactOccurred()
            action()
        } label: {
            Text(label)
                .font(OPSStyle.Typography.buttonLabel)
                .kerning(0.27)
                .textCase(.uppercase)
                .foregroundColor(foreground(emphasis))
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                    .fill(fill(emphasis))
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                    .strokeBorder(border(emphasis), lineWidth: OPSStyle.Layout.Border.standard)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .bugReportPickable(.button, label: label)
        .accessibilityLabel(spoken)
    }

    private func foreground(_ emphasis: Emphasis) -> Color {
        switch emphasis {
        case .lead:        return OPSStyle.Colors.text
        case .standard:    return OPSStyle.Colors.text2
        case .destructive: return OPSStyle.Colors.roseTextM
        }
    }

    private func fill(_ emphasis: Emphasis) -> Color {
        switch emphasis {
        case .lead:        return OPSStyle.Colors.surfaceActive
        case .standard:    return OPSStyle.Colors.surfaceInput
        case .destructive: return Color.clear
        }
    }

    private func border(_ emphasis: Emphasis) -> Color {
        switch emphasis {
        // The app's active-control hairline — the same edge an active filter
        // chip carries, so emphasis without the accent looks the same
        // everywhere.
        case .lead:        return OPSStyle.Colors.lineActive
        case .standard:    return OPSStyle.Colors.line
        case .destructive: return OPSStyle.Colors.roseLineM
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Lead site visit banner") {
    VStack(spacing: OPSStyle.Layout.spacing3) {
        LeadSiteVisitBanner(
            state: .booked(token: "TODAY 2:00PM", windowOpen: true),
            canManage: true
        )
        LeadSiteVisitBanner(
            state: .booked(token: "TUE 2:00PM", windowOpen: false),
            canManage: true
        )
        LeadSiteVisitBanner(
            state: .booked(token: "TUE 2:00PM", windowOpen: false),
            canManage: false
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.top, OPSStyle.Layout.spacing4)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
