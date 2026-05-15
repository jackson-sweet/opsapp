//
//  LeadsPreviewSupport.swift
//  OPS
//
//  Preview-only scaffolding for the LEADS surface. Lets every Leads view
//  render in Xcode Previews without touching Supabase. DEBUG-guarded —
//  excluded from release builds.
//

#if DEBUG
import SwiftUI

// MARK: - Opportunity factory

extension Opportunity {
    /// Builds an in-memory `Opportunity` for previews. Bypasses ModelContainer
    /// binding (LEADS UI only reads, never persists).
    static func preview(
        id: String = UUID().uuidString,
        title: String? = nil,
        contactName: String,
        stage: PipelineStage,
        estimatedValue: Double? = nil,
        daysInStage: Int = 0,
        lastActivityDaysAgo: Int? = nil,
        nextFollowUpDaysFromNow: Int? = nil,
        assignedTo: String? = "preview-user",
        actualCloseDaysAgo: Int? = nil
    ) -> Opportunity {
        let now = Date()
        let cal = Calendar.current
        let entered = cal.date(byAdding: .day, value: -daysInStage, to: now) ?? now

        let opp = Opportunity(
            id: id,
            companyId: "preview-company",
            contactName: contactName,
            stage: stage,
            stageEnteredAt: entered,
            createdAt: entered,
            updatedAt: now
        )
        opp.title = title
        opp.estimatedValue = estimatedValue
        opp.assignedTo = assignedTo
        if let last = lastActivityDaysAgo {
            opp.lastActivityAt = cal.date(byAdding: .day, value: -last, to: now)
        }
        if let next = nextFollowUpDaysFromNow {
            opp.nextFollowUpAt = cal.date(byAdding: .day, value: next, to: now)
        }
        if let close = actualCloseDaysAgo {
            opp.actualCloseDate = cal.date(byAdding: .day, value: -close, to: now)
        }
        return opp
    }

    /// Realistic mix spanning every stage and every urgency tier.
    /// Sized so `closeRate(periodDays: 90)` clears its `>= 5 closes` gate.
    static var previewMix: [Opportunity] {
        [
            // NEW LEAD — untouched
            .preview(title: "Smith deck addition", contactName: "Mike Smith",
                     stage: .newLead, estimatedValue: 8_500,
                     daysInStage: 0, lastActivityDaysAgo: nil),
            // NEW LEAD — fresh contact made
            .preview(title: "Garcia kitchen remodel", contactName: "Lupita Garcia",
                     stage: .newLead, estimatedValue: 32_000,
                     daysInStage: 1, lastActivityDaysAgo: 0),
            // QUALIFYING — healthy
            .preview(title: "Acme HQ retrofit", contactName: "Procurement / Acme",
                     stage: .qualifying, estimatedValue: 145_000,
                     daysInStage: 4, lastActivityDaysAgo: 1),
            // QUOTING — stale (threshold 5d)
            .preview(title: "Hilltop pool deck", contactName: "Anna Patel",
                     stage: .quoting, estimatedValue: 22_400,
                     daysInStage: 9, lastActivityDaysAgo: 7),
            // QUOTED — overdue follow-up
            .preview(title: "Rivera siding job", contactName: "Sam Rivera",
                     stage: .quoted, estimatedValue: 14_800,
                     daysInStage: 5, lastActivityDaysAgo: 4,
                     nextFollowUpDaysFromNow: -2),
            // FOLLOW-UP — fresh
            .preview(title: "Donovan fence rebuild", contactName: "Pat Donovan",
                     stage: .followUp, estimatedValue: 6_200,
                     daysInStage: 2, lastActivityDaysAgo: 2),
            // NEGOTIATION — overdue + stale (threshold 2d)
            .preview(title: "Cedar Ridge roof", contactName: "Cedar Ridge HOA",
                     stage: .negotiation, estimatedValue: 78_500,
                     daysInStage: 6, lastActivityDaysAgo: 6,
                     nextFollowUpDaysFromNow: -5),
            // WON ×4 + LOST ×2 to satisfy 90D close-rate threshold
            .preview(title: "Maple Lane porch", contactName: "Tom Liu",
                     stage: .won, estimatedValue: 11_200,
                     daysInStage: 12, actualCloseDaysAgo: 12),
            .preview(title: "Foster patio", contactName: "Jen Foster",
                     stage: .won, estimatedValue: 9_400,
                     daysInStage: 18, actualCloseDaysAgo: 18),
            .preview(title: "Northgate gym build", contactName: "Northgate Fitness",
                     stage: .won, estimatedValue: 48_000,
                     daysInStage: 30, actualCloseDaysAgo: 30),
            .preview(title: "Lakeview shed pad", contactName: "Carlos Vega",
                     stage: .won, estimatedValue: 4_800,
                     daysInStage: 9, actualCloseDaysAgo: 9),
            .preview(title: "Beacon Hill addition", contactName: "Beacon Hill LLC",
                     stage: .lost, estimatedValue: 26_500,
                     daysInStage: 20, actualCloseDaysAgo: 20),
            .preview(title: "Westwood remodel", contactName: "Erin Webb",
                     stage: .lost, estimatedValue: 18_000,
                     daysInStage: 25, actualCloseDaysAgo: 25),
        ]
    }
}

// MARK: - PipelineViewModel

extension PipelineViewModel {
    /// Pre-seeded VM. Never calls `setup(...)` so no Supabase repository is
    /// created. `currentUserId` is set so in-court derivations resolve.
    @MainActor
    static func previewLoaded(
        opportunities: [Opportunity] = Opportunity.previewMix,
        currentUserId: String? = "preview-user",
        selectedStage: PipelineStage = .newLead
    ) -> PipelineViewModel {
        let vm = PipelineViewModel()
        vm.currentUserId = currentUserId
        vm.allOpportunities = opportunities
        vm.selectedStage = selectedStage
        return vm
    }
}

// MARK: - PermissionStore

extension PermissionStore {
    /// Initialized store granting pipeline-manage so swipe actions render
    /// in previews. Bypasses keychain / network hydration.
    static func previewWithFullAccess() -> PermissionStore {
        let store = PermissionStore()
        store.permissions = [
            "pipeline.manage": "all",
            "pipeline.view": "all",
            "lead.create": "all",
        ]
        store.roleName = "OPERATOR"
        store.initialized = true
        return store
    }
}

// MARK: - Env-object stack

/// Applies every env object the LEADS surface (including `AppHeader`) needs
/// for previews. Use on the top-level preview view.
struct LeadsPreviewEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environmentObject(DataController())
            .environmentObject(PermissionStore.previewWithFullAccess())
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(AppState())
            .preferredColorScheme(.dark)
    }
}

extension View {
    func leadsPreviewEnvironment() -> some View {
        modifier(LeadsPreviewEnvironment())
    }
}
#endif
