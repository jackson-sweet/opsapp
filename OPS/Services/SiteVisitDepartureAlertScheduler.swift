//
//  SiteVisitDepartureAlertScheduler.swift
//  OPS
//
//  The one prompt the device owns: "time to leave", computed from live
//  drive-time. The server owns heads-up and START pushes (it can reach an
//  assignee whose app never opened); only departure needs location, so only
//  departure lives here.
//
//  Silently absent by design when location permission or a lead address is
//  missing — the heads-up and START pushes still cover the visit, and
//  prompting for location over a nicety would be noise. Never fires after the
//  visit starts: every refresh cancels first, and start/cancel/reschedule/
//  unassign all trigger a refresh.
//

import CoreLocation
import Foundation
import MapKit
import SwiftData
import UIKit
import UserNotifications

// MARK: - Seams

/// Driving ETA to a postal address, nil when it cannot be answered (no
/// location permission, no fix, geocode miss, no route). Production adapter
/// wraps CLGeocoder + MKDirections; tests inject fixed answers.
protocol DrivingETAProviding: Sendable {
    func drivingETA(toAddress address: String) async -> TimeInterval?
}

/// The slice of UNUserNotificationCenter this scheduler touches. `leadId`
/// rides the payload so a tap routes into the lead like the server prompts.
protocol DepartureNotificationScheduling: Sendable {
    func pendingDepartureIds() async -> [String]
    func cancel(ids: [String]) async
    func schedule(id: String, title: String, body: String, fireDate: Date, leadId: String) async
}

// MARK: - Pure math

enum SiteVisitDepartureMath {
    /// Fire at `scheduled_at − ETA − buffer`. Nil when that moment already
    /// passed — a late alert is worse than none.
    static func fireDate(
        scheduledAt: Date,
        etaSeconds: TimeInterval,
        bufferSeconds: TimeInterval = 300,
        now: Date
    ) -> Date? {
        let fire = scheduledAt.addingTimeInterval(-(etaSeconds + bufferSeconds))
        return fire > now ? fire : nil
    }

    static func notificationId(visitId: String) -> String {
        "site-visit-departure-\(visitId.lowercased())"
    }

    /// "~25 min drive. Visit at 10:30 AM."
    static func body(etaSeconds: TimeInterval, scheduledAt: Date, calendar: Calendar = .current) -> String {
        let minutes = max(1, Int((etaSeconds / 60).rounded()))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return "~\(minutes) min drive. Visit at \(formatter.string(from: scheduledAt))."
    }
}

// MARK: - Candidate

/// One visit the refresh pass considers — resolved from SwiftData by the
/// caller so the scheduler core stays fetch-free and provable.
struct DepartureAlertCandidate: Equatable {
    let visitId: String
    let leadId: String
    let leadName: String
    let address: String
    let scheduledAt: Date
}

// MARK: - Scheduler

final class SiteVisitDepartureAlertScheduler: @unchecked Sendable {
    /// Live instance — CLGeocoder + MKDirections + UNUserNotificationCenter.
    static let shared = SiteVisitDepartureAlertScheduler(
        etaProvider: LiveDrivingETAProvider(),
        notifications: LiveDepartureNotificationScheduler()
    )

    private let etaProvider: DrivingETAProviding
    private let notifications: DepartureNotificationScheduling
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []

    init(
        etaProvider: DrivingETAProviding,
        notifications: DepartureNotificationScheduling,
        now: @escaping () -> Date = Date.init
    ) {
        self.etaProvider = etaProvider
        self.notifications = notifications
        self.now = now
    }

    /// Wire the refresh triggers: foreground (the morning-of case) and any
    /// booking change (book / reschedule / cancel locally; starts, unassigns,
    /// and remote changes arrive via the inbound router posting the same
    /// event). Idempotent — call once at launch.
    @MainActor
    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { await SiteVisitDepartureAlertScheduler.shared.refreshFromStore() }
            }
        )
        observers.append(
            center.addObserver(
                forName: Notification.Name("SiteVisitBookingChanged"),
                object: nil,
                queue: .main
            ) { _ in
                Task { await SiteVisitDepartureAlertScheduler.shared.refreshFromStore() }
            }
        )
    }

    /// Resolve today's candidates from the live store and refresh. Silently a
    /// no-op without a signed-in user or a main context.
    func refreshFromStore() async {
        let resolved: [DepartureAlertCandidate] = await MainActor.run {
            guard let context = ModelContainerHolder.mainContext,
                  let userId = UserDefaults.standard.string(forKey: "currentUserId"),
                  !userId.isEmpty else { return [] }
            return Self.candidates(in: context, userId: userId)
        }
        await refresh(candidates: resolved)
    }

    /// Cancel-then-schedule for today's eligible candidates. Cancelling first
    /// means a started, cancelled, rescheduled-away, or unassigned visit loses
    /// its pending alert by simply not being a candidate anymore.
    func refresh(candidates: [DepartureAlertCandidate]) async {
        let stale = await notifications.pendingDepartureIds()
        if !stale.isEmpty {
            await notifications.cancel(ids: stale)
        }

        for candidate in candidates {
            guard let eta = await etaProvider.drivingETA(toAddress: candidate.address) else {
                continue
            }
            let reference = now()
            guard let fireDate = SiteVisitDepartureMath.fireDate(
                scheduledAt: candidate.scheduledAt,
                etaSeconds: eta,
                now: reference
            ) else { continue }

            await notifications.schedule(
                id: SiteVisitDepartureMath.notificationId(visitId: candidate.visitId),
                title: "Time to leave — \(candidate.leadName)",
                body: SiteVisitDepartureMath.body(etaSeconds: eta, scheduledAt: candidate.scheduledAt),
                fireDate: fireDate,
                leadId: candidate.leadId
            )
        }
    }

    // MARK: - Candidate resolution (SwiftData boundary)

    /// Today's booked, still-scheduled visits assigned to `userId` whose lead
    /// has an address. Everything else is silently ineligible.
    @MainActor
    static func candidates(
        in context: ModelContext,
        userId: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DepartureAlertCandidate] {
        let canonicalUser = userId.lowercased()
        let descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate<SiteVisit> {
                $0.bookedAt != nil && $0.deletedAt == nil
            }
        )
        let visits = (try? context.fetch(descriptor)) ?? []
        return visits.compactMap { visit -> DepartureAlertCandidate? in
            guard visit.status == .scheduled,
                  let scheduledAt = visit.scheduledAt,
                  scheduledAt > now,
                  calendar.isDate(scheduledAt, inSameDayAs: now),
                  visit.assigneeIds.contains(canonicalUser),
                  let opportunityId = visit.opportunityId
            else { return nil }

            let leadDescriptor = FetchDescriptor<Opportunity>(
                predicate: #Predicate<Opportunity> { $0.id == opportunityId }
            )
            guard let lead = try? context.fetch(leadDescriptor).first,
                  let address = lead.address, !address.isEmpty
            else { return nil }

            return DepartureAlertCandidate(
                visitId: visit.id,
                leadId: lead.id,
                leadName: lead.displayContactName,
                address: address,
                scheduledAt: scheduledAt
            )
        }
    }
}

// MARK: - Live adapters

/// CLGeocoder + MKDirections, answering nil unless the app already holds a
/// location grant — this feature never prompts for location.
final class LiveDrivingETAProvider: DrivingETAProviding {
    func drivingETA(toAddress address: String) async -> TimeInterval? {
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }
        guard let destination = try? await CLGeocoder().geocodeAddressString(address).first,
              let location = destination.location else {
            return nil
        }

        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.transportType = .automobile

        guard let response = try? await MKDirections(request: request).calculateETA() else {
            return nil
        }
        return response.expectedTravelTime
    }
}

final class LiveDepartureNotificationScheduler: DepartureNotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    func pendingDepartureIds() async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("site-visit-departure-") }
    }

    func cancel(ids: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func schedule(id: String, title: String, body: String, fireDate: Date, leadId: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // A tap routes like the server prompts: open the lead.
        content.userInfo = ["type": "site_visit_heads_up", "leadId": leadId]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
