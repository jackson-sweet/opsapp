//
//  LeadShareSummaryBuilder.swift
//  OPS
//
//  Share-lead-summary (feature request 6b2ef5de): a plain-text lead summary
//  the operator can text, email, or copy — name, contact, site, job,
//  notes, recent correspondence — plus the photo packet and a 2-D snapshot
//  of the lead's deck design when one exists.
//
//  The TEXT leaves the app and lands in front of clients and subs, so it is
//  plain professional English — no tactical chrome, no `//` prefixes, no
//  uppercase shouting. Sections with nothing to say are omitted entirely.
//

import Foundation
import UIKit

enum LeadShareSummaryBuilder {

    // MARK: - Text

    static let activityLineLimit = 5

    static func summaryText(
        for opportunity: Opportunity,
        activities: [Activity],
        now: Date = Date()
    ) -> String {
        var blocks: [String] = []

        blocks.append("LEAD — \(opportunity.displayContactName)\n\(opportunity.shortDisplayId)")

        var contact: [String] = []
        if !opportunity.contactName.isEmpty { contact.append(opportunity.contactName) }
        if let phone = opportunity.contactPhone, !phone.isEmpty { contact.append(phone) }
        if let email = opportunity.contactEmail, !email.isEmpty { contact.append(email) }
        if !contact.isEmpty {
            blocks.append("CONTACT\n" + contact.joined(separator: "\n"))
        }

        if let address = opportunity.address, !address.isEmpty {
            blocks.append("SITE\n" + address)
        }

        var job: [String] = []
        if let title = opportunity.title, !title.isEmpty { job.append(title) }
        if let value = opportunity.estimatedValue, value > 0 {
            job.append("Estimated value: \(formatMoney(value))")
        }
        if !job.isEmpty {
            blocks.append("JOB\n" + job.joined(separator: "\n"))
        }

        if let notes = opportunity.descriptionText, !notes.isEmpty {
            blocks.append("NOTES\n" + notes)
        }

        let activityBlock = activityLines(from: activities, now: now)
        if !activityBlock.isEmpty {
            blocks.append("ACTIVITY\n" + activityBlock.joined(separator: "\n"))
        }

        return blocks.joined(separator: "\n\n")
    }

    /// Newest-first, capped at `activityLineLimit`, with an honest tail count.
    static func activityLines(from activities: [Activity], now: Date = Date()) -> [String] {
        let sorted = activities.sorted { $0.createdAt > $1.createdAt }
        guard !sorted.isEmpty else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        var lines = sorted.prefix(activityLineLimit).map { activity in
            "\(formatter.string(from: activity.createdAt)) — \(label(for: activity))"
        }
        let remainder = sorted.count - activityLineLimit
        if remainder > 0 {
            lines.append("(+ \(remainder) earlier)")
        }
        return lines
    }

    static func label(for activity: Activity) -> String {
        if let subject = activity.subject, !subject.isEmpty { return subject }
        // Fall back to a readable form of the type ("phone_call" → "Phone call").
        let raw = activity.type.rawValue.replacingOccurrences(of: "_", with: " ")
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    static func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? String(Int(value)))
    }

    // MARK: - Packet assembly

    /// Everything the share sheet gets: the summary text, every lead photo
    /// (remote URLs downloaded concurrently — failures skipped, never block —
    /// plus queued local bytes), and the deck design's 2-D snapshot when the
    /// lead has one.
    @MainActor
    static func assemblePacket(
        opportunity: Opportunity,
        activities: [Activity],
        deckDesigns: [DeckDesign]
    ) async -> [Any] {
        var items: [Any] = [summaryText(for: opportunity, activities: activities)]

        // Photo packet — remote first (server order reversed = newest first).
        let remoteURLs = opportunity.images.filter { !$0.isEmpty }.reversed()
        let downloaded = await downloadImages(Array(remoteURLs))
        items.append(contentsOf: downloaded)

        for pending in LeadImageService.shared.queuedUploads(for: opportunity.id) {
            if let image = LeadImageService.shared.queuedImage(for: pending) {
                items.append(image)
            }
        }

        // 2-D deck snapshot.
        if let design = DeckDesign.displayCandidate(in: deckDesigns, forOpportunityId: opportunity.id),
           design.hasRenderableGeometry,
           let snapshot = DeckRenderer.renderToPNG(drawingData: design.drawingData) {
            items.append(snapshot)
        }

        return items
    }

    /// Concurrent downloads with a tight per-request timeout — a dead photo
    /// URL degrades the packet, never hangs the share.
    private static func downloadImages(_ urls: [String]) async -> [UIImage] {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        return await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, urlString) in urls.enumerated() {
                group.addTask {
                    guard let url = URL(string: urlString),
                          let (data, _) = try? await session.data(from: url),
                          let image = UIImage(data: data) else {
                        return (index, nil)
                    }
                    return (index, image)
                }
            }
            var results: [(Int, UIImage)] = []
            for await (index, image) in group {
                if let image { results.append((index, image)) }
            }
            // Preserve strip order regardless of download completion order.
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}
