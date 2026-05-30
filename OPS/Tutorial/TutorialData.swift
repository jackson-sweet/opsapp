import SwiftUI

// MARK: - Tutorial Data

/// All static content for the "Lead to Revenue" tutorial.
/// Deck resurfacing job. Real trades data. No database, no sync.
enum TutorialData {

    // MARK: - Client

    static let clientName = "Tom Walsh"
    static let projectTitle = "Deck Resurfacing"

    // MARK: - Estimate

    static let estimateTotal: Int = 4_800
    static let invoiceNumber = "INV-0047"

    static let lineItems: [LineItem] = [
        LineItem(name: "Sand & Prep",       type: .labor,    amount: 1_200),
        LineItem(name: "Stain & Seal",      type: .labor,    amount: 1_800),
        LineItem(name: "Railing Touch-Up",  type: .labor,    amount: 800),
        LineItem(name: "Materials",         type: .material, amount: 1_000),
    ]

    static var laborItems: [LineItem] {
        lineItems.filter { $0.type == .labor }
    }

    // MARK: - Tasks (from labor line items)

    static let taskCards: [TaskCard] = [
        TaskCard(name: "Sand & Prep",      crew: "Pete Mitchell", color: Color(hex: "#8195B5") ?? OPSStyle.Colors.primaryAccent),
        TaskCard(name: "Stain & Seal",     crew: "Nick Bradshaw", color: OPSStyle.Colors.olive),
        TaskCard(name: "Railing Touch-Up", crew: "Pete Mitchell", color: Color(hex: "#B5A381") ?? OPSStyle.Colors.warningStatus),
    ]

    // MARK: - Review Cards (Step 5 — Tinder swipe)
    // Each card is the LAST remaining task for its project.
    // Swiping right completes the project and triggers auto-invoice.

    static let reviewCards: [ReviewCard] = [
        ReviewCard(
            task: "Gutter Cleaning", project: "Parkside Duplex", client: "Metro Property Mgmt",
            daysAgo: 3, color: Color(hex: "#BCBCBC") ?? OPSStyle.Colors.inactiveStatus,
            projectTasks: [
                ReviewProjectTask(name: "Downspout Repair", alreadyComplete: true),
                ReviewProjectTask(name: "Fascia Replacement", alreadyComplete: true),
                ReviewProjectTask(name: "Gutter Cleaning", alreadyComplete: false),
            ],
            invoiceTotal: 3_200
        ),
        ReviewCard(
            task: "Railing Touch-Up", project: "Deck Resurfacing", client: "Tom Walsh",
            daysAgo: 1, color: Color(hex: "#B5A381") ?? OPSStyle.Colors.warningStatus,
            projectTasks: [
                ReviewProjectTask(name: "Sand & Prep", alreadyComplete: true),
                ReviewProjectTask(name: "Stain & Seal", alreadyComplete: true),
                ReviewProjectTask(name: "Railing Touch-Up", alreadyComplete: false),
            ],
            invoiceTotal: 4_800
        ),
        ReviewCard(
            task: "Caulking & Trim", project: "Unit 4B Refresh", client: "Apex Holdings",
            daysAgo: 5, color: Color(hex: "#8195B5") ?? OPSStyle.Colors.primaryAccent,
            projectTasks: [
                ReviewProjectTask(name: "Drywall Patch", alreadyComplete: true),
                ReviewProjectTask(name: "Caulking & Trim", alreadyComplete: false),
            ],
            invoiceTotal: 5_600
        ),
        ReviewCard(
            task: "Final Walkthrough", project: "Henley Reno", client: "Lisa Park",
            daysAgo: 2, color: OPSStyle.Colors.rose,
            projectTasks: [
                ReviewProjectTask(name: "Tile Install", alreadyComplete: true),
                ReviewProjectTask(name: "Grout Sealing", alreadyComplete: true),
                ReviewProjectTask(name: "Final Walkthrough", alreadyComplete: false),
            ],
            invoiceTotal: 8_200
        ),
    ]

    // MARK: - Crew

    static let crewMembers: [CrewMember] = [
        CrewMember(name: "Pete Mitchell", color: Color(hex: "#8195B5") ?? OPSStyle.Colors.primaryAccent),
        CrewMember(name: "Nick Bradshaw", color: OPSStyle.Colors.olive),
    ]

    // MARK: - Formatting

    static func formatCurrency(_ amount: Int) -> String {
        "$\(amount.formatted(.number.grouping(.automatic)))"
    }

    // MARK: - Nested Types

    struct LineItem: Identifiable {
        let id = UUID()
        let name: String
        let type: LineItemType
        let amount: Int
    }

    enum LineItemType: String {
        case labor = "LABOR"
        case material = "MATERIAL"

        var color: Color {
            switch self {
            case .labor:    return OPSStyle.Colors.successStatus
            case .material: return OPSStyle.Colors.inactiveStatus
            }
        }
    }

    struct TaskCard: Identifiable {
        let id = UUID()
        let name: String
        let crew: String
        let color: Color
    }

    struct ReviewProjectTask {
        let name: String
        let alreadyComplete: Bool
    }

    struct ReviewCard: Identifiable {
        let id = UUID()
        let task: String
        let project: String
        let client: String
        let daysAgo: Int
        let color: Color
        let projectTasks: [ReviewProjectTask]
        let invoiceTotal: Int
    }

    // MARK: - Calendar Schedule (Gantt-style week view for Phase 4→5)

    struct CalendarScheduleTask: Identifiable {
        let id: String              // Stable ID for matchedGeometryEffect
        let name: String
        let projectName: String
        let color: Color
        let startDay: Int           // 0=Mon...4=Fri
        let endDay: Int             // Inclusive end day
        let row: Int                // Vertical position (no overlaps)
        let completesOnDay: Int?    // Day when ✓ appears. nil = never (review card)
        let reviewCardIndex: Int?   // Maps to reviewCards index if incomplete
        let isDeckTask: Bool        // true = came from the project card (phase 4)
    }

    static let dayLabels = ["MON", "TUE", "WED", "THU", "FRI"]

    /// Gantt-style week schedule. 10 tasks across 6 rows, 5 days.
    /// 6 tasks auto-complete. 4 stay incomplete → become review swipe cards.
    /// Row assignments prevent overlap for multi-day bars.
    static let calendarSchedule: [CalendarScheduleTask] = [
        // Deck Resurfacing tasks (came from project card in phase 4)
        CalendarScheduleTask(id: "cal_sandprep", name: "Sand & Prep", projectName: "Deck Resurfacing",
            color: Color(hex: "#8195B5") ?? OPSStyle.Colors.primaryAccent,
            startDay: 0, endDay: 1, row: 0, completesOnDay: 1, reviewCardIndex: nil, isDeckTask: true),
        CalendarScheduleTask(id: "cal_stain", name: "Stain & Seal", projectName: "Deck Resurfacing",
            color: OPSStyle.Colors.olive,
            startDay: 1, endDay: 2, row: 1, completesOnDay: 2, reviewCardIndex: nil, isDeckTask: true),
        CalendarScheduleTask(id: "cal_rail", name: "Rail Touch-Up", projectName: "Deck Resurfacing",
            color: Color(hex: "#B5A381") ?? OPSStyle.Colors.warningStatus,
            startDay: 2, endDay: 3, row: 4, completesOnDay: nil, reviewCardIndex: 1, isDeckTask: true),

        // Parkside Duplex tasks
        CalendarScheduleTask(id: "cal_downspout", name: "Downspout Rep.", projectName: "Parkside Duplex",
            color: Color(hex: "#BCBCBC") ?? OPSStyle.Colors.inactiveStatus,
            startDay: 1, endDay: 1, row: 3, completesOnDay: 1, reviewCardIndex: nil, isDeckTask: false),
        CalendarScheduleTask(id: "cal_gutter", name: "Gutter Clean", projectName: "Parkside Duplex",
            color: Color(hex: "#BCBCBC") ?? OPSStyle.Colors.inactiveStatus,
            startDay: 1, endDay: 2, row: 5, completesOnDay: nil, reviewCardIndex: 0, isDeckTask: false),

        // Unit 4B Refresh tasks
        CalendarScheduleTask(id: "cal_drywall", name: "Drywall Patch", projectName: "Unit 4B Refresh",
            color: Color(hex: "#8195B5") ?? OPSStyle.Colors.primaryAccent,
            startDay: 0, endDay: 0, row: 2, completesOnDay: 0, reviewCardIndex: nil, isDeckTask: false),
        CalendarScheduleTask(id: "cal_caulk", name: "Caulk & Trim", projectName: "Unit 4B Refresh",
            color: Color(hex: "#8195B5") ?? OPSStyle.Colors.primaryAccent,
            startDay: 2, endDay: 2, row: 2, completesOnDay: nil, reviewCardIndex: 2, isDeckTask: false),

        // Henley Reno tasks
        CalendarScheduleTask(id: "cal_fascia", name: "Fascia Rep.", projectName: "Henley Reno",
            color: OPSStyle.Colors.rose,
            startDay: 2, endDay: 3, row: 0, completesOnDay: 3, reviewCardIndex: nil, isDeckTask: false),
        CalendarScheduleTask(id: "cal_tile", name: "Tile Install", projectName: "Henley Reno",
            color: OPSStyle.Colors.rose,
            startDay: 3, endDay: 4, row: 1, completesOnDay: 4, reviewCardIndex: nil, isDeckTask: false),
        CalendarScheduleTask(id: "cal_final", name: "Final Walk", projectName: "Henley Reno",
            color: OPSStyle.Colors.rose,
            startDay: 3, endDay: 4, row: 3, completesOnDay: nil, reviewCardIndex: 3, isDeckTask: false),
    ]

    struct CrewMember: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
    }

    // MARK: - Accounting Insights (Phase 6)

    struct ProjectCost {
        let projectIndex: Int         // Maps to reviewCards[index]
        let labor: Int
        let materials: Int
        let other: Int
        var totalCost: Int { labor + materials + other }
    }

    struct ExpenseItem: Identifiable {
        let id = UUID()
        let category: String          // "LABOR", "MATERIALS", "OTHER"
        let description: String
        let amount: Int
        let icon: String              // SF Symbol name
        let projectIndex: Int         // Maps to reviewCards[index]
    }

    struct ClosingStep: Identifiable {
        let id = UUID()
        let text: String
        let opsHandles: Bool          // true = gets strikethrough, false = survives
    }

    /// Per-project cost breakdown. Labor 15%, Materials 47%, Other 10%.
    static let projectCosts: [ProjectCost] = [
        ProjectCost(projectIndex: 0, labor: 480, materials: 1_504, other: 320),   // Parkside Duplex
        ProjectCost(projectIndex: 1, labor: 720, materials: 2_256, other: 480),   // Deck Resurfacing
        ProjectCost(projectIndex: 2, labor: 840, materials: 2_632, other: 560),   // Unit 4B Refresh
        ProjectCost(projectIndex: 3, labor: 1_230, materials: 3_854, other: 820), // Henley Reno
    ]

    /// Crew-submitted expense receipts (shown individually during accounting animation).
    /// 2-3 per project for visual variety.
    static let expenseItems: [ExpenseItem] = [
        // Parkside Duplex
        ExpenseItem(category: "LABOR", description: "Gutter crew — 2 days", amount: 480,
                    icon: "person.2.fill", projectIndex: 0),
        ExpenseItem(category: "MATERIALS", description: "Downspouts & brackets", amount: 1_504,
                    icon: "hammer.fill", projectIndex: 0),
        ExpenseItem(category: "OTHER", description: "Disposal & hauling", amount: 320,
                    icon: "wrench.and.screwdriver.fill", projectIndex: 0),
        // Deck Resurfacing
        ExpenseItem(category: "LABOR", description: "Sand & stain crew — 3 days", amount: 720,
                    icon: "person.2.fill", projectIndex: 1),
        ExpenseItem(category: "MATERIALS", description: "Stain, sealant, sandpaper", amount: 2_256,
                    icon: "hammer.fill", projectIndex: 1),
        ExpenseItem(category: "OTHER", description: "Pressure washer rental", amount: 480,
                    icon: "wrench.and.screwdriver.fill", projectIndex: 1),
        // Unit 4B Refresh
        ExpenseItem(category: "LABOR", description: "Drywall & trim crew — 2 days", amount: 840,
                    icon: "person.2.fill", projectIndex: 2),
        ExpenseItem(category: "MATERIALS", description: "Drywall, caulk, trim", amount: 2_632,
                    icon: "hammer.fill", projectIndex: 2),
        ExpenseItem(category: "OTHER", description: "Paint & finishing supplies", amount: 560,
                    icon: "wrench.and.screwdriver.fill", projectIndex: 2),
        // Henley Reno
        ExpenseItem(category: "LABOR", description: "Tile & finish crew — 4 days", amount: 1_230,
                    icon: "person.2.fill", projectIndex: 3),
        ExpenseItem(category: "MATERIALS", description: "Tile, grout, adhesive", amount: 3_854,
                    icon: "hammer.fill", projectIndex: 3),
        ExpenseItem(category: "OTHER", description: "Scaffold rental & permits", amount: 820,
                    icon: "wrench.and.screwdriver.fill", projectIndex: 3),
    ]

    /// 13 steps of running a job. 11 OPS handles, 2 the owner does.
    static let closingSteps: [ClosingStep] = [
        ClosingStep(text: "LEAD", opsHandles: true),
        ClosingStep(text: "SITE VISIT", opsHandles: false),
        ClosingStep(text: "ESTIMATE", opsHandles: true),
        ClosingStep(text: "FOLLOW UP", opsHandles: true),
        ClosingStep(text: "APPROVAL", opsHandles: true),
        ClosingStep(text: "SCHEDULING", opsHandles: true),
        ClosingStep(text: "THE WORK", opsHandles: false),
        ClosingStep(text: "TRACKING", opsHandles: true),
        ClosingStep(text: "EXPENSES", opsHandles: true),
        ClosingStep(text: "PUNCH LIST", opsHandles: true),
        ClosingStep(text: "INVOICE", opsHandles: true),
        ClosingStep(text: "PAYMENT", opsHandles: true),
        ClosingStep(text: "BOOKS", opsHandles: true),
    ]
}
