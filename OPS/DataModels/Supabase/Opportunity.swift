//
//  Opportunity.swift
//  OPS
//
//  Pipeline deal — Supabase-backed.
//  Schema parity with public.opportunities (47 cols). Phase 1 defers AI/location/images.
//

import SwiftData
import Foundation

@Model
class Opportunity: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String

    // Deal identity
    var title: String?
    var contactName: String
    var contactEmail: String?
    var contactPhone: String?
    var descriptionText: String?
    var address: String?

    // Pipeline tracking
    var stage: PipelineStage
    var stageEnteredAt: Date
    var stageManuallySet: Bool
    var assignedTo: String?
    var priority: String?
    var source: String?
    var quoteDeliveryMethod: QuoteDeliveryMethod?

    // Financial
    var estimatedValue: Double?
    var actualValue: Double?
    var winProbabilityOverride: Int?       // optional server override; falls back to stage default

    // Dates
    var expectedCloseDate: Date?
    var actualCloseDate: Date?
    var nextFollowUpAt: Date?
    var lastActivityAt: Date?

    // Conversion / linking
    var projectId: String?
    var clientId: String?
    var lostReason: String?
    var lostNotes: String?

    // Soft-delete + archive
    var deletedAt: Date?
    var archivedAt: Date?

    // Tags + email source
    var tags: [String]
    var sourceEmailId: String?

    // Message-thread denormalized counters (populated by web; iOS reads but doesn't write)
    var correspondenceCount: Int
    var outboundCount: Int
    var inboundCount: Int
    var lastInboundAt: Date?
    var lastOutboundAt: Date?
    var lastMessageDirection: String?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed

    var weightedValue: Double {
        let pct = winProbabilityOverride ?? stage.winProbability
        return (estimatedValue ?? 0) * Double(pct) / 100.0
    }

    var daysInStage: Int {
        Calendar.current.dateComponents([.day], from: stageEnteredAt, to: Date()).day ?? 0
    }

    var isStale: Bool {
        daysInStage > stage.staleThresholdDays
    }

    var isDeleted: Bool { deletedAt != nil }
    var isArchived: Bool { archivedAt != nil }

    // MARK: - Init

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
