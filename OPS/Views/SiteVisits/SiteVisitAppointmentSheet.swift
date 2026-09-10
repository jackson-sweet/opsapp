//
//  SiteVisitAppointmentSheet.swift
//  OPS
//
//  The booked appointment behind the lead's NEXT TOUCH cell: what is
//  booked, how long until it, who is going — and the two verbs that matter
//  (START NOW when the day arrives, REBOOK to move it). Facts are readable
//  by anyone who can read the lead; verbs are gated by the convert grant.
//
//  Self-healing: the sheet re-resolves its booking from the store on every
//  SiteVisitBookingChanged and dismisses itself when the booking is gone
//  (cancelled here, started or cancelled on another device).
//

import SwiftUI
import SwiftData
import UIKit

struct SiteVisitAppointmentSheet: View {
    let lead: Opportunity
    /// Convert-grant gate, computed by the host (LeadDetailView.canConvert).
    let canManage: Bool
    /// Host-owned start: dismisses this sheet and raises the ONE capture cover.
    let onStartNow: () -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: BookSiteVisitForm.BookingSnapshot?
    @State private var bookingRequest: BookSiteVisitRequest?

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            if let snapshot {
                SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    SiteVisitAppointmentContent(
                        leadName: lead.displayContactName,
                        address: lead.address,
                        scheduledAt: snapshot.scheduledAt,
                        durationMinutes: snapshot.durationMinutes,
                        crewSummary: crewSummary(snapshot),
                        crewMembers: crewMembers(snapshot),
                        now: timeline.date,
                        showsStartNow: canManage && startIsAvailable(snapshot, now: timeline.date),
                        showsRebook: canManage,
                        onStartNow: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onStartNow()
                        },
                        onRebook: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            bookingRequest = BookSiteVisitRequest(lead: lead, existing: snapshot)
                        }
                    )
                }
            } else {
                ProgressView()
                    .tint(OPSStyle.Colors.text2)
            }
        }
        .colorScheme(.dark)
        .onAppear { resolveBooking() }
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("SiteVisitBookingChanged"))
        ) { _ in
            resolveBooking()
        }
        .sheet(item: $bookingRequest) { request in
            BookSiteVisitSheet(request: request)
                .environmentObject(dataController)
        }
    }

    // MARK: - Resolution

    /// START is honest from the morning of the visit day onward — the same
    /// today-rule the calendar's branch dialog uses (DayCanvasView).
    private func startIsAvailable(_ snapshot: BookSiteVisitForm.BookingSnapshot, now: Date) -> Bool {
        // The visit day only. A booking from an earlier day that nobody started
        // is missed, not late — its remedy is REBOOK (bug 2b085519).
        Calendar.current.isDate(snapshot.scheduledAt, inSameDayAs: now)
    }

    @MainActor
    private func resolveBooking() {
        guard let context = dataController.modelContext,
              let booking = SiteVisitBookingLookup.openBooking(
                forOpportunityId: lead.id,
                in: context
              ),
              let resolved = SiteVisitBookingLookup.snapshot(of: booking) else {
            // Booking gone — cancelled, started, or completed. The cell that
            // opened this sheet is already reverting; follow it out.
            dismiss()
            return
        }
        snapshot = resolved
    }

    private func crewMembers(_ snapshot: BookSiteVisitForm.BookingSnapshot) -> [User] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        var members = dataController.getTeamMembers(companyId: companyId)
        if let me = dataController.currentUser, !members.contains(where: { $0.id == me.id }) {
            members.append(me)
        }
        let assigned = Set(snapshot.assigneeIds.map { $0.lowercased() })
        return members
            .filter { assigned.contains($0.id.lowercased()) }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private func crewSummary(_ snapshot: BookSiteVisitForm.BookingSnapshot) -> String {
        let members = crewMembers(snapshot)
        let meId = dataController.currentUser?.id.lowercased()
        if snapshot.assigneeIds.map({ $0.lowercased() }) == [meId].compactMap({ $0 }) {
            return "You"
        }
        if members.count <= 1 { return members.first?.fullName ?? "You" }
        return "\(members.count) going"
    }
}

// MARK: - Content (value-driven, snapshot-provable)

/// Dumb by design (LeadSiteVisitPanel's discipline): resolved values in,
/// pixels out — the snapshot harness renders every state without a store.
struct SiteVisitAppointmentContent: View {
    let leadName: String
    let address: String?
    let scheduledAt: Date
    let durationMinutes: Int
    let crewSummary: String
    let crewMembers: [User]
    let now: Date
    let showsStartNow: Bool
    let showsRebook: Bool
    let onStartNow: () -> Void
    let onRebook: () -> Void

    private var countdownToken: String? {
        SiteVisitCountdown.token(until: scheduledAt, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            countdownBlock

            windowLine

            crewLine

            Spacer(minLength: 0)

            actions
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing4)
        .padding(.bottom, OPSStyle.Layout.spacing3_5)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("// SITE VISIT")
                .font(OPSStyle.Typography.nanoLabel)
                .tracking(1.2)
                .foregroundColor(OPSStyle.Colors.text3)

            Text(leadName)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            if let address, !address.isEmpty {
                Text(address)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Booked for a day that has already gone and never started — overdue,
    /// so rose, and the number is how long ago rather than a window that
    /// closed days back (bug 2b085519).
    private var isMissed: Bool {
        scheduledAt < Calendar.current.startOfDay(for: now)
    }

    /// The number the sheet exists for. Window open = tan (attention, the
    /// site-visit semantic), missed = rose, otherwise neutral. Mono, always.
    private var countdownBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(isMissed ? "// MISSED" : (countdownToken == nil ? "// VISIT WINDOW OPEN" : "// UNTIL VISIT"))
                .font(OPSStyle.Typography.nanoLabel)
                .tracking(1.2)
                .foregroundColor(
                    isMissed
                        ? OPSStyle.Colors.roseTextM
                        : (countdownToken == nil ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.text3)
                )

            Text(isMissed ? DaySheetDateToken.age(scheduledAt, now: now) : (countdownToken ?? "NOW"))
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isMissed
                ? "Visit missed, \(DaySheetDateToken.age(scheduledAt, now: now).lowercased())"
                : countdownToken.map { "Time until visit, \($0.lowercased())" } ?? "Visit window open"
        )
    }

    private var windowLine: some View {
        Text("\(DaySheetDateToken.day(scheduledAt, now: now)) · \(Self.windowText(start: scheduledAt, durationMinutes: durationMinutes))")
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .monospacedDigit()
    }

    private var crewLine: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: -6) {
                ForEach(Array(crewMembers.prefix(3)), id: \.id) { user in
                    UserAvatar(user: user, size: 28)
                        .overlay(
                            Circle()
                                .stroke(OPSStyle.Colors.background, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
            }
            Text(crewSummary)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Going, \(crewSummary)")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            if showsStartNow {
                OPSPrimaryButton(title: "START NOW", action: onStartNow)
            }
            if showsRebook {
                Button(action: onRebook) {
                    Text("REBOOK")
                        .font(OPSStyle.Typography.buttonLabel)
                        .kerning(0.27)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Rebook this visit")
            }
        }
    }

    private static func windowText(start: Date, durationMinutes: Int) -> String {
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return "\(timeFormatter.string(from: start).uppercased()) – \(timeFormatter.string(from: end).uppercased())"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

// MARK: - Previews

#if DEBUG
#Preview("Appointment / future") {
    SiteVisitAppointmentContent(
        leadName: "Kim Berelliee",
        address: "903 Collinson St, Victoria, BC",
        scheduledAt: Date().addingTimeInterval(3_600 * 52),
        durationMinutes: 60,
        crewSummary: "You",
        crewMembers: [],
        now: Date(),
        showsStartNow: false,
        showsRebook: true,
        onStartNow: {},
        onRebook: {}
    )
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("Appointment / window open") {
    SiteVisitAppointmentContent(
        leadName: "Kim Berelliee",
        address: "903 Collinson St, Victoria, BC",
        scheduledAt: Date().addingTimeInterval(-600),
        durationMinutes: 60,
        crewSummary: "2 going",
        crewMembers: [],
        now: Date(),
        showsStartNow: true,
        showsRebook: true,
        onStartNow: {},
        onRebook: {}
    )
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
