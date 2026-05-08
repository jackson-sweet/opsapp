//
//  StageTransition.swift
//  OPS
//
//  Immutable stage history record — Supabase-backed.
//  Schema parity with public.stage_transitions.
//

import SwiftData
import Foundation

@Model
class StageTransition: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var opportunityId: String
    var fromStage: PipelineStage?    // nullable — first transition from "no prior stage"
    var toStage: PipelineStage
    var transitionedAt: Date
    var transitionedBy: String?      // user UUID
    var durationInStage: TimeInterval?  // decoded from Postgres `interval` type
    var createdAt: Date              // local cache timestamp (not in DB)

    init(
        id: String = UUID().uuidString,
        companyId: String,
        opportunityId: String,
        fromStage: PipelineStage?,
        toStage: PipelineStage,
        transitionedAt: Date = Date(),
        transitionedBy: String? = nil,
        durationInStage: TimeInterval? = nil
    ) {
        self.id = id
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.fromStage = fromStage
        self.toStage = toStage
        self.transitionedAt = transitionedAt
        self.transitionedBy = transitionedBy
        self.durationInStage = durationInStage
        self.createdAt = Date()
    }
}
