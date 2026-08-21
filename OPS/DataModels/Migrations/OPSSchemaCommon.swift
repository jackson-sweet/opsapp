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

/// Opportunity as it shipped through V15. The live model gained `images`,
/// `latitude`, and `longitude` after V15 was already on devices. Keeping this
/// exact stored-property graph prevents that later widening from rewriting the
/// fingerprint of every released schema.
enum OPSSchemaLegacyOpportunityV15 {
    @Model
    final class Opportunity: Identifiable {
        @Attribute(.unique) var id: String
        var companyId: String
        var title: String?
        var contactName: String
        var contactEmail: String?
        var contactPhone: String?
        var descriptionText: String?
        var address: String?
        var stage: PipelineStage
        var stageEnteredAt: Date
        var stageManuallySet: Bool
        var assignedTo: String?
        var priority: String?
        var source: String?
        var quoteDeliveryMethod: QuoteDeliveryMethod?
        var estimatedValue: Double?
        var actualValue: Double?
        var winProbabilityOverride: Int?
        var expectedCloseDate: Date?
        var actualCloseDate: Date?
        var nextFollowUpAt: Date?
        var lastActivityAt: Date?
        var projectId: String?
        var clientId: String?
        var lostReason: String?
        var lostNotes: String?
        var deletedAt: Date?
        var archivedAt: Date?
        var tags: [String]
        var sourceEmailId: String?
        var correspondenceCount: Int
        var outboundCount: Int
        var inboundCount: Int
        var lastInboundAt: Date?
        var lastOutboundAt: Date?
        var lastMessageDirection: String?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String = UUID().uuidString,
            companyId: String,
            contactName: String,
            stage: PipelineStage = .newLead,
            stageEnteredAt: Date = Date(),
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.companyId = companyId
            self.contactName = contactName
            self.stage = stage
            self.stageEnteredAt = stageEnteredAt
            self.stageManuallySet = false
            self.tags = []
            self.correspondenceCount = 0
            self.outboundCount = 0
            self.inboundCount = 0
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

/// Opportunity as it stood at V16–V17: images + coordinates present, no
/// `assignmentVersion` and no chase/summary columns. The live model gained
/// those at V18 (guarded lead assignment + the Leads chase system), so this
/// exact stored-property graph keeps the V16/V17 fingerprints stable.
enum OPSSchemaLegacyOpportunityV17 {
    @Model
    final class Opportunity: Identifiable {
        @Attribute(.unique) var id: String
        var companyId: String
        var title: String?
        var contactName: String
        var contactEmail: String?
        var contactPhone: String?
        var descriptionText: String?
        var address: String?
        var stage: PipelineStage
        var stageEnteredAt: Date
        var stageManuallySet: Bool
        var assignedTo: String?
        var priority: String?
        var source: String?
        var quoteDeliveryMethod: QuoteDeliveryMethod?
        var estimatedValue: Double?
        var actualValue: Double?
        var winProbabilityOverride: Int?
        var expectedCloseDate: Date?
        var actualCloseDate: Date?
        var nextFollowUpAt: Date?
        var lastActivityAt: Date?
        var projectId: String?
        var clientId: String?
        var lostReason: String?
        var lostNotes: String?
        var deletedAt: Date?
        var archivedAt: Date?
        var tags: [String]
        var sourceEmailId: String?
        var images: [String] = []
        var latitude: Double?
        var longitude: Double?
        var correspondenceCount: Int
        var outboundCount: Int
        var inboundCount: Int
        var lastInboundAt: Date?
        var lastOutboundAt: Date?
        var lastMessageDirection: String?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String = UUID().uuidString,
            companyId: String,
            contactName: String,
            stage: PipelineStage = .newLead,
            stageEnteredAt: Date = Date(),
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.companyId = companyId
            self.contactName = contactName
            self.stage = stage
            self.stageEnteredAt = stageEnteredAt
            self.stageManuallySet = false
            self.tags = []
            self.correspondenceCount = 0
            self.outboundCount = 0
            self.inboundCount = 0
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

/// Opportunity exactly as it shipped at V18: images/coordinates, guarded
/// assignment, and the first chase/summary fields are present, but the later
/// `operatorActionRequiredAt` ownership-correction signal is not. Freezing this
/// graph prevents that additive V19 field from rewriting V18's released
/// fingerprint.
enum OPSSchemaLegacyOpportunityV18 {
    @Model
    final class Opportunity: Identifiable {
        @Attribute(.unique) var id: String
        var companyId: String
        var title: String?
        var contactName: String
        var contactEmail: String?
        var contactPhone: String?
        var descriptionText: String?
        var address: String?
        var stage: PipelineStage
        var stageEnteredAt: Date
        var stageManuallySet: Bool
        var assignedTo: String?
        var assignmentVersion: Int64 = 0
        var priority: String?
        var source: String?
        var quoteDeliveryMethod: QuoteDeliveryMethod?
        var estimatedValue: Double?
        var actualValue: Double?
        var winProbabilityOverride: Int?
        var expectedCloseDate: Date?
        var actualCloseDate: Date?
        var nextFollowUpAt: Date?
        var lastActivityAt: Date?
        var projectId: String?
        var clientId: String?
        var lostReason: String?
        var lostNotes: String?
        var deletedAt: Date?
        var archivedAt: Date?
        var tags: [String]
        var sourceEmailId: String?
        var images: [String] = []
        var latitude: Double?
        var longitude: Double?
        var correspondenceCount: Int
        var outboundCount: Int
        var inboundCount: Int
        var lastInboundAt: Date?
        var lastOutboundAt: Date?
        var lastMessageDirection: String?
        var handledAt: Date?
        var aiSummary: String?
        var aiSummaryUpdatedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String = UUID().uuidString,
            companyId: String,
            contactName: String,
            stage: PipelineStage = .newLead,
            stageEnteredAt: Date = Date(),
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.companyId = companyId
            self.contactName = contactName
            self.stage = stage
            self.stageEnteredAt = stageEnteredAt
            self.stageManuallySet = false
            self.tags = []
            self.correspondenceCount = 0
            self.outboundCount = 0
            self.inboundCount = 0
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

/// DeckDesign as it shipped through V15. The live model gained the nullable
/// `opportunityId` after release, so the pre-addition graph must remain frozen
/// for every historical schema fingerprint.
enum OPSSchemaLegacyDeckDesignV15 {
    @Model
    final class DeckDesign: Identifiable {
        @Attribute(.unique) var id: String
        var companyId: String
        var projectId: String?
        var title: String
        var drawingDataJSON: String
        var thumbnailURL: String?
        var localThumbnailPath: String?
        var version: Int = 1
        var createdBy: String?
        var needsSync: Bool = false
        var lastSyncedAt: Date?
        var syncPriority: Int = 1
        var deletedAt: Date?
        var createdAt: Date
        var updatedAt: Date?

        init(
            id: String = UUID().uuidString,
            companyId: String,
            projectId: String? = nil,
            title: String = "Untitled Deck",
            drawingDataJSON: String = "{}",
            createdBy: String? = nil
        ) {
            self.id = id
            self.companyId = companyId
            self.projectId = projectId
            self.title = title
            self.drawingDataJSON = drawingDataJSON
            self.createdBy = createdBy
            self.createdAt = Date()
        }
    }
}

/// ProjectVinylOrderMarker as it shipped V7 through V16. The live model gained
/// `vinylColor` / `vinylPO` (projections of `projects.vinyl_color` /
/// `vinyl_po`, VINYL ORDERS board 2026-07-16) after V16 was already on
/// devices, so the pre-widening shape stays frozen for every historical
/// schema fingerprint.
enum OPSSchemaLegacyVinylOrderV16 {
    @Model
    final class ProjectVinylOrderMarker: Identifiable {
        @Attribute(.unique) var id: String
        var statusRaw: String
        var orderedAt: Date?
        var orderedBy: String?
        var sourceProjectUpdatedAt: Date?
        var lastSyncedAt: Date?

        init(
            projectId: String,
            status: ProjectVinylOrderStatus = .notOrdered,
            orderedAt: Date? = nil,
            orderedBy: String? = nil,
            sourceProjectUpdatedAt: Date? = nil
        ) {
            self.id = projectId
            self.statusRaw = status.rawValue
            self.orderedAt = orderedAt
            self.orderedBy = orderedBy
            self.sourceProjectUpdatedAt = sourceProjectUpdatedAt
            self.lastSyncedAt = nil
        }
    }
}

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

/// Frozen `SiteVisit` shape as it shipped through V15–V19. V15 added the
/// nullable `loggedActivityId` to the V11 shape; V20 widens the live model for
/// complete Supabase round-tripping. Keeping this exact graph prevents the
/// cloud fields from rewriting any released schema checksum.
enum OPSSchemaLegacySiteVisitV19 {
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
        var loggedActivityId: String?

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

/// Frozen `SiteVisit` shape as it shipped through V20–V22 — the full cloud
/// projection, WITHOUT the V23 booking fields (`bookedAt`,
/// `reminderLeadMinutes`). Every store written between the V20 cloud release
/// and the booking build carries this exact fingerprint; keeping it byte-exact
/// is what lets those installs open and lightweight-migrate to V23.
/// Migration-fingerprint only — runtime code always uses the top-level model.
enum OPSSchemaLegacySiteVisitV22 {
    @Model
    final class SiteVisit: Identifiable {
        @Attribute(.unique) var id: String
        var opportunityId: String?
        var companyId: String
        var projectId: String?
        var projectRef: String?
        var clientId: String?
        var clientRef: String?
        var status: SiteVisitStatus
        var scheduledAt: Date?
        var durationMinutes: Int = 60
        var assigneeIds: [String] = []
        var completedAt: Date?
        var notes: String?
        var internalNotes: String?
        var measurements: String?
        var photos: [String] = []
        var address: String?
        var assignedTo: String?
        var calendarEventId: String?
        var createdBy: String?
        var createdAt: Date
        var updatedAt: Date?
        var deletedAt: Date?
        var needsSync: Bool = false
        var lastSyncedAt: Date?
        var loggedActivityId: String?

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

/// Frozen `SiteVisit` shape as it shipped in V23 — the V20 cloud projection
/// plus `bookedAt` and `reminderLeadMinutes`, before Phase C appointment
/// presentation metadata. V24 adds those nullable server-owned fields without
/// rewriting the released V23 fingerprint.
enum OPSSchemaLegacySiteVisitV23 {
    @Model
    final class SiteVisit: Identifiable {
        @Attribute(.unique) var id: String
        var opportunityId: String?
        var companyId: String
        var projectId: String?
        var projectRef: String?
        var clientId: String?
        var clientRef: String?
        var status: SiteVisitStatus
        var scheduledAt: Date?
        var durationMinutes: Int = 60
        var assigneeIds: [String] = []
        var completedAt: Date?
        var notes: String?
        var internalNotes: String?
        var measurements: String?
        var photos: [String] = []
        var address: String?
        var assignedTo: String?
        var calendarEventId: String?
        var createdBy: String?
        var createdAt: Date
        var updatedAt: Date?
        var deletedAt: Date?
        var needsSync: Bool = false
        var lastSyncedAt: Date?
        var loggedActivityId: String?
        var bookedAt: Date?
        var reminderLeadMinutes: Int?

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

/// Frozen `SiteVisitIdentityDraft` shape as it shipped through V12–V19. V20
/// adds cloud deletion/sync bookkeeping and author provenance to the live
/// model, while this type keeps installed-store fingerprints recognizable.
enum OPSSchemaLegacySiteVisitIdentityDraftV19 {
    @Model
    final class SiteVisitIdentityDraft: Identifiable {
        @Attribute(.unique) var id: String
        var siteVisitId: String
        var companyId: String
        var opportunityId: String?
        var clientId: String?
        var subClientId: String?
        var searchText: String
        var clientName: String
        var contactName: String
        var preferredEmail: String
        var additionalEmailsJSON: String
        var phoneNumber: String
        var address: String
        var notes: String
        var createdAt: Date
        var updatedAt: Date
        var lastCommittedAt: Date?

        init(
            id: String = UUID().uuidString,
            siteVisitId: String,
            companyId: String,
            opportunityId: String? = nil,
            clientId: String? = nil,
            subClientId: String? = nil,
            searchText: String = "",
            clientName: String = "",
            contactName: String = "",
            preferredEmail: String = "",
            additionalEmailsJSON: String = "[]",
            phoneNumber: String = "",
            address: String = "",
            notes: String = "",
            createdAt: Date = Date()
        ) {
            self.id = id
            self.siteVisitId = siteVisitId
            self.companyId = companyId
            self.opportunityId = opportunityId
            self.clientId = clientId
            self.subClientId = subClientId
            self.searchText = searchText
            self.clientName = clientName
            self.contactName = contactName
            self.preferredEmail = preferredEmail
            self.additionalEmailsJSON = additionalEmailsJSON
            self.phoneNumber = phoneNumber
            self.address = address
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = createdAt
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

/// `Activity` exactly as it shipped from V14 through V20 — unified lead/client/
/// job parents and call provenance, but WITHOUT the per-message email identity
/// (`emailMessageId` / `emailThreadId` / `fromEmail` / `toEmails` / `ccEmails`).
/// The live model gains those five at V21. Freezing this graph keeps every
/// released V14–V20 fingerprint exact — the same version-scoping used at the
/// V13→V14 boundary (`OPSSchemaLegacyActivity`). Migration-fingerprint only;
/// runtime code always uses the top-level `Activity`.
///
/// (The `V19` suffix is the version this freeze was introduced at. V20 — the
/// cloud-backed site-visit schema — widened `SiteVisit`, never `Activity`, so
/// this identical graph also backs V20.)
enum OPSSchemaLegacyActivityV19 {
    @Model
    final class Activity: Identifiable {
        @Attribute(.unique) var id: String
        var opportunityId: String?
        var clientId: String?
        var projectId: String?
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
            opportunityId: String? = nil,
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

/// `Activity` exactly as it stands at V21 — unified lead/client/job parents,
/// call provenance, and the per-message email identity, but WITHOUT the
/// site-visit link (`siteVisitId`). The live model gains that at V22. Freezing
/// this graph keeps the V21 fingerprint exact — the same version-scoping used
/// at the V13→V14 and V20→V21 boundaries. Migration-fingerprint only; runtime
/// code always uses the top-level `Activity`.
enum OPSSchemaLegacyActivityV21 {
    @Model
    final class Activity: Identifiable {
        @Attribute(.unique) var id: String
        var opportunityId: String?
        var clientId: String?
        var projectId: String?
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
        var emailMessageId: String?
        var emailThreadId: String?
        var fromEmail: String?
        // `= []` mirrors the live model exactly. A mandatory attribute with no
        // default cannot be added by an inferred migration — see `Activity`.
        var toEmails: [String] = []
        var ccEmails: [String] = []
        var isRead: Bool
        var hasAttachments: Bool
        var attachmentCount: Int
        var createdBy: String?
        var createdAt: Date

        init(
            id: String = UUID().uuidString,
            opportunityId: String? = nil,
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
            self.toEmails = []
            self.ccEmails = []
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

/// Frozen `PhotoAnnotation` shape as it shipped through V1–V14 — WITHOUT the
/// `syncFailureCount` / `syncParkedAt` retry-hygiene columns. Those two stored
/// properties were added to the live `PhotoAnnotation` (durable photo-markup
/// soft-delete + retry, 2026-07-03) AFTER the V10 ship point, but `PhotoAnnotation`
/// was in `unchangedModels`, so the live class silently shifted V10's (and every
/// historical schema's) persistent fingerprint — a real V10 store on a shipped
/// device would no longer match any VersionedSchema and be destructively wiped.
/// Version-scoping it (mirror of `OPSSchemaLegacyProjectNote`) freezes the
/// pre-widening shape for V1–V14 and introduces the two columns at V14→V15.
/// Migration-fingerprint only — runtime code always uses the top-level model.
enum OPSSchemaLegacyPhotoAnnotation {
    @Model
    final class PhotoAnnotation: Identifiable {
        @Attribute(.unique) var id: String
        var projectId: String
        var companyId: String
        var photoURL: String
        var annotationURL: String?
        var note: String
        var authorId: String
        var createdAt: Date
        var updatedAt: Date?
        var deletedAt: Date?
        var renderedPhotoURL: String?
        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var localDrawingData: Data?
        var dimensionsData: Data?
        var localDepthMapPath: String?
        var localSidecarPath: String?
        var localCaptureFinishedAt: Date?

        init(
            id: String = UUID().uuidString,
            projectId: String,
            companyId: String,
            photoURL: String,
            authorId: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.projectId = projectId
            self.companyId = companyId
            self.photoURL = photoURL
            self.note = ""
            self.authorId = authorId
            self.createdAt = createdAt
        }
    }
}

/// PhotoAnnotation as it stood at V15–V17: retry-hygiene columns
/// (`syncFailureCount` / `syncParkedAt`) present, WITHOUT the collaborative-
/// markup columns. The live model gained `layersData` / `changeLogData` /
/// `beforeSnapshotURL` / `afterSnapshotURL` / `hiddenAuthorIdsData` at V18
/// (author-scoped markup layers), so this exact stored-property graph keeps
/// the V15–V17 fingerprints stable.
enum OPSSchemaLegacyPhotoAnnotationV17 {
    @Model
    final class PhotoAnnotation: Identifiable {
        @Attribute(.unique) var id: String
        var projectId: String
        var companyId: String
        var photoURL: String
        var annotationURL: String?
        var note: String
        var authorId: String
        var createdAt: Date
        var updatedAt: Date?
        var deletedAt: Date?
        var renderedPhotoURL: String?
        var lastSyncedAt: Date?
        var needsSync: Bool = false
        var syncFailureCount: Int = 0
        var syncParkedAt: Date?
        var localDrawingData: Data?
        var dimensionsData: Data?
        var localDepthMapPath: String?
        var localSidecarPath: String?
        var localCaptureFinishedAt: Date?

        init(
            id: String = UUID().uuidString,
            projectId: String,
            companyId: String,
            photoURL: String,
            authorId: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.projectId = projectId
            self.companyId = companyId
            self.photoURL = photoURL
            self.note = ""
            self.authorId = authorId
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
        // NOTE: PhotoAnnotation is intentionally NOT here. The live model gained
        // two retry-hygiene columns (`syncFailureCount`, `syncParkedAt`) after the
        // V10 ship point, so it is version-scoped: the frozen
        // `OPSSchemaLegacyPhotoAnnotation.PhotoAnnotation` (pre-widening) backs
        // V1–V14 and the live `PhotoAnnotation` backs V15+. See
        // `v1ToV14PhotoAnnotationModel` / `v15PhotoAnnotationModel`.
        CalendarUserEvent.self,

        // Offline-first sync models
        TimeEntry.self,
        SignatureCapture.self,
        FormSubmission.self,
        LocalPhoto.self,

        // NOTE: Opportunity and DeckDesign are intentionally NOT here. Their
        // persistent shapes changed after V15 shipped, so both are version-
        // scoped at the V15→V16 boundary below.
    ]

    /// Opportunity as shipped through V15, before images and coordinates.
    static let v1ToV15OpportunityModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyOpportunityV15.Opportunity.self
    ]

    /// Opportunity as it stood at V16–V17 — images and coordinates, before the
    /// guarded-assignment snapshot and the chase/summary columns.
    static let v16ToV17OpportunityModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyOpportunityV17.Opportunity.self
    ]

    /// Opportunity exactly as released at V18 — guarded assignment plus the
    /// first chase/summary fields, before `operatorActionRequiredAt`.
    static let v18OpportunityModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyOpportunityV18.Opportunity.self
    ]

    /// Opportunity from V19 onward — the live model, including the nullable
    /// `operatorActionRequiredAt` ownership-correction signal.
    static let v19OpportunityModel: [any PersistentModel.Type] = [
        Opportunity.self
    ]

    /// DeckDesign as shipped through V15, before lead attachment.
    static let v1ToV15DeckDesignModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyDeckDesignV15.DeckDesign.self
    ]

    /// DeckDesign from V16 onward, including nullable `opportunityId`.
    static let v16DeckDesignModel: [any PersistentModel.Type] = [
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

    /// Vinyl-order marker projection as shipped V7 through V16, before
    /// color/PO. The server fields live on `projects`; this local model keeps
    /// the marker offline-readable without changing the historical `Project`
    /// model shape.
    static let v7ToV16VinylOrderModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyVinylOrderV16.ProjectVinylOrderMarker.self
    ]

    /// Vinyl-order marker from V17 onward, including `vinylColor` / `vinylPO`.
    static let v17VinylOrderModel: [any PersistentModel.Type] = [
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

    /// SiteVisit as it shipped from V15 through V19 — adds
    /// `loggedActivityId` to the V11 shape, but predates cloud sync fields.
    /// (The `v14` suffix is the pre-consolidation introduction version; after the
    /// three-way schema reconciliation this live shape first appears at V15.)
    static let v14SiteVisitModel: [any PersistentModel.Type] = [
        OPSSchemaLegacySiteVisitV19.SiteVisit.self
    ]

    /// SiteVisit from V20 onward — the live cloud-backed model.
    /// SiteVisit as it shipped through V20–V22 — the cloud-sync shape, WITHOUT
    /// the V23 booking fields. Frozen at `OPSSchemaLegacySiteVisitV22` because
    /// the booking build widened the live class in place, which silently
    /// shifted the V20–V22 fingerprints and made every installed store
    /// unrecognizable (CoreData 134504 on device, 2026-08-17). The widened
    /// live model begins at V23.
    static let v20SiteVisitModel: [any PersistentModel.Type] = [
        OPSSchemaLegacySiteVisitV22.SiteVisit.self
    ]

    /// SiteVisit as released in V23, frozen before V24 adds Phase C
    /// appointment presentation metadata.
    static let v23SiteVisitModel: [any PersistentModel.Type] = [
        OPSSchemaLegacySiteVisitV23.SiteVisit.self
    ]

    /// The live SiteVisit from V24 onward.
    static let v24SiteVisitModel: [any PersistentModel.Type] = [
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

    /// Activity across V14–V20 — optional `opportunityId` plus `clientId` /
    /// `projectId`, so an activity can be parented to a lead, a client, OR a
    /// job. Frozen at `OPSSchemaLegacyActivityV19` because V21 widens the live
    /// model with per-message email identity; without the freeze that addition
    /// would rewrite seven released fingerprints. Mirror of `v11SiteVisitModel`.
    /// (The `v13` suffix is the pre-consolidation introduction version; after
    /// the three-way schema reconciliation this shape first appears at V14. V20
    /// widened `SiteVisit`, not `Activity`, so it reuses this exact graph.)
    static let v13ActivityModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyActivityV19.Activity.self
    ]

    /// Activity at V21 — the per-message email identity, frozen at
    /// `OPSSchemaLegacyActivityV21` because V22 widens the live model with the
    /// site-visit link. Without the freeze that addition would rewrite the V21
    /// fingerprint. Mirror of `v13ActivityModel`.
    static let v21ActivityModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyActivityV21.Activity.self
    ]

    /// Activity from V22 onward — the live model, including the `siteVisitId`
    /// link that lets a completed site visit render as a record on the lead's
    /// timeline instead of an unremarkable row. Mirror of
    /// `v19OpportunityModel`.
    static let v22ActivityModel: [any PersistentModel.Type] = [
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

    /// PhotoAnnotation as it shipped through V1–V14 — frozen, WITHOUT the
    /// `syncFailureCount` / `syncParkedAt` retry-hygiene columns. Pulled out of
    /// `unchangedModels` so those two columns (added in-place after the V10 ship
    /// point) do not silently drift V10's fingerprint and destructively wipe real
    /// shipped stores. Mirror of `v1ToV12ProjectNoteModel`.
    static let v1ToV14PhotoAnnotationModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyPhotoAnnotation.PhotoAnnotation.self
    ]

    /// PhotoAnnotation as it stood at V15–V17 — retry-hygiene columns present,
    /// WITHOUT the collaborative-markup columns (`layersData`, `changeLogData`,
    /// `beforeSnapshotURL`, `afterSnapshotURL`, `hiddenAuthorIdsData`). The live
    /// model gained those at V18 (author-scoped markup layers), so this frozen
    /// stored-property graph keeps the V15–V17 fingerprints stable. Mirror of
    /// `v16ToV17OpportunityModel`.
    static let v15ToV17PhotoAnnotationModel: [any PersistentModel.Type] = [
        OPSSchemaLegacyPhotoAnnotationV17.PhotoAnnotation.self
    ]

    /// PhotoAnnotation from V18 onward — the live model, including the
    /// collaborative-markup layer/change-log/snapshot columns. Mirror of
    /// `v18OpportunityModel`.
    static let v18PhotoAnnotationModel: [any PersistentModel.Type] = [
        PhotoAnnotation.self
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

    /// Site-visit identity draft as it shipped from V12 through V19.
    static let v12SiteVisitIdentityModels: [any PersistentModel.Type] = [
        OPSSchemaLegacySiteVisitIdentityDraftV19.SiteVisitIdentityDraft.self
    ]

    /// Site-visit identity draft from V20 onward — cloud deletion/sync state.
    static let v20SiteVisitIdentityModels: [any PersistentModel.Type] = [
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
