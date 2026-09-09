//
//  NotificationInboxGrouping.swift
//  OPS
//
//  Collapses the rail's unroutable inbox notifications into ONE honest row.
//
//  Bug 589e3b1e — the operator opened NOTIFICATIONS and found a wall of
//  identical "Reply waiting, no owner" rows, every one of which dead-tapped.
//  Verified in prod (2026-09-09): 89 such rows, all unread; 85 of their email
//  threads carry `opportunity_id = NULL`. There is no lead to open, so iOS
//  resolved the thread, found nothing, and fell back to the LEADS tab — the
//  tap that goes nowhere the operator described.
//
//  The generator half (a per-thread row for a thread with no lead) is filed to
//  the web session as bug fc7eebd9. The iOS half is this file: when a row's
//  ONLY routing signal is an email thread, and that thread resolves to no
//  lead, the row joins one group instead of standing alone. The group says
//  what it is, how many there are, and where they can actually be handled.
//
//  Resolution rules — deliberately conservative, because a wrong group is a
//  lie the operator cannot see through:
//    • A thread id ABSENT from `threadLeads` is UNRESOLVED. It renders as its
//      own row, exactly as before. Offline, or a failed read, groups nothing.
//    • A thread id PRESENT with a nil / blank opportunity id is resolved-to-
//      nothing: either the thread has no lead, or RLS hides it from this
//      operator. Either way the app cannot route it, so it joins the group.
//    • A row carrying a `project_id`, an opportunity id in its action url, or
//      an opportunity id in its dedupe key is never grouped — it has a live
//      destination and keeps opening it.
//

import Foundation

// MARK: - The group

/// One rail row standing in for every inbox notification whose email thread
/// resolves to no lead.
struct UnlinkedInboxGroup: Equatable, Identifiable {
    /// Stable for the life of the list so the expand/collapse latch survives a
    /// reload. Namespaced so it can never collide with a notification uuid.
    static let rowId = "ops.notifications.unlinked-inbox-group"

    /// One distinct server title inside the group, with how many rows carry it.
    struct Source: Equatable {
        let title: String
        let count: Int
    }

    /// Member notification ids in list order (newest first).
    let memberIds: [String]
    /// `created_at` of the newest member — buckets the row into TODAY / THIS
    /// WEEK / LAST WEEK exactly where its newest member would have landed.
    let newestCreatedAt: String
    /// Members still unread.
    let unreadCount: Int
    /// True only when EVERY member may be marked read under
    /// `NotificationReadPolicy`. A persistent row represents an unresolved
    /// condition; marking one read from the rail would masquerade as recovery,
    /// so a group holding even one persistent member offers no read action.
    let isMarkReadPermitted: Bool
    /// Distinct server titles inside the group, densest first, first-seen order
    /// breaking ties. The expanded row renders these as its readout — the rows
    /// this one replaced, named and counted.
    let sources: [Source]

    var id: String { Self.rowId }
    var count: Int { memberIds.count }
    var isRead: Bool { unreadCount == 0 }
}

// MARK: - List item

/// A row in the notification rail: one server notification, or the synthetic
/// group standing in for the unroutable inbox pile.
enum NotificationListItem: Identifiable {
    case single(NotificationDTO)
    case unlinkedInbox(UnlinkedInboxGroup)

    var id: String {
        switch self {
        case .single(let notification): return notification.id
        case .unlinkedInbox(let group):  return group.id
        }
    }

    /// Timestamp the rail buckets and sorts on.
    var createdAt: String {
        switch self {
        case .single(let notification): return notification.createdAt
        case .unlinkedInbox(let group):  return group.newestCreatedAt
        }
    }

    var isRead: Bool {
        switch self {
        case .single(let notification): return notification.isRead
        case .unlinkedInbox(let group):  return group.isRead
        }
    }
}

// MARK: - Grouping

enum NotificationInboxGrouping {

    // MARK: Copy

    /// Rail copy for the group. Kept beside the rule so the sentence can never
    /// drift from what the rule actually proves.
    enum Copy {
        /// Rendered uppercase by the row, like every other rail title.
        static let title = "Inbox replies waiting"
        static let markReadLabel = "MARK READ"
        /// Stand-in for a member whose server title is blank.
        static let untitledSource = "Untitled"

        /// The sentence that follows the mono count. Split so the count can be
        /// rendered in JetBrains Mono — numbers are always mono (DESIGN.md §4).
        static func bodySuffix(count: Int) -> String {
            count == 1
                ? " customer reply with no lead attached. Handle it on the web."
                : " customer replies with no lead attached. Handle them on the web."
        }

        /// The whole sentence, count included. Used for the row's accessibility
        /// label and by the tests; the view composes the two halves itself.
        static func body(count: Int) -> String {
            "\(count)" + bodySuffix(count: count)
        }
    }

    // MARK: Rule

    /// The thread id this row would have to resolve before it can open
    /// anything — or nil when the row has a destination of its own.
    ///
    /// Nil is returned when the row carries a project, when it is not claimed
    /// by lead routing at all, or when an opportunity id is recoverable from
    /// the action url / dedupe key. Only a row whose sole routing signal is an
    /// email thread can end up in the group.
    static func emailThreadRouteId(for notification: NotificationDTO) -> String? {
        if let projectId = notification.projectId,
           !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        guard LeadNotificationRouteParser.isLeadNotification(
            type: notification.type,
            deepLinkType: notification.deepLinkType,
            actionUrl: notification.actionUrl,
            dedupeKey: notification.dedupeKey
        ) else { return nil }

        guard case .emailThread(let threadId) = LeadNotificationRouteParser.route(
            actionUrl: notification.actionUrl,
            dedupeKey: notification.dedupeKey
        ) else { return nil }

        return threadId
    }

    /// Thread ids the rail still has to look up, de-duplicated and in first-
    /// seen order. `alreadyResolved` is the cache's key set, so a thread is
    /// looked up once for the life of the list no matter how many rows cite it.
    static func threadIdsNeedingResolution(
        in notifications: [NotificationDTO],
        alreadyResolved: Set<String> = []
    ) -> [String] {
        var seen = alreadyResolved
        var ids: [String] = []
        for notification in notifications {
            guard let threadId = emailThreadRouteId(for: notification) else { continue }
            guard !seen.contains(threadId) else { continue }
            seen.insert(threadId)
            ids.append(threadId)
        }
        return ids
    }

    /// The rail's rows, with every resolved-to-nothing inbox row folded into a
    /// single group placed where its newest member sat.
    ///
    /// `notifications` is expected newest-first (the rail's own query order);
    /// the group inherits the timestamp of the first member it sees.
    static func items(
        for notifications: [NotificationDTO],
        threadLeads: [String: String?]
    ) -> [NotificationListItem] {
        var items: [NotificationListItem] = []
        var members: [NotificationDTO] = []
        var insertionIndex: Int?

        for notification in notifications {
            if isUnlinked(notification, threadLeads: threadLeads) {
                if insertionIndex == nil { insertionIndex = items.count }
                members.append(notification)
            } else {
                items.append(.single(notification))
            }
        }

        guard let insertionIndex, let group = makeGroup(from: members) else { return items }
        items.insert(.unlinkedInbox(group), at: insertionIndex)
        return items
    }

    // MARK: - Internals

    /// True when this row's thread has been looked up and carries no lead.
    /// An unlooked-up thread is never unlinked — absence of proof is not proof.
    private static func isUnlinked(
        _ notification: NotificationDTO,
        threadLeads: [String: String?]
    ) -> Bool {
        guard let threadId = emailThreadRouteId(for: notification),
              let resolved = threadLeads[threadId] else { return false }
        let opportunityId = resolved?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return opportunityId.isEmpty
    }

    private static func makeGroup(from members: [NotificationDTO]) -> UnlinkedInboxGroup? {
        guard let newest = members.first else { return nil }

        var countsByTitle: [String: Int] = [:]
        var firstSeenOrder: [String] = []
        for member in members {
            let trimmed = member.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmed.isEmpty ? Copy.untitledSource : trimmed
            if countsByTitle[title] == nil { firstSeenOrder.append(title) }
            countsByTitle[title, default: 0] += 1
        }

        // Densest first; first-seen order breaks ties. Built in steps — the
        // one-expression form times out the type checker.
        var ranked: [(order: Int, source: UnlinkedInboxGroup.Source)] = []
        for (order, title) in firstSeenOrder.enumerated() {
            let count: Int = countsByTitle[title] ?? 0
            ranked.append((order: order, source: UnlinkedInboxGroup.Source(title: title, count: count)))
        }
        ranked.sort { lhs, rhs in
            if lhs.source.count != rhs.source.count {
                return lhs.source.count > rhs.source.count
            }
            return lhs.order < rhs.order
        }
        let sources: [UnlinkedInboxGroup.Source] = ranked.map { $0.source }

        return UnlinkedInboxGroup(
            memberIds: members.map(\.id),
            newestCreatedAt: newest.createdAt,
            unreadCount: members.filter { !$0.isRead }.count,
            isMarkReadPermitted: members.allSatisfy {
                NotificationReadPolicy.shouldMarkRead(persistent: $0.persistent)
            },
            sources: sources
        )
    }
}
