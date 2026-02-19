//
//  Estimate.swift
//  OPS
//
//  Quote document — Supabase-backed
//

import SwiftData
import Foundation

@Model
class Estimate {
    @Attribute(.unique) var id: String
    var companyId: String
    var estimateNumber: String
    var status: EstimateStatus
    var clientId: String?
    var projectId: String?
    var opportunityId: String?
    var title: String?
    var clientMessage: String?
    var internalNotes: String?
    var taxRate: Double
    var discountPercent: Double
    var subtotal: Double
    var taxAmount: Double
    var total: Double
    var validUntil: Date?
    var sentAt: Date?
    var version: Int
    var parentId: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        companyId: String,
        estimateNumber: String = "",
        status: EstimateStatus = .draft,
        taxRate: Double = 0,
        discountPercent: Double = 0,
        version: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.estimateNumber = estimateNumber
        self.status = status
        self.taxRate = taxRate
        self.discountPercent = discountPercent
        self.subtotal = 0
        self.taxAmount = 0
        self.total = 0
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
