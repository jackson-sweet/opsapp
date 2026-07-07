//
//  OPSSchemaCommon.swift
//  OPS
//
//  Models whose persistent shape is identical across V2 and V3 — i.e.,
//  everything except `WizardState` (V1↔V2 boundary) and the inventory↔catalog
//  swap (V2↔V3 boundary). Each VersionedSchema appends its version-specific
//  model types on top of this list.
//

import Foundation
import SwiftData

/// Frozen catalog model shapes used by historical schema stages. These types
/// are only for SwiftData migration fingerprints; runtime code uses the
/// top-level models in `DataModels/Supabase/Catalog`.
enum OPSSchemaLegacyCatalogModels {
    @Model
    final class ProductBundleItem: Identifiable {
        @Attribute(.unique) var id: String
        var companyId: String
        var bundleProductId: String
        var childProductId: String
        var quantity: Double
        var displayOrder: Int
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
        var lastSyncedAt: Date?
        var needsSync: Bool = false

        init(
            id: String = UUID().uuidString,
            companyId: String,
            bundleProductId: String,
            childProductId: String,
            quantity: Double = 1,
            displayOrder: Int = 0,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.companyId = companyId
            self.bundleProductId = bundleProductId
            self.childProductId = childProductId
            self.quantity = quantity
            self.displayOrder = displayOrder
            self.createdAt = createdAt
            self.updatedAt = createdAt
        }
    }
}

/// Frozen core relationship graph used by V1-V3. Those schema stages predate
/// the V4 task-reminder relationships, so the core models that own task/user
/// inverses must point at the frozen task models as a consistent graph.
enum OPSSchemaLegacyCoreModels {
    @Model
    final class User {
        var id: String
        var firstName: String
        var lastName: String
        var email: String?
        var phone: String?
        var profileImageURL: String?
        var profileImageData: Data?
        var role: UserRole
        var companyId: String?
        var userType: UserType?
        var latitude: Double?
        var longitude: Double?
        var locationName: String?
        var homeAddress: String?
        var clientId: String?
        var isActive: Bool?
        var userColor: String?
        var devPermission: Bool = false
        var hasCompletedAppOnboarding: Bool = false
        var hasCompletedAppTutorial: Bool = false
        var inventoryAccess: Bool = false
        var specialPermissions: [String] = []
        var emergencyContactName: String?
        var emergencyContactPhone: String?
        var emergencyContactRelationship: String?
        var stripeCustomerId: String?
        var deviceToken: String?

        @Relationship(deleteRule: .noAction, inverse: \OPSSchemaLegacyCoreModels.Project.teamMembers)
        var assignedProjects: [OPSSchemaLegacyCoreModels.Project]

        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var deletedAt: Date?

        init(id: String, firstName: String, lastName: String, role: UserRole, companyId: String) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.role = role
            self.companyId = companyId
            self.assignedProjects = []
            self.isActive = true
        }
    }

    @Model
    final class Project: Identifiable {
        var id: String
        var title: String
        var address: String?
        var latitude: Double?
        var longitude: Double?
        var startDate: Date?
        var endDate: Date?
        var completedAt: Date?
        var duration: Int?
        var status: Status
        var notes: String?
        var companyId: String
        var clientId: String?
        var allDay: Bool
        var opportunityId: String?

        @Relationship(deleteRule: .nullify)
        var client: OPSSchemaLegacyCoreModels.Client?

        var teamMemberIdsString: String = ""
        var projectDescription: String?
        var projectImagesString: String = ""
        var unsyncedImagesString: String = ""
        var clientVisibleImagesString: String = ""

        @Relationship(deleteRule: .noAction)
        var teamMembers: [OPSSchemaLegacyCoreModels.User]

        @Relationship(deleteRule: .cascade, inverse: \OPSSchemaLegacyTaskModels.ProjectTask.project)
        var tasks: [OPSSchemaLegacyTaskModels.ProjectTask] = []

        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var syncPriority: Int = 1
        var deletedAt: Date?
        var createdAt: Date?
        var createdBy: String?
        var updatedAt: Date?

        init(id: String, title: String, status: Status) {
            self.id = id
            self.title = title
            self.status = status
            self.address = nil
            self.companyId = ""
            self.teamMemberIdsString = ""
            self.projectImagesString = ""
            self.unsyncedImagesString = ""
            self.clientVisibleImagesString = ""
            self.teamMembers = []
            self.allDay = false
            self.client = nil
        }
    }

    @Model
    final class Company {
        var id: String
        var name: String
        var logoURL: String?
        var logoData: Data?
        var externalId: String?
        var companyDescription: String?
        var address: String?
        var phone: String?
        var email: String?
        var website: String?
        var latitude: Double?
        var longitude: Double?
        var openHour: String?
        var closeHour: String?
        var industryString: String = ""
        var companySize: String?
        var companyAge: String?
        var referralMethod: String?
        var projectIdsString: String = ""
        var teamIdsString: String = ""
        var adminIdsString: String = ""
        var accountHolderId: String?

        @Relationship(deleteRule: .cascade)
        var teamMembers: [OPSSchemaLegacyCoreModels.TeamMember] = []

        @Relationship(deleteRule: .cascade)
        var taskTypes: [OPSSchemaLegacyTaskModels.TaskType] = []

        var defaultProjectColor: String = "#9CA3AF"
        var preciseSchedulingEnabled: Bool = false
        var skipWeekendsInAutoSchedule: Bool = true
        var overdueReviewThresholdDays: Int = 14
        var overdueReminderFrequencyDays: Int = 7
        var matchInvoicePaymentTerms: Bool = false
        var staleEstimateThresholdDays: Int = 30
        var schedulingWindowMode: String = "companyHours"
        var customSchedulingStartHour: String?
        var customSchedulingEndHour: String?
        var daylightBufferMinutes: Int = 30
        var proximityGroupingRadiusKm: Double = 15.0
        var teamMembersSynced: Bool = false
        var subscriptionStatus: String?
        var subscriptionPlan: String?
        var subscriptionEnd: Date?
        var subscriptionPeriod: String?
        var maxSeats: Int = 10
        var seatedEmployeeIds: String = ""
        var seatGraceStartDate: Date?
        var subscriptionIdsJson: String?
        var trialStartDate: Date?
        var trialEndDate: Date?
        var hasPrioritySupport: Bool = false
        var dataSetupPurchased: Bool = false
        var dataSetupCompleted: Bool = false
        var dataSetupScheduledDate: Date?
        var stripeCustomerId: String?
        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var deletedAt: Date?

        init(id: String, name: String) {
            self.id = id
            self.name = name
            self.projectIdsString = ""
            self.teamIdsString = ""
            self.teamMembers = []
        }
    }

    @Model
    final class TeamMember {
        var id: String
        var firstName: String
        var lastName: String
        var role: String
        var avatarURL: String?
        var email: String?
        var phone: String?

        @Relationship(deleteRule: .cascade, inverse: \OPSSchemaLegacyCoreModels.Company.teamMembers)
        var company: OPSSchemaLegacyCoreModels.Company?

        var lastUpdated: Date

        init(
            id: String,
            firstName: String,
            lastName: String,
            role: String,
            avatarURL: String? = nil,
            email: String? = nil,
            phone: String? = nil
        ) {
            self.id = id
            self.firstName = firstName
            self.lastName = lastName
            self.role = role
            self.avatarURL = avatarURL
            self.email = email
            self.phone = phone
            self.lastUpdated = Date()
        }
    }

    @Model
    final class Client: Identifiable {
        var id: String
        var name: String
        var email: String?
        var phoneNumber: String?
        var address: String?
        var latitude: Double?
        var longitude: Double?
        var profileImageURL: String?
        var notes: String?
        var companyId: String?

        @Relationship(deleteRule: .noAction, inverse: \OPSSchemaLegacyCoreModels.Project.client)
        var projects: [OPSSchemaLegacyCoreModels.Project]

        @Relationship(deleteRule: .cascade)
        var subClients: [OPSSchemaLegacyCoreModels.SubClient]

        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var createdAt: Date?
        var deletedAt: Date?

        init(
            id: String,
            name: String,
            email: String? = nil,
            phoneNumber: String? = nil,
            address: String? = nil,
            companyId: String? = nil,
            notes: String? = nil
        ) {
            self.id = id
            self.name = name
            self.email = email
            self.phoneNumber = phoneNumber
            self.address = address
            self.companyId = companyId
            self.notes = notes
            self.projects = []
            self.subClients = []
            self.lastSyncedAt = Date()
        }
    }

    @Model
    final class SubClient: Identifiable {
        var id: String
        var name: String
        var title: String?
        var email: String?
        var phoneNumber: String?
        var address: String?
        var client: OPSSchemaLegacyCoreModels.Client?
        var createdAt: Date
        var updatedAt: Date
        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var deletedAt: Date?

        init(
            id: String,
            name: String,
            title: String? = nil,
            email: String? = nil,
            phoneNumber: String? = nil,
            address: String? = nil
        ) {
            self.id = id
            self.name = name
            self.title = title
            self.email = email
            self.phoneNumber = phoneNumber
            self.address = address
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
}

/// Frozen task scheduling model shapes used by V1-V3. V4 adds reminder
/// relationships to the live TaskType/ProjectTask models; historical schemas
/// must not inherit those V4 relationships or their persistent checksums collapse.
enum OPSSchemaLegacyTaskModels {
    @Model
    final class TaskType: Identifiable {
        var id: String
        var color: String
        var display: String
        var icon: String?
        var isDefault: Bool
        var companyId: String
        var displayOrder: Int = 0
        var defaultTeamMemberIdsString: String = ""
        var dependenciesJSON: String = "[]"
        var isWeatherDependent: Bool = false
        var defaultDuration: Int = 1

        @Relationship(deleteRule: .nullify, inverse: \OPSSchemaLegacyTaskModels.ProjectTask.taskType)
        var tasks: [OPSSchemaLegacyTaskModels.ProjectTask] = []

        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var deletedAt: Date?

        init(
            id: String,
            display: String,
            color: String,
            companyId: String,
            isDefault: Bool = false,
            icon: String? = nil
        ) {
            self.id = id
            self.display = display
            self.color = color
            self.companyId = companyId
            self.isDefault = isDefault
            self.icon = icon
            self.displayOrder = 0
        }
    }

    @Model
    final class ProjectTask {
        var id: String
        var projectId: String
        var companyId: String
        var status: TaskStatus
        var taskColor: String
        var taskNotes: String?
        var taskTypeId: String
        var taskIndex: Int?
        var displayOrder: Int = 0
        var customTitle: String?
        var sourceLineItemId: String?
        var sourceEstimateId: String?
        var startDate: Date?
        var endDate: Date?
        var duration: Int = 1
        var startTime: Date = {
            Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
        }()
        var endTime: Date = {
            Calendar.current.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
        }()
        var dependencyOverridesJSON: String?
        var pairedFromTaskId: String?
        var scheduleLocked: Bool = false
        var teamMemberIdsString: String = ""

        @Relationship(deleteRule: .nullify)
        var project: OPSSchemaLegacyCoreModels.Project?

        @Relationship(deleteRule: .nullify)
        var taskType: OPSSchemaLegacyTaskModels.TaskType?

        @Relationship(deleteRule: .noAction)
        var teamMembers: [OPSSchemaLegacyCoreModels.User] = []

        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var deletedAt: Date?
        var createdAt: Date?

        init(
            id: String,
            projectId: String,
            taskTypeId: String,
            companyId: String,
            status: TaskStatus = .active,
            taskColor: String = "#59779F"
        ) {
            self.id = id
            self.projectId = projectId
            self.taskTypeId = taskTypeId
            self.companyId = companyId
            self.status = status
            self.taskColor = taskColor
            self.taskNotes = nil
            self.startDate = nil
            self.endDate = nil
            self.duration = 1
            self.displayOrder = 0
            self.teamMemberIdsString = ""
            self.teamMembers = []
        }
    }
}

/// Frozen `SiteVisit` shape as it shipped through V1–V10: `opportunityId` is a
/// REQUIRED `String`. The live `SiteVisit` (DataModels/Supabase/SiteVisit.swift)
/// relaxed `opportunityId` to optional at the V10→V11 boundary so a site visit
/// can start before a lead is selected. Because `SiteVisit` participates in
/// every historical versioned schema, mutating the live model in place would
/// shift the persistent (Core Data) entity-version hash of `SiteVisit` in V1–V10
/// — the snapshots that must reproduce the already-shipped on-disk shape exactly.
/// Freezing the old shape here keeps V1–V10 byte-identical to what shipped and
/// confines the optionality relaxation to the single V10→V11 lightweight stage.
/// (Same discipline as `OPSSchemaLegacyCoreModels` / `OPSSchemaLegacyTaskModels`.)
enum OPSSchemaLegacySiteVisit {
    @Model
    final class SiteVisit: Identifiable {
        @Attribute(.unique) var id: String
        var opportunityId: String
        var companyId: String
        var status: SiteVisitStatus
        var scheduledAt: Date?
        var completedAt: Date?
        var notes: String?
        var address: String?
        var assignedTo: String?
        var createdAt: Date

        init(
            id: String = UUID().uuidString,
            opportunityId: String,
            companyId: String,
            status: SiteVisitStatus = .scheduled,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.opportunityId = opportunityId
            self.companyId = companyId
            self.status = status
            self.createdAt = createdAt
        }
    }
}

/// Frozen `SiteVisit` shape as it shipped through V11–V14 — an OPTIONAL
/// `opportunityId: String?` (the V10→V11 relaxation) but NO `loggedActivityId`.
/// The live top-level `SiteVisit` adds `loggedActivityId` (the site-visit →
/// timeline auto-post idempotency key) from V15 onward. `SiteVisit` was
/// version-scoped at V10→V11 via `v11SiteVisitModel` pointing at the live class;
/// adding a property to that live class would shift the fingerprint of V11, V12,
/// V13 AND V14 by the same delta — the hazard documented in `OPSApp.swift`.
/// Pulling the V11–V14 shape out and freezing it (mirror of
/// `OPSSchemaLegacyActivity`) confines the change to the V14→V15 boundary.
/// Migration-fingerprint only — runtime code always uses the top-level model.
enum OPSSchemaLegacySiteVisitV11 {
    @Model
    final class SiteVisit: Identifiable {
        @Attribute(.unique) var id: String
        var opportunityId: String?
        var companyId: String
        var status: SiteVisitStatus
        var scheduledAt: Date?
        var completedAt: Date?
        var notes: String?
        var address: String?
        var assignedTo: String?
        var createdAt: Date

        init(
            id: String = UUID().uuidString,
            opportunityId: String? = nil,
            companyId: String,
            status: SiteVisitStatus = .scheduled,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.opportunityId = opportunityId
            self.companyId = companyId
            self.status = status
            self.createdAt = createdAt
        }
    }
}

/// Frozen `Activity` shape as it shipped through V1–V13 — a REQUIRED
/// `opportunityId: String`, and NO `clientId` / `projectId`. The live top-level
/// `Activity` widens `opportunityId` to optional and adds `clientId`/`projectId`
/// (unified-activity parents) from V14 onward. `Activity` was in
/// `unchangedModels`, so that widening would otherwise shift EVERY historical
/// schema's fingerprint by the same delta — the exact hazard documented in
/// `OPSApp.swift`. Pulling the frozen shape out and version-scoping it (mirror
/// of `OPSSchemaLegacySiteVisit`) confines the change to the V13→V14 boundary.
/// Migration-fingerprint only — runtime code always uses the top-level model.
enum OPSSchemaLegacyActivity {
    @Model
    final class Activity: Identifiable {
        @Attribute(.unique) var id: String
        var opportunityId: String
        var companyId: String
        var type: ActivityType
        var subject: String?
        var bodyText: String?
        var content: String?
        var direction: String?
        var outcome: String?
        var durationMinutes: Int?
        var callSource: String?
        var callerNumber: String?
        var callStartedAt: Date?
        var isRead: Bool
        var hasAttachments: Bool
        var attachmentCount: Int
        var createdBy: String?
        var createdAt: Date

        init(
            id: String = UUID().uuidString,
            opportunityId: String,
            companyId: String,
            type: ActivityType,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.opportunityId = opportunityId
            self.companyId = companyId
            self.type = type
            self.isRead = false
            self.hasAttachments = false
            self.attachmentCount = 0
            self.createdAt = createdAt
        }
    }
}

/// Frozen `ProjectNote` shape as it shipped through V1–V12 — WITHOUT the
/// `eventKind` / `contentMetadataJSON` system-event columns. The live top-level
/// `ProjectNote` adds those two optional attributes (live `project_notes`
/// `event_kind` / `content_metadata`) from V13 onward. `ProjectNote` was in
/// `unchangedModels`, so widening it in place made V12 and V13 byte-identical —
/// SwiftData then rejects the whole plan with "Duplicate version checksums
/// across stages detected" the moment the chain is activated past V12 (the
/// dormant-at-V10 store never traversed the stage, which is why it went
/// unnoticed). Pulling the pre-widening shape out and version-scoping it (mirror
/// of `OPSSchemaLegacyActivity`) confines the change to the V12→V13 boundary and
/// gives that stage a real fingerprint delta. Migration-fingerprint only —
/// runtime code always uses the top-level model.
enum OPSSchemaLegacyProjectNote {
    @Model
    final class ProjectNote: Identifiable {
        @Attribute(.unique) var id: String
        var projectId: String
        var companyId: String
        var authorId: String
        var content: String
        var attachmentsJSON: String
        var mentionedUserIdsString: String
        var photoURL: String?
        var createdAt: Date
        var updatedAt: Date?
        var deletedAt: Date?
        var lastSyncedAt: Date?
        var needsSync: Bool = false

        init(
            id: String = UUID().uuidString,
            projectId: String,
            companyId: String,
            authorId: String,
            content: String = "",
            photoURL: String? = nil,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.projectId = projectId
            self.companyId = companyId
            self.authorId = authorId
            self.content = content
            self.attachmentsJSON = "[]"
            self.mentionedUserIdsString = ""
            self.photoURL = photoURL
            self.createdAt = createdAt
        }
    }
}

enum OPSSchemaCommon {
    /// Models present in both V2 and V3 (and unchanged across the V2→V3
    /// boundary). The inventory entities live only in V2; the catalog/product-
    /// extension entities live only in V3. WizardState is appended per-version
    /// so V1's legacy shape stays scoped to V1.
    static let unchangedModels: [any PersistentModel.Type] = [
        // Core data models
        TaskTemplate.self,
        TaskStatusOption.self,
        SyncOperation.self,
        OpsContact.self,

        // Supabase-backed models
        Opportunity.self,
        // NOTE: Activity is intentionally NOT here. Its persistent shape changed
        // at the V13→V14 boundary (opportunityId String → String?, plus new
        // clientId/projectId for unified-activity parents), so it is
        // version-scoped: the frozen `OPSSchemaLegacyActivity.Activity`
        // (required opportunityId, no client/project) backs V1–V13 and the live
        // `Activity` (optional, +client/project) backs V14+. See
        // `v1ToV12ActivityModel` / `v13ActivityModel`.
        FollowUp.self,
        StageTransition.self,
        Estimate.self,
        EstimateLineItem.self,
        Invoice.self,
        InvoiceLineItem.self,
        Payment.self,
        Product.self,
        // NOTE: SiteVisit is intentionally NOT here. Its persistent shape
        // changed at TWO boundaries — V10→V11 (opportunityId String → String?)
        // and V14→V15 (+ loggedActivityId) — so it is version-scoped three ways:
        // the frozen `OPSSchemaLegacySiteVisit.SiteVisit` (required opportunityId)
        // backs V1–V10, the frozen `OPSSchemaLegacySiteVisitV11.SiteVisit`
        // (optional opportunityId, no loggedActivityId) backs V11–V14, and the
        // live `SiteVisit` (+ loggedActivityId) backs V15+. See
        // `v1ToV10SiteVisitModel` / `v11SiteVisitModel` / `v14SiteVisitModel`.
        // NOTE: ProjectNote is intentionally NOT here. Its persistent shape
        // changed at the V12→V13 boundary (added optional `eventKind` +
        // `contentMetadataJSON` system-event columns), so it is version-scoped:
        // the frozen `OPSSchemaLegacyProjectNote.ProjectNote` (no system-event
        // columns) backs V1–V12 and the live `ProjectNote` backs V13+. See
        // `v1ToV12ProjectNoteModel` / `v13ProjectNoteModel`.
        PhotoAnnotation.self,
        CalendarUserEvent.self,

        // Offline-first sync models
        TimeEntry.self,
        SignatureCapture.self,
        FormSubmission.self,
        LocalPhoto.self,

        // Deck builder
        DeckDesign.self
    ]

    /// V1-V3 core models with relationships wired to the V1-V3 task graph.
    static let v1ToV3CoreModels: [any PersistentModel.Type] = [
        OPSSchemaLegacyCoreModels.User.self,
        OPSSchemaLegacyCoreModels.Project.self,
        OPSSchemaLegacyCoreModels.Company.self,
        OPSSchemaLegacyCoreModels.TeamMember.self,
        OPSSchemaLegacyCoreModels.Client.self,
        OPSSchemaLegacyCoreModels.SubClient.self
    ]

    /// V4+ core models use the live graph that includes task reminders.
    static let v4CoreModels: [any PersistentModel.Type] = [
        User.self,
        Project.self,
        Company.self,
        TeamMember.self,
        Client.self,
        SubClient.self
    ]

    /// V1-V3 task models, before V4 added reminder inverse relationships.
    static let v1ToV3TaskModels: [any PersistentModel.Type] = [
        OPSSchemaLegacyTaskModels.ProjectTask.self,
        OPSSchemaLegacyTaskModels.TaskType.self
    ]

    /// V4+ task models include reminder relationships on TaskType/ProjectTask.
    static let v4TaskModels: [any PersistentModel.Type] = [
        ProjectTask.self,
        TaskType.self
    ]

    /// V2-only models: the legacy inventory entities. V3 drops these and
    /// replaces them with the catalog_* / product_* entities listed in
    /// `OPSSchemaV3.catalogModels`.
    static let v2InventoryModels: [any PersistentModel.Type] = [
        InventoryItem.self,
        InventoryTag.self,
        InventoryUnit.self,
        InventorySnapshot.self,
        InventorySnapshotItem.self
    ]

    /// V4 reminder entities. Layered on top of V3 (additive) — bug 4f00c2d7.
    static let v4ReminderModels: [any PersistentModel.Type] = [
        TaskTypeReminder.self,
        TaskReminder.self
    ]

    /// V6 forecast entities. Layered on top of V5 (additive). Cashflow Forecast feature —
    /// see docs/superpowers/specs/2026-05-11-cashflow-forecast-design.md.
    static let v6ForecastModels: [any PersistentModel.Type] = [
        PaymentMilestone.self,
        RecurringExpense.self
    ]

    /// V7 vinyl-order marker projection. The server fields live on
    /// `projects`; this local model keeps the marker offline-readable without
    /// changing the historical `Project` model shape.
    static let v7VinylOrderModels: [any PersistentModel.Type] = [
        ProjectVinylOrderMarker.self
    ]

    /// V8 catalog setup data foundation. These rows back stock-unit identity
    /// and product↔catalog option mapping for the catalog/inventory setup flow.
    static let v8CatalogSetupModels: [any PersistentModel.Type] = [
        CatalogStockUnit.self,
        CatalogProductOptionMapping.self
    ]

    /// V9 synced project photos. Layered on top of V8 (additive). Promotes the
    /// canonical `project_photos` store to a first-class synced entity so every
    /// assigned teammate sees the full gallery — not just the uploader, who was
    /// previously the only device to render the legacy `projects.project_images`
    /// optimistic append.
    static let v9ProjectPhotoModels: [any PersistentModel.Type] = [
        ProjectPhoto.self
    ]

    /// V10 stock-unit lifecycle ledger. Additive over V9 — `CatalogStockUnitEvent`
    /// is a brand-new @Model mirroring the immutable `catalog_stock_unit_events`
    /// table so offcut provenance (source roll ↔ banked offcut) syncs locally.
    static let v10StockUnitEventModels: [any PersistentModel.Type] = [
        CatalogStockUnitEvent.self
    ]

    /// SiteVisit as it shipped through V1–V10 — frozen, required `opportunityId`.
    /// Pulled out of `unchangedModels` so the V10→V11 optionality relaxation is
    /// isolated to one boundary instead of silently rewriting every historical
    /// schema's `SiteVisit` hash.
    static let v1ToV10SiteVisitModel: [any PersistentModel.Type] = [
        OPSSchemaLegacySiteVisit.SiteVisit.self
    ]

    /// SiteVisit as it shipped through V11–V14 — optional `opportunityId`, no
    /// `loggedActivityId`. Frozen so the V14→V15 addition of `loggedActivityId`
    /// (site-visit → timeline auto-post idempotency key) is isolated to one
    /// boundary instead of silently rewriting every V11–V14 schema's `SiteVisit`
    /// hash. Mirror of `v1ToV12ActivityModel`.
    static let v11SiteVisitModel: [any PersistentModel.Type] = [
        OPSSchemaLegacySiteVisitV11.SiteVisit.self
    ]

    /// SiteVisit from V15 onward — the live model, which adds `loggedActivityId`
    /// (a local-only idempotency key stamped when a completed visit posts its
    /// "Site visit" activity to the timeline). Mirror of `v13ActivityModel`.
    /// (The `v14` suffix is the pre-consolidation introduction version; after the
    /// three-way schema reconciliation this live shape first appears at V15.)
    static let v14SiteVisitModel: [any PersistentModel.Type] = [
        SiteVisit.self
    ]

    /// Activity as it shipped through V1–V13 — frozen, required `opportunityId`,
    /// no `clientId`/`projectId`. Pulled out of `unchangedModels` so the V13→V14
    /// widening (opportunityId → optional, + client/project parents) is isolated
    /// to one boundary instead of silently rewriting every historical schema's
    /// `Activity` hash. Mirror of `v1ToV10SiteVisitModel`. (The `V12` suffix is
    /// the pre-consolidation introduction version; after the three-way schema
    /// reconciliation this frozen shape backs V1–V13.)
    static let v1ToV12ActivityModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyActivity.Activity.self
    ]

    /// Activity from V14 onward — the live model with optional `opportunityId`
    /// plus `clientId`/`projectId`, so an activity can be parented to a lead,
    /// a client, OR a job. Mirror of `v11SiteVisitModel`. (The `v13` suffix is
    /// the pre-consolidation introduction version; after the three-way schema
    /// reconciliation this live shape first appears at V14.)
    static let v13ActivityModel: [any PersistentModel.Type] = [
        Activity.self
    ]

    /// ProjectNote as it shipped through V1–V12 — frozen, WITHOUT the
    /// `eventKind` / `contentMetadataJSON` system-event columns. Pulled out of
    /// `unchangedModels` so the V12→V13 addition of those two optional columns is
    /// isolated to one boundary — otherwise V12 and V13 are byte-identical and
    /// SwiftData aborts plan construction with "Duplicate version checksums
    /// across stages". Mirror of `v1ToV12ActivityModel`.
    static let v1ToV12ProjectNoteModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyProjectNote.ProjectNote.self
    ]

    /// ProjectNote from V13 onward — the live model with optional `eventKind`
    /// (system-event discriminator) and `contentMetadataJSON` (structured jsonb
    /// payload for system entries). Mirror of `v13ActivityModel`.
    static let v13ProjectNoteModel: [any PersistentModel.Type] = [
        ProjectNote.self
    ]

    /// V11 site-visit capture packet. Additive over V10 — captures evidence,
    /// visit types, checklist answers, LiDAR dimensioned photos, and CanPro
    /// deck designs before a project exists so the reviewed packet can seed
    /// project creation.
    static let v11SiteVisitCaptureModels: [any PersistentModel.Type] = [
        SiteVisitCaptureArtifact.self,
        SiteVisitType.self,
        SiteVisitChecklistAnswer.self
    ]

    /// V12 site-visit identity draft. Additive over V11 — stores local-first
    /// client/lead contact details while the operator captures the visit before
    /// selecting or creating the final lead.
    static let v12SiteVisitIdentityModels: [any PersistentModel.Type] = [
        SiteVisitIdentityDraft.self
    ]

    /// V3 catalog/product models other than ProductBundleItem. Historical
    /// schemas append a frozen bundle-row shape; V8 appends the live top-level
    /// ProductBundleItem with the additive relationship fields.
    private static let v3CatalogModelsExcludingBundleItem: [any PersistentModel.Type] = [
        CatalogCategory.self,
        CatalogItem.self,
        CatalogVariant.self,
        CatalogOption.self,
        CatalogOptionValue.self,
        CatalogVariantOptionValue.self,
        CatalogTag.self,
        CatalogItemTag.self,
        CatalogUnit.self,
        CatalogSnapshot.self,
        CatalogSnapshotItem.self,
        CatalogOrder.self,
        CatalogOrderItem.self,
        CompanyDefaultProduct.self,

        ProductOption.self,
        ProductOptionValue.self,
        ProductPricingModifier.self,
        ProductMaterial.self
    ]

    /// V3-only models: catalog & variant model + configurable Products +
    /// the company-defaults adapter map. Replaces the V2 inventory entities.
    /// ProductBundleItem is frozen here so V3-V7 schema fingerprints do not
    /// silently inherit V8's additive bundle relationship fields.
    static let v3CatalogModels: [any PersistentModel.Type] = [
        v3CatalogModelsExcludingBundleItem,
        [OPSSchemaLegacyCatalogModels.ProductBundleItem.self]
    ].flatMap { $0 }

    /// V8 catalog/product models use the live ProductBundleItem shape. This is
    /// the only schema stage that sees relationshipKind/suggestion metadata.
    static let v8CatalogModels: [any PersistentModel.Type] = [
        v3CatalogModelsExcludingBundleItem,
        [ProductBundleItem.self]
    ].flatMap { $0 }
}
