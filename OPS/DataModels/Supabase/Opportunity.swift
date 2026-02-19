//
//  Opportunity.swift
//  OPS
//
//  Pipeline deal — Supabase-backed
//

import SwiftData
import Foundation

@Model
class Opportunity: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var contactName: String
    var contactEmail: String?
    var contactPhone: String?
    var jobDescription: String?
    var estimatedValue: Double?
    var stage: PipelineStage
    var source: String?
    var projectId: String?
    var clientId: String?
    var lossReason: String?
    var createdAt: Date
    var updatedAt: Date
    var lastActivityAt: Date?

    var weightedValue: Double {
        (estimatedValue ?? 0) * Double(stage.winProbability) / 100.0
    }

    var daysInStage: Int {
        let ref = lastActivityAt ?? createdAt
        return Calendar.current.dateComponents([.day], from: ref, to: Date()).day ?? 0
    }

    var isStale: Bool {
        daysInStage > stage.staleThresholdDays
    }

    init(
        id: String = UUID().uuidString,
        companyId: String,
        contactName: String,
        stage: PipelineStage = .newLead,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.contactName = contactName
        self.stage = stage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
