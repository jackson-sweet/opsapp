//
//  OPSSchemaLegacyOpportunityV15.swift
//  OPS
//
//  Frozen Opportunity shape as shipped through schema V15. Runtime code uses
//  the live top-level Opportunity model; this type exists only to keep every
//  historical SwiftData fingerprint stable when V16 adds assignmentVersion.
//

import Foundation
import SwiftData

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
