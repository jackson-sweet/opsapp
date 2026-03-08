//
//  SignatureCapture.swift
//  OPS
//
//  Captured signature with location metadata — supports offline-first sync
//

import SwiftData
import Foundation

@Model
class SignatureCapture: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var projectId: String?
    var taskId: String?
    var signerName: String
    var signatureData: Data?
    var signatureImagePath: String?
    var uploadedURL: String?
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    var deletedAt: Date?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = true

    init(
        id: String = UUID().uuidString,
        companyId: String,
        projectId: String? = nil,
        taskId: String? = nil,
        signerName: String,
        signatureData: Data? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.projectId = projectId
        self.taskId = taskId
        self.signerName = signerName
        self.signatureData = signatureData
        self.capturedAt = capturedAt
    }
}
