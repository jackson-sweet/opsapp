//
//  HomeBillableThisWeekRollupEngine.swift
//  OPS
//

import Foundation

enum HomeBillableRollupSection: String {
    case closingThisWeek
    case readyToBill
}

struct HomeBillableProjectCandidate: Identifiable {
    let id: String
    let projectId: String
    let title: String
    let section: HomeBillableRollupSection
    let taskCount: Int
    let amount: Double?
    let invoiceId: String?
    let estimateId: String?
    let latestTaskEnd: Date?
}

struct HomeBillableThisWeekRollup {
    let weekStart: Date
    let weekEnd: Date
    let closingThisWeek: [HomeBillableProjectCandidate]
    let readyToBill: [HomeBillableProjectCandidate]

    static let empty = HomeBillableThisWeekRollup(
        weekStart: Date(),
        weekEnd: Date(),
        closingThisWeek: [],
        readyToBill: []
    )

    var allItems: [HomeBillableProjectCandidate] {
        closingThisWeek + readyToBill
    }

    var projectCount: Int {
        allItems.count
    }

    var totalKnownAmount: Double {
        allItems.reduce(0) { partial, item in
            partial + (item.amount ?? 0)
        }
    }

    var hasItems: Bool {
        !closingThisWeek.isEmpty || !readyToBill.isEmpty
    }
}

enum HomeBillableThisWeekRollupEngine {

    static func compute(
        projects: [Project],
        invoices: [Invoice],
        estimates: [Estimate],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> HomeBillableThisWeekRollup {
        let scopedCalendar = mondayCalendar(from: calendar)
        let bounds = weekBounds(containing: today, calendar: scopedCalendar)
        let invoicesByProject = Dictionary(grouping: invoices.filter { $0.deletedAt == nil }) { invoice in
            invoice.projectId ?? ""
        }
        let estimatesByProject = Dictionary(grouping: estimates.filter { $0.deletedAt == nil }) { estimate in
            estimate.projectId ?? ""
        }

        var closing: [HomeBillableProjectCandidate] = []
        var ready: [HomeBillableProjectCandidate] = []

        for project in projects where project.deletedAt == nil {
            guard project.status != .archived, project.status != .closed else { continue }

            let projectInvoices = invoicesByProject[project.id] ?? []
            guard !hasPostedInvoice(projectInvoices) else { continue }

            let liveTasks = project.tasks
                .filter { $0.deletedAt == nil && $0.status != .cancelled }

            guard !liveTasks.isEmpty else { continue }

            let remainingTasks = liveTasks.filter { $0.status != .completed }
            let amountSource = amountSource(
                invoices: projectInvoices,
                estimates: estimatesByProject[project.id] ?? []
            )

            if remainingTasks.isEmpty {
                ready.append(
                    candidate(
                        project: project,
                        section: .readyToBill,
                        tasks: liveTasks,
                        amountSource: amountSource
                    )
                )
                continue
            }

            guard remainingTasks.allSatisfy({ task in
                guard let endDate = task.endDate else { return false }
                return endDate >= bounds.start && endDate <= bounds.end
            }) else {
                continue
            }

            closing.append(
                candidate(
                    project: project,
                    section: .closingThisWeek,
                    tasks: remainingTasks,
                    amountSource: amountSource
                )
            )
        }

        return HomeBillableThisWeekRollup(
            weekStart: bounds.start,
            weekEnd: bounds.end,
            closingThisWeek: sorted(closing),
            readyToBill: sorted(ready)
        )
    }

    private static func candidate(
        project: Project,
        section: HomeBillableRollupSection,
        tasks: [ProjectTask],
        amountSource: AmountSource
    ) -> HomeBillableProjectCandidate {
        HomeBillableProjectCandidate(
            id: "\(section.rawValue)-\(project.id)",
            projectId: project.id,
            title: project.title,
            section: section,
            taskCount: tasks.count,
            amount: amountSource.amount,
            invoiceId: amountSource.invoiceId,
            estimateId: amountSource.estimateId,
            latestTaskEnd: tasks.compactMap(\.endDate).max()
        )
    }

    private static func hasPostedInvoice(_ invoices: [Invoice]) -> Bool {
        invoices.contains { invoice in
            invoice.status != .draft && invoice.status != .void
        }
    }

    private struct AmountSource {
        let amount: Double?
        let invoiceId: String?
        let estimateId: String?

        static let none = AmountSource(amount: nil, invoiceId: nil, estimateId: nil)
    }

    private static func amountSource(invoices: [Invoice], estimates: [Estimate]) -> AmountSource {
        if let invoice = invoices
            .filter({ $0.status == .draft && $0.total > 0 })
            .sorted(by: { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt { return lhs.total > rhs.total }
                return lhs.updatedAt > rhs.updatedAt
            })
            .first {
            return AmountSource(amount: invoice.total, invoiceId: invoice.id, estimateId: nil)
        }

        if let estimate = estimates
            .filter({ estimateAmountRank($0.status) != nil && $0.total > 0 })
            .sorted(by: { lhs, rhs in
                let lhsRank = estimateAmountRank(lhs.status) ?? Int.max
                let rhsRank = estimateAmountRank(rhs.status) ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.updatedAt == rhs.updatedAt { return lhs.total > rhs.total }
                return lhs.updatedAt > rhs.updatedAt
            })
            .first {
            return AmountSource(amount: estimate.total, invoiceId: nil, estimateId: estimate.id)
        }

        return .none
    }

    private static func estimateAmountRank(_ status: EstimateStatus) -> Int? {
        switch status {
        case .approved, .converted: return 0
        case .sent, .viewed: return 1
        case .draft: return 2
        case .declined, .expired: return nil
        }
    }

    private static func sorted(_ items: [HomeBillableProjectCandidate]) -> [HomeBillableProjectCandidate] {
        items.sorted { lhs, rhs in
            switch (lhs.latestTaskEnd, rhs.latestTaskEnd) {
            case let (lhsEnd?, rhsEnd?) where lhsEnd != rhsEnd:
                return lhsEnd < rhsEnd
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private static func mondayCalendar(from calendar: Calendar) -> Calendar {
        var scoped = calendar
        scoped.firstWeekday = 2
        scoped.minimumDaysInFirstWeek = 1
        return scoped
    }

    private static func weekBounds(containing date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 86_400)
        return (start, nextWeek.addingTimeInterval(-1))
    }
}
