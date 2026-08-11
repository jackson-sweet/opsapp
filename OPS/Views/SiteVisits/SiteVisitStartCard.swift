//
//  SiteVisitStartCard.swift
//  OPS
//
//  The visit-day card: from the morning of a booked visit, the assigned
//  operator's leads surface leads with the appointment — name, time, address,
//  START. It persists until the visit starts, the operator dismisses it, or
//  the day ends. Dismissal kills the card only — the server's heads-up and
//  START pushes are untouched (the card is a convenience, the pushes are the
//  contract).
//
//  No accent: on the day sheet the milestone button owns the screen's one
//  accent slot, so START uses the inverted white CTA — commanding without
//  breaking the accent contract.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Dismissal store

/// Per-visit, per-day dismissal. Keying by day means a rescheduled visit's
/// card returns on its new day with zero bookkeeping.
struct SiteVisitStartCardStore {
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    private func key(visitId: String, day: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let stamp = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
        return "site-visit-start-card-dismissed-\(visitId.lowercased())-\(stamp)"
    }

    func isDismissed(visitId: String, day: Date = Date()) -> Bool {
        defaults.bool(forKey: key(visitId: visitId, day: day))
    }

    func dismiss(visitId: String, day: Date = Date()) {
        defaults.set(true, forKey: key(visitId: visitId, day: day))
    }
}

// MARK: - Candidate logic

enum SiteVisitStartCardCandidates {
    /// Today's booked, still-scheduled visits assigned to `userId`, newest
    /// appointment first — minus the ones dismissed today.
    static func resolve(
        visits: [SiteVisit],
        userId: String,
        store: SiteVisitStartCardStore,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SiteVisit] {
        let canonicalUser = userId.lowercased()
        return visits
            .filter { visit in
                visit.isBookedAppointment
                    && visit.deletedAt == nil
                    && visit.status == .scheduled
                    && visit.assigneeIds.contains(canonicalUser)
                    && (visit.scheduledAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
                    && !store.isDismissed(visitId: visit.id, day: now)
            }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }
}

// MARK: - Host

/// The visit-day cards above the leads surfaces. @Query keeps the set live
/// (booking, start, cancel, and inbound sync all mutate SiteVisit rows);
/// `dismissalTick` re-evaluates after a dismissal since UserDefaults is not
/// observable.
struct SiteVisitStartCardsHost: View {
    let currentUserId: String?
    let onStart: (Opportunity) -> Void

    @Query private var allVisits: [SiteVisit]
    @Query private var allLeads: [Opportunity]
    @State private var dismissalTick = 0

    private let store = SiteVisitStartCardStore()

    private var candidates: [SiteVisit] {
        guard let currentUserId else { return [] }
        _ = dismissalTick
        return SiteVisitStartCardCandidates.resolve(
            visits: allVisits,
            userId: currentUserId,
            store: store
        )
    }

    private func lead(for visit: SiteVisit) -> Opportunity? {
        guard let opportunityId = visit.opportunityId else { return nil }
        return allLeads.first { $0.id == opportunityId }
    }

    var body: some View {
        let cards = candidates
        if !cards.isEmpty {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(cards, id: \.id) { visit in
                    if let lead = lead(for: visit), let scheduledAt = visit.scheduledAt {
                        SiteVisitStartCard(
                            leadName: lead.displayContactName,
                            address: lead.address,
                            scheduledAt: scheduledAt,
                            onStart: { onStart(lead) },
                            onDismiss: {
                                store.dismiss(visitId: visit.id)
                                dismissalTick += 1
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }
}

// MARK: - Card

struct SiteVisitStartCard: View {
    let leadName: String
    let address: String?
    let scheduledAt: Date
    let onStart: () -> Void
    let onDismiss: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma"
        return formatter
    }()

    private var timeToken: String {
        Self.timeFormatter.string(from: scheduledAt).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text("// SITE VISIT — \(timeToken)")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .tracking(1.2)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .monospacedDigit()

                Spacer(minLength: 0)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    Image(systemName: OPSStyle.Icons.close)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(width: OPSStyle.Layout.touchTargetMin,
                               height: OPSStyle.Layout.touchTargetMin,
                               alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Dismiss visit card")
            }

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(leadName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let address, !address.isEmpty {
                    Text(address)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onStart()
            } label: {
                Text("START")
                    .font(OPSStyle.Typography.buttonLabel)
                    .kerning(0.27)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                            .fill(OPSStyle.Colors.primaryText)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Start site visit for \(leadName)")
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
        .accessibilityElement(children: .contain)
    }
}
