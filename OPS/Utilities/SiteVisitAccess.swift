//
//  SiteVisitAccess.swift
//  OPS
//
//  CREW SITE VISITS · P1 — the pure, testable access rules for site visits.
//
//  Two grants exist, and neither is a role name:
//    • Assignment is the grant. A user listed in `site_visits.assignee_ids`
//      may open, capture and complete that visit with no `pipeline.*` grant.
//      The server mirrors this exactly (`private.actor_is_site_visit_assignee`).
//    • Walk-up capture is a permission. `site_visits.capture` (scope `all`), or
//      `pipeline.convert` at any scope, lets a user start a visit with no lead.
//
//  What an assignee may NOT do stays lead authority: re-link the visit, move
//  the lead's stage, create a lead, convert to a project, edit the lead's
//  address, or discard the visit. The server freezes the visit's link columns
//  (opportunity_id, project_id, project_ref, client_id, client_ref, deleted_at)
//  for assignee-only authority, so every surface that could change them reads
//  its gate from here.
//
//  Spec: ops-software-bible/specs/2026-09-18-crew-site-visit-access.md
//

import Foundation

// MARK: - Value types

/// Lead authority for one lead row, derived from `LeadAccessPolicy` with the
/// lead's `assigned_to`. An unknown `assignedTo` (a detached brief snapshot)
/// only satisfies an `all`-scope grant — never an `assigned` one.
struct SiteVisitLeadAuthority: Equatable {
    let canView: Bool
    let canEdit: Bool
    let canConvert: Bool
    let canCreate: Bool

    static let none = SiteVisitLeadAuthority(
        canView: false,
        canEdit: false,
        canConvert: false,
        canCreate: false
    )
}

/// Where a START / RESUME intent lands.
enum SiteVisitStartResolution: Equatable {
    /// The user has the Leads tab and the intent names a lead: the leads tab's
    /// one capture cover owns it (today's path).
    case leadsTab
    /// The user is an assignee of this exact, still-open visit: the root-level
    /// capture host opens it directly — no Leads tab required.
    case rootCapture(visitId: String)
    /// Nothing this user may open: the access-denied rail.
    case denied
}

/// The booked-visit card's dialog actions, in presentation order.
enum SiteVisitCalendarAction: String, Equatable, CaseIterable {
    case startNow
    case resumeVisit
    case reschedule
    case openLead
}

/// The capture screen's lead-authority gates for the visit it is showing.
struct SiteVisitCaptureGates: Equatable {
    /// The visit's links (lead / client binding) may change: lead search and
    /// attach, client binding, and clearing the bound lead.
    let canChangeBinding: Bool
    /// Lead search is shown at all (needs lead view).
    let canSearchLeads: Bool
    /// CREATE LEAD from the identity draft (needs pipeline create).
    let canCreateLead: Bool
    /// CREATE PROJECT NOW (needs convert on the bound lead).
    let canCreateProject: Bool
    /// The lead stage card, and queuing a stage command (needs edit).
    let canMoveLeadStage: Bool
    /// A picked address persists to the bound lead's row (needs edit). When
    /// false the address stays visit-local.
    let canPersistAddressToLead: Bool
    /// DISCARD VISIT tombstones the visit (needs edit on a linked visit).
    let canDiscardVisit: Bool

    /// No lead-authority restriction — a console built outside
    /// `SiteVisitCaptureView` (tests, previews) keeps its pre-existing
    /// behaviour. Every other precondition (a bound lead, evidence, …) still
    /// applies on top.
    static let unrestricted = SiteVisitCaptureGates(
        canChangeBinding: true,
        canSearchLeads: true,
        canCreateLead: true,
        canCreateProject: true,
        canMoveLeadStage: true,
        canPersistAddressToLead: true,
        canDiscardVisit: true
    )
}

/// The fields of a local visit the access rules read. A plain value so the
/// rules are testable without a SwiftData store.
struct SiteVisitAccessCandidate: Equatable {
    let id: String
    let companyId: String
    let opportunityId: String?
    let assigneeIds: [String]
    let status: SiteVisitStatus
    let completedAt: Date?
    let deletedAt: Date?
    let scheduledAt: Date?
    let bookedAt: Date?
    let createdAt: Date

    init(
        id: String,
        companyId: String,
        opportunityId: String?,
        assigneeIds: [String],
        status: SiteVisitStatus,
        completedAt: Date? = nil,
        deletedAt: Date? = nil,
        scheduledAt: Date? = nil,
        bookedAt: Date? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.assigneeIds = assigneeIds
        self.status = status
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.scheduledAt = scheduledAt
        self.bookedAt = bookedAt
        self.createdAt = createdAt
    }

    init(visit: SiteVisit) {
        self.init(
            id: visit.id,
            companyId: visit.companyId,
            opportunityId: visit.opportunityId,
            assigneeIds: visit.assigneeIds,
            status: visit.status,
            completedAt: visit.completedAt,
            deletedAt: visit.deletedAt,
            scheduledAt: visit.scheduledAt,
            bookedAt: visit.bookedAt,
            createdAt: visit.createdAt
        )
    }

    /// Open = still workable: not completed, not cancelled, not tombstoned.
    /// The same definition the capture view model's `openVisits()` uses, so a
    /// visit this resolves is a visit the console can resume.
    var isOpen: Bool {
        status != .completed
            && status != .cancelled
            && completedAt == nil
            && deletedAt == nil
    }
}

// MARK: - Rules

enum SiteVisitAccess {
    /// Start a walk-up visit with no lead. Scope `all` only.
    static let capturePermission = "site_visits.capture"

    // MARK: Assignment

    /// Whether `userId` is listed in the visit's `assignee_ids`. Ids compare
    /// case-insensitively — Postgres uuids are lowercase, `UUID().uuidString`
    /// is not.
    static func isAssignee(assigneeIds: [String], userId: String?) -> Bool {
        guard let user = canonical(userId) else { return false }
        return assigneeIds.contains { canonical($0) == user }
    }

    static func isAssignee(_ visit: SiteVisit, userId: String?) -> Bool {
        isAssignee(assigneeIds: visit.assigneeIds, userId: userId)
    }

    static func isAssignee(_ candidate: SiteVisitAccessCandidate, userId: String?) -> Bool {
        isAssignee(assigneeIds: candidate.assigneeIds, userId: userId)
    }

    // MARK: Walk-up capture

    /// `site_visits.capture` (scope all) or `pipeline.convert` at any scope.
    /// Both inputs already carry feature-flag blocking: `site_visits.capture`
    /// belongs to the `pipeline` flag's permission list.
    static func canStartWalkUp(canCapture: Bool, canConvertAny: Bool) -> Bool {
        canCapture || canConvertAny
    }

    static func canStartWalkUp(permissionStore: PermissionStore) -> Bool {
        canStartWalkUp(
            canCapture: permissionStore.can(capturePermission, requiredScope: "all"),
            canConvertAny: permissionStore.leadAccessPolicy.canConvertAny
        )
    }

    // MARK: Leads tab

    /// The LEADS tab exists for this user: a lead view grant AND the
    /// `pipeline` feature flag. Mirrors `MainTabView.hasLeadsAccess`.
    static func hasLeadsAccess(policy: LeadAccessPolicy, pipelineEnabled: Bool) -> Bool {
        policy.canViewAny && pipelineEnabled
    }

    // MARK: Lead authority

    static func leadAuthority(policy: LeadAccessPolicy, assignedTo: String?) -> SiteVisitLeadAuthority {
        SiteVisitLeadAuthority(
            canView: policy.can(.view, assignedTo: assignedTo),
            canEdit: policy.can(.edit, assignedTo: assignedTo),
            canConvert: policy.can(.convert, assignedTo: assignedTo),
            canCreate: policy.canCreate
        )
    }

    // MARK: Capture gates

    /// The capture screen's gates.
    ///
    /// - A lead-bound visit: every binding-shaped action needs edit on that
    ///   lead (the server freezes the link columns for assignee-only
    ///   authority); CREATE PROJECT needs convert on it.
    /// - A project-linked visit with no lead: there is no lead row to read an
    ///   assignment from, so only an `all`-scope lead edit grant unlocks it.
    /// - An unlinked walk-up: today's behaviour, except lead search needs a
    ///   lead view grant and CREATE LEAD needs pipeline create.
    static func captureGates(
        policy: LeadAccessPolicy,
        boundLeadId: String?,
        boundLeadAssignedTo: String?,
        isProjectLinked: Bool
    ) -> SiteVisitCaptureGates {
        if canonical(boundLeadId) != nil || isProjectLinked {
            let assignedTo = canonical(boundLeadId) != nil ? boundLeadAssignedTo : nil
            let authority = leadAuthority(policy: policy, assignedTo: assignedTo)
            return SiteVisitCaptureGates(
                canChangeBinding: authority.canEdit,
                canSearchLeads: authority.canEdit && authority.canView,
                canCreateLead: false,
                canCreateProject: canonical(boundLeadId) != nil && authority.canConvert,
                canMoveLeadStage: canonical(boundLeadId) != nil && authority.canEdit,
                canPersistAddressToLead: canonical(boundLeadId) != nil && authority.canEdit,
                canDiscardVisit: authority.canEdit
            )
        }

        let canView = policy.canViewAny
        return SiteVisitCaptureGates(
            canChangeBinding: canView,
            canSearchLeads: canView,
            canCreateLead: policy.canCreate,
            canCreateProject: policy.canConvertAny,
            canMoveLeadStage: false,
            canPersistAddressToLead: false,
            canDiscardVisit: true
        )
    }

    /// Whether the capture console may mint a NEW visit when a resume target
    /// is missing. A lead-bound visit is created under lead authority (edit on
    /// that lead); a leadless one needs walk-up authority. Without it the
    /// console must not fabricate a row the server will refuse.
    static func canCreateVisit(
        policy: LeadAccessPolicy,
        boundLeadId: String?,
        boundLeadAssignedTo: String?,
        canStartWalkUp: Bool
    ) -> Bool {
        if canonical(boundLeadId) != nil {
            return leadAuthority(policy: policy, assignedTo: boundLeadAssignedTo).canEdit
        }
        return canStartWalkUp
    }

    // MARK: START / RESUME relay

    /// Resolve a START / RESUME intent.
    ///
    /// Order: the Leads tab first (it owns the lead's capture cover); else a
    /// local OPEN visit the user is assigned to, matched by `siteVisitId`, else
    /// by the lead id; else denied.
    static func resolveStart(
        leadId: String?,
        siteVisitId: String?,
        hasLeadsAccess: Bool,
        userId: String?,
        companyId: String?,
        candidates: [SiteVisitAccessCandidate],
        now: Date = Date()
    ) -> SiteVisitStartResolution {
        let lead = canonical(leadId)
        if hasLeadsAccess, lead != nil {
            return .leadsTab
        }

        let workable = candidates.filter { candidate in
            candidate.isOpen
                && isAssignee(candidate, userId: userId)
                && (canonical(companyId).map { canonical(candidate.companyId) == $0 } ?? true)
        }

        if let visitId = canonical(siteVisitId),
           let exact = workable.first(where: { canonical($0.id) == visitId }) {
            return .rootCapture(visitId: exact.id)
        }

        if let lead,
           let best = preferredVisit(
               workable.filter { canonical($0.opportunityId) == lead },
               now: now
           ) {
            return .rootCapture(visitId: best.id)
        }

        return .denied
    }

    /// Among several open visits for the same lead: the one already on site,
    /// then the booked appointment nearest to now, then the newest walk-up.
    static func preferredVisit(
        _ visits: [SiteVisitAccessCandidate],
        now: Date
    ) -> SiteVisitAccessCandidate? {
        if let inProgress = visits
            .filter({ $0.status == .inProgress })
            .max(by: { $0.createdAt < $1.createdAt }) {
            return inProgress
        }
        let booked = visits.filter { $0.bookedAt != nil && $0.scheduledAt != nil }
        if let nearest = booked.min(by: { lhs, rhs in
            abs(lhs.scheduledAt!.timeIntervalSince(now)) < abs(rhs.scheduledAt!.timeIntervalSince(now))
        }) {
            return nearest
        }
        return visits.max { $0.createdAt < $1.createdAt }
    }

    // MARK: Calendar dialog

    /// The booked-visit card's actions.
    ///
    /// - START NOW: scheduled, today, and the user can open the visit.
    /// - RESUME VISIT: in progress, and the user can open the visit.
    /// - RESCHEDULE: scheduled, a lead to book against, a real booking, and
    ///   `canConvertAny` (booking authority).
    /// - OPEN LEAD: the Leads tab exists and the visit has a lead.
    ///
    /// `canOpenVisit` = the START relay would not deny: Leads-tab access with a
    /// lead, or assignment. It keeps START / RESUME off cards the user could
    /// only bounce off the access-denied rail.
    static func calendarActions(
        status: SiteVisitStatus,
        isToday: Bool,
        hasLeadsAccess: Bool,
        canConvertAny: Bool,
        hasLead: Bool,
        hasBookingSnapshot: Bool,
        canOpenVisit: Bool
    ) -> [SiteVisitCalendarAction] {
        var actions: [SiteVisitCalendarAction] = []
        if status == .scheduled, isToday, canOpenVisit {
            actions.append(.startNow)
        }
        if status == .inProgress, canOpenVisit {
            actions.append(.resumeVisit)
        }
        if status == .scheduled, canConvertAny, hasLead, hasBookingSnapshot {
            actions.append(.reschedule)
        }
        if hasLeadsAccess, hasLead {
            actions.append(.openLead)
        }
        return actions
    }

    /// Whether the START relay would open this visit for this user.
    static func canOpenVisit(
        hasLeadsAccess: Bool,
        hasLead: Bool,
        isAssignee: Bool
    ) -> Bool {
        (hasLeadsAccess && hasLead) || isAssignee
    }

    // MARK: Reminder routing

    /// A heads-up / reminder tap by a user without the Leads tab lands on
    /// Schedule, on the visit's day. The visit is matched by `siteVisitId`,
    /// else by the lead id among visits assigned to the user. Nil = no local
    /// visit to date the landing by (Schedule opens where it is).
    static func reminderFocusDate(
        leadId: String?,
        siteVisitId: String?,
        userId: String?,
        candidates: [SiteVisitAccessCandidate],
        now: Date = Date()
    ) -> Date? {
        if let visitId = canonical(siteVisitId),
           let exact = candidates.first(where: { canonical($0.id) == visitId && $0.deletedAt == nil }) {
            return exact.scheduledAt
        }
        guard let lead = canonical(leadId) else { return nil }
        let assigned = candidates.filter {
            canonical($0.opportunityId) == lead
                && $0.deletedAt == nil
                && $0.bookedAt != nil
                && isAssignee($0, userId: userId)
        }
        return preferredVisit(assigned, now: now)?.scheduledAt
    }

    // MARK: Helpers

    private static func canonical(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
