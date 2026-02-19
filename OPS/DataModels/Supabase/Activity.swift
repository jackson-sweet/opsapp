//
//  Activity.swift
//  OPS
//
//  Timeline event per opportunity — Supabase-backed
//

import SwiftData
import Foundation

@Model
class Activity: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: ActivityType
    var body: String?
    var createdBy: String?
    var createdAt: Date
    var metadata: String?

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
        self.createdAt = createdAt
    }
}
