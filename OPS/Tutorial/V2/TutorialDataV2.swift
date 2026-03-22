import SwiftUI

/// V2-specific data extensions for the tutorial.
/// Invoice numbers, financial helpers, and line-item derivation.
enum TutorialDataV2 {

    // MARK: - Invoice Numbers (per review card)

    static let invoiceNumbers = ["INV-0044", "INV-0045", "INV-0046", "INV-0047"]

    // MARK: - Invoice Line Items

    /// Derives invoice line items from a review card's project tasks + known amounts.
    /// Each task becomes a line item with a proportional share of the invoice total.
    static func invoiceLineItems(for cardIndex: Int) -> [(name: String, amount: Int)] {
        guard cardIndex < TutorialData.reviewCards.count else { return [] }
        let card = TutorialData.reviewCards[cardIndex]
        let taskCount = card.projectTasks.count
        guard taskCount > 0 else { return [] }

        // Distribute invoice total across tasks proportionally
        // Last task gets remainder to avoid rounding errors
        let perTask = card.invoiceTotal / taskCount
        return card.projectTasks.enumerated().map { idx, task in
            let amount = idx == taskCount - 1
                ? card.invoiceTotal - (perTask * (taskCount - 1))
                : perTask
            return (name: task.name, amount: amount)
        }
    }

    // MARK: - Financial Summary

    /// Per-project financial breakdown. Revenue depends on whether the project was completed (right-swiped).
    /// - isPaid: true = full invoice (right-swipe), false = 50% deposit (left-swipe)
    static func financialSummary(for cardIndex: Int, isPaid: Bool) -> (revenue: Int, costs: Int, profit: Int) {
        guard cardIndex < TutorialData.reviewCards.count,
              cardIndex < TutorialData.projectCosts.count else {
            return (0, 0, 0)
        }

        let card = TutorialData.reviewCards[cardIndex]
        let costs = TutorialData.projectCosts[cardIndex]

        let revenue = isPaid ? card.invoiceTotal : card.invoiceTotal / 2
        let totalCost = costs.totalCost
        let profit = revenue - totalCost

        return (revenue: revenue, costs: totalCost, profit: profit)
    }

    // MARK: - Project Display Data

    /// Full project card data for closeout phase — combines review card info with all tasks.
    struct CloseoutProject {
        let cardIndex: Int
        let projectName: String
        let clientName: String
        let color: Color
        let invoiceNumber: String
        let invoiceTotal: Int
        let tasks: [TutorialData.ReviewProjectTask]
        let swipedTaskName: String
    }

    /// Builds closeout project data from a review card index.
    static func closeoutProject(for cardIndex: Int) -> CloseoutProject {
        let card = TutorialData.reviewCards[cardIndex]
        return CloseoutProject(
            cardIndex: cardIndex,
            projectName: card.project,
            clientName: card.client,
            color: card.color,
            invoiceNumber: invoiceNumbers[cardIndex],
            invoiceTotal: card.invoiceTotal,
            tasks: card.projectTasks,
            swipedTaskName: card.task
        )
    }
}
