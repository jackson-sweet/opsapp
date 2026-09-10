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

/// Today's visits rail above the leads surfaces (f77d38fc — replaces the
/// stacked START cards). @Query keeps the set live (booking, start, cancel,
/// and inbound sync all mutate SiteVisit rows); `dismissalTick` re-evaluates
/// after a dismissal since UserDefaults is not observable.
struct SiteVisitStartCardsHost: View {
    let currentUserId: String?
    let onStart: (Opportunity) -> Void
    let onOpen: (Opportunity) -> Void

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

    private var entries: [(visit: SiteVisit, lead: Opportunity, entry: SiteVisitTodayRail.Entry)] {
        candidates.compactMap { visit in
            guard let lead = lead(for: visit), let scheduledAt = visit.scheduledAt else { return nil }
            return (
                visit,
                lead,
                SiteVisitTodayRail.Entry(
                    id: visit.id,
                    leadName: lead.displayContactName,
                    address: lead.address,
                    scheduledAt: scheduledAt
                )
            )
        }
    }

    var body: some View {
        let resolved = entries
        if !resolved.isEmpty {
            SiteVisitTodayRail(
                entries: resolved.map { $0.entry },
                onOpen: { id in
                    guard let match = resolved.first(where: { $0.visit.id == id }) else { return }
                    onOpen(match.lead)
                },
                onStart: { id in
                    guard let match = resolved.first(where: { $0.visit.id == id }) else { return }
                    onStart(match.lead)
                },
                onDismiss: { id in
                    store.dismiss(visitId: id)
                    dismissalTick += 1
                }
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }
}

// MARK: - Rail

/// One compact panel for the day's booked visits: a mono header, time-led
/// rows, and a small START chip as the only verb. Tapping a row opens the
/// lead; dismissing for the day lives behind a long-press so it never
/// competes with starting. Height for two visits is roughly half the old
/// stacked cards.
struct SiteVisitTodayRail: View {
    struct Entry: Identifiable, Equatable {
        let id: String
        let leadName: String
        let address: String?
        let scheduledAt: Date
    }

    let entries: [Entry]
    let onOpen: (String) -> Void
    let onStart: (String) -> Void
    let onDismiss: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(SiteVisitTodayRailCopy.header(count: entries.count))
                .font(OPSStyle.Typography.miniLabelBold)
                .tracking(1.2)
                .foregroundColor(OPSStyle.Colors.text3)
                .padding(.bottom, OPSStyle.Layout.spacing2)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle()
                        .fill(OPSStyle.Colors.line)
                        .frame(height: OPSStyle.Layout.Border.standard)
                }
                SiteVisitTodayRow(
                    entry: entry,
                    onOpen: { onOpen(entry.id) },
                    onStart: { onStart(entry.id) },
                    onDismiss: { onDismiss(entry.id) }
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .glassSurface()
        .animation(reduceMotion ? nil : OPSStyle.Animation.standard, value: entries.map(\.id))
        .accessibilityElement(children: .contain)
    }
}

/// Header and time copy for the rail — pure, so the words are testable.
enum SiteVisitTodayRailCopy {
    static let start = "START"
    static let dismissForToday = "DISMISS FOR TODAY"

    static func header(count: Int) -> String {
        "// TODAY · \(count) \(count == 1 ? "VISIT" : "VISITS")"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// `2:00 PM` — mono, tabular, uppercase meridiem.
    static func timeToken(_ date: Date) -> String {
        timeFormatter.string(from: date).uppercased()
    }
}

// MARK: - Row

struct SiteVisitTodayRow: View {
    let entry: SiteVisitTodayRail.Entry
    let onOpen: () -> Void
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing3) {
                Text(SiteVisitTodayRailCopy.timeToken(entry.scheduledAt))
                    .font(OPSStyle.Typography.dataValue)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.text)
                    .fixedSize(horizontal: true, vertical: false)

                // The chip shares the name line; the address takes the whole
                // text column beneath it, so the street never truncates behind
                // the verb — the "where" is the point of the row.
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                        Text(entry.leadName)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: OPSStyle.Layout.spacing2)

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onStart()
                        } label: {
                            Text(SiteVisitTodayRailCopy.start)
                                .kerning(0.27)
                        }
                        .opsSecondaryCompactButtonStyle()
                        .accessibilityLabel("Start site visit for \(entry.leadName)")
                    }
                    if let address = entry.address, !address.isEmpty {
                        Text(address)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open lead for \(entry.leadName)")
        .contextMenu {
            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Label(SiteVisitTodayRailCopy.dismissForToday, systemImage: OPSStyle.Icons.close)
            }
        }
    }
}
