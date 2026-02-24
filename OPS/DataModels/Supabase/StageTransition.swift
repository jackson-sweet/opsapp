//
//  StageTransition.swift
//  OPS
//
//  Immutable stage history record — Supabase-backed
//

import SwiftData
import Foundation

@Model
class StageTransition: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var fromStage: PipelineStage
    var toStage: PipelineStage
    var changedBy: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        opportunityId: String,
        fromStage: PipelineStage,
        toStage: PipelineStage,
        changedBy: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.opportunityId = opportunityId
        self.fromStage = fromStage
        self.toStage = toStage
        self.changedBy = changedBy
        self.createdAt = createdAt
    }
}
