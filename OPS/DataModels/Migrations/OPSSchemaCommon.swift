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
        Activity.self,
        FollowUp.self,
        StageTransition.self,
        Estimate.self,
        EstimateLineItem.self,
        Invoice.self,
        InvoiceLineItem.self,
        Payment.self,
        Product.self,
        SiteVisit.self,
        ProjectNote.self,
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
