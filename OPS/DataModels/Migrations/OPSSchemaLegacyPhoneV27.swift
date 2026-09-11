import Foundation
import SwiftData

/// Exact released stored model shapes from8553b1b4, before Phase19 write
/// metadata. V1–V27 retain this SyncOperation; V11–V27 retain these forms.
/// Never widen these definitions when the live models evolve.
enum OPSSchemaLegacyPhoneV27 {
    @Model
    final class SiteVisitType: Identifiable {
        @Attribute(.unique) var id: String
        var companyId: String
        var slug: String
        var name: String
        var descriptionText: String?
        var isSystemTemplate: Bool
        var isDefault: Bool
        var sortOrder: Int
        var fieldsData: Data?
        var createdAt: Date
        var updatedAt: Date?
        var deletedAt: Date?
        var needsSync: Bool
        var lastSyncedAt: Date?

        init(
            id: String = UUID().uuidString,
            companyId: String,
            slug: String,
            name: String,
            descriptionText: String? = nil,
            isSystemTemplate: Bool = false,
            isDefault: Bool = false,
            sortOrder: Int = 0,
            fields: [SiteVisitTypeFieldDefinition] = [],
            createdAt: Date = Date()
        ) {
            self.id = id
            self.companyId = companyId
            self.slug = slug
            self.name = name
            self.descriptionText = descriptionText
            self.isSystemTemplate = isSystemTemplate
            self.isDefault = isDefault
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.needsSync = true
            self.fields = fields
        }

        var fields: [SiteVisitTypeFieldDefinition] {
            get {
                guard let fieldsData,
                      let decoded = try? JSONDecoder().decode(
                        [SiteVisitTypeFieldDefinition].self,
                        from: fieldsData
                      ) else { return [] }
                return decoded.sorted { $0.sortOrder < $1.sortOrder }
            }
            set {
                fieldsData = try? JSONEncoder().encode(newValue.sorted { $0.sortOrder < $1.sortOrder })
                updatedAt = Date()
                needsSync = true
            }
        }

        /// Trade-agnostic starter visit types. Every subtrade does these three;
        /// the deck-specific type is only seeded for companies running the deck
        /// builder (CanPro). Companies can add their own types on top of these.
        static func builtInTemplates(
            companyId: String,
            deckBuilderEnabled: Bool
        ) -> [SiteVisitType] {
            var templates: [SiteVisitType] = [
                // The default: scoping a job to quote it.
                SiteVisitType(
                    id: "system-\(companyId)-estimate",
                    companyId: companyId,
                    slug: "estimate",
                    name: "Estimate",
                    descriptionText: "Scope a job to quote it.",
                    isSystemTemplate: true,
                    isDefault: true,
                    sortOrder: 0,
                    fields: [
                        .init(id: "scope-of-work", label: "Scope of work", kind: .longText, required: true, sortOrder: 10),
                        .init(id: "site-photos", label: "Site photos", kind: .photo, sortOrder: 20),
                        .init(id: "measurements", label: "Measurements", kind: .measurement, sortOrder: 30),
                        .init(id: "access-parking", label: "Access & parking", kind: .shortText, helpText: "Gate codes, parking, pets", sortOrder: 40),
                        .init(id: "client-priorities", label: "What the client wants", kind: .longText, sortOrder: 50),
                    ]
                ),
                // Diagnose / repair a reported problem.
                SiteVisitType(
                    id: "system-\(companyId)-service-call",
                    companyId: companyId,
                    slug: "service_call",
                    name: "Service Call",
                    descriptionText: "Diagnose and fix a reported issue.",
                    isSystemTemplate: true,
                    sortOrder: 10,
                    fields: [
                        .init(id: "reported-issue", label: "Reported issue", kind: .longText, required: true, sortOrder: 10),
                        .init(id: "service-photos", label: "Photos", kind: .photo, sortOrder: 20),
                        .init(id: "work-done", label: "Work done & findings", kind: .longText, sortOrder: 30),
                        .init(id: "return-needed", label: "Return visit needed", kind: .yesNoNA, sortOrder: 40),
                    ]
                ),
                // Take-offs for an install.
                SiteVisitType(
                    id: "system-\(companyId)-measure-survey",
                    companyId: companyId,
                    slug: "measure_survey",
                    name: "Measure / Survey",
                    descriptionText: "Take measurements and document conditions.",
                    isSystemTemplate: true,
                    sortOrder: 20,
                    fields: [
                        .init(id: "measurements", label: "Measurements", kind: .measurement, required: true, sortOrder: 10),
                        .init(id: "site-photos", label: "Site photos", kind: .photo, sortOrder: 20),
                        .init(id: "conditions", label: "Conditions & obstructions", kind: .longText, sortOrder: 30),
                    ]
                ),
            ]

            if deckBuilderEnabled {
                templates.append(
                    SiteVisitType(
                        id: "system-\(companyId)-deck-estimate",
                        companyId: companyId,
                        slug: "deck_estimate",
                        name: "Deck",
                        descriptionText: "Deck scope, photos, measurements, and design.",
                        isSystemTemplate: true,
                        sortOrder: 30,
                        fields: [
                            .init(id: "client-goals", label: "What the client wants", kind: .longText, sortOrder: 10),
                            .init(id: "existing-structure", label: "Existing structure", kind: .photoMarkup, sortOrder: 20),
                            // No measurement row: measuring is what the visit's
                            // capture tools are for (LiDAR / scaled / dimensioned).
                            // A checklist item demanding the same thing was a second
                            // gate that blocked completion after the work was done.
                            .init(id: "deck-design", label: "Deck design", kind: .deckDesign, required: true, sortOrder: 40),
                        ]
                    )
                )
            }

            return templates
        }
    }

    @Model
    final class SiteVisitChecklistAnswer: Identifiable {
        @Attribute(.unique) var id: String
        var siteVisitId: String
        var companyId: String
        var opportunityId: String?
        var siteVisitTypeId: String?
        var fieldId: String
        var label: String
        var kind: SiteVisitFieldKind
        var required: Bool
        var helpText: String?
        var sortOrder: Int
        var answerValueData: Data?
        var createdBy: String?
        var createdAt: Date
        var updatedAt: Date?
        var deletedAt: Date?
        var needsSync: Bool
        var lastSyncedAt: Date?

        init(
            id: String = UUID().uuidString,
            siteVisitId: String,
            companyId: String,
            opportunityId: String?,
            siteVisitTypeId: String?,
            fieldId: String,
            label: String,
            kind: SiteVisitFieldKind,
            required: Bool,
            helpText: String? = nil,
            sortOrder: Int,
            answerValue: SiteVisitChecklistValue = .empty,
            createdBy: String? = nil,
            createdAt: Date = Date()
        ) {
            self.id = id.lowercased()
            self.siteVisitId = siteVisitId.lowercased()
            self.companyId = companyId.lowercased()
            self.opportunityId = opportunityId?.lowercased()
            self.siteVisitTypeId = siteVisitTypeId
            self.fieldId = fieldId
            self.label = label
            self.kind = kind
            self.required = required
            self.helpText = helpText
            self.sortOrder = sortOrder
            self.createdBy = createdBy?.lowercased()
            self.createdAt = createdAt
            self.needsSync = true
            self.answerValue = answerValue
        }

        var answerValue: SiteVisitChecklistValue {
            get {
                guard let answerValueData,
                      let decoded = try? JSONDecoder().decode(
                        SiteVisitChecklistValue.self,
                        from: answerValueData
                      ) else { return .empty }
                return decoded
            }
            set {
                answerValueData = try? JSONEncoder().encode(newValue)
                updatedAt = Date()
                needsSync = true
            }
        }

        var isActive: Bool {
            deletedAt == nil
        }

        var isAnswered: Bool {
            answerValue.isAnswered
        }

        static func makeAnswers(
            for siteVisitType: SiteVisitType,
            siteVisitId: String,
            companyId: String,
            opportunityId: String?,
            createdBy: String?
        ) -> [SiteVisitChecklistAnswer] {
            siteVisitType.fields.filter(\.isShown).map { field in
                SiteVisitChecklistAnswer(
                    siteVisitId: siteVisitId,
                    companyId: companyId,
                    opportunityId: opportunityId,
                    siteVisitTypeId: siteVisitType.id,
                    fieldId: field.id,
                    label: field.label,
                    kind: field.kind,
                    required: field.required,
                    helpText: field.helpText,
                    sortOrder: field.sortOrder,
                    createdBy: createdBy
                )
            }
        }
    }

    @Model
    final class SyncOperation {
        var id: UUID
        var entityType: String
        var entityId: String
        var operationType: String
        var payload: Data
        var changedFields: String
        var createdAt: Date
        var retryCount: Int = 0
        var lastAttemptedAt: Date?
        /// Lifecycle status. One of:
        /// - `pending`    — queued, eligible for the next outbound push.
        /// - `inProgress` — currently being pushed (set immediately before the network call).
        /// - `completed`  — server confirmed; eligible for cleanup after 24h.
        /// - `failed`     — transient failures exhausted the retry budget (20). Recoverable:
        ///                  the launch / reconnect re-enqueue sweep resets it to `pending`.
        /// - `parked`     — a permanent server rejection (4xx / data / integrity / syntax).
        ///                  NEVER auto-retried. Only an explicit user Retry (→ `pending`,
        ///                  retryCount 0) or Discard moves it. See `SyncErrorClassifier`.
        /// - `quarantined`— site-visit identity/tenant evidence is unsafe. Never sent
        ///                  or exposed through generic Retry; its encrypted recovery
        ///                  entry is the only operator disposition surface.
        var status: String = "pending"
        var lastError: String?

        // Rollback support
        var previousValues: Data?

        // Priority & scheduling
        var priority: Int = 1  // 0 = immediate, 1 = normal, 2 = low
        var requiresWiFi: Bool = false

        // Dependency tracking
        var dependsOnId: String?

        // Completion timestamps
        var completedAt: Date?
        var serverConfirmedAt: Date?

        init(
            entityType: String,
            entityId: String,
            operationType: String,
            payload: Data,
            changedFields: [String],
            previousValues: Data? = nil,
            priority: Int = 1,
            dependsOnId: String? = nil
        ) {
            self.id = UUID()
            self.entityType = entityType
            self.entityId = entityId
            self.operationType = operationType
            self.payload = payload
            self.changedFields = changedFields.joined(separator: ",")
            self.createdAt = Date()
            self.previousValues = previousValues
            self.priority = priority
            self.dependsOnId = dependsOnId
        }

        func getChangedFields() -> [String] {
            changedFields.isEmpty ? [] : changedFields.components(separatedBy: ",")
        }

        var isPending: Bool { status == "pending" }
        var isInProgress: Bool { status == "inProgress" }
        var isFailed: Bool { status == "failed" }
        var isParked: Bool { status == "parked" }
        var isCompleted: Bool { status == "completed" }
        var canRetry: Bool { retryCount < 20 }

        /// Exponential backoff delay capped at 60 seconds.
        /// Use this with `lastAttemptedAt` to determine the earliest eligible retry time:
        /// `lastAttemptedAt.addingTimeInterval(backoffDelay)`
        var backoffDelay: TimeInterval { min(pow(2.0, Double(retryCount)), 60.0) }
    }
}
