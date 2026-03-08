//
//  LocalPhoto.swift
//  OPS
//
//  Locally-stored photo with upload tracking — supports offline-first sync
//

import SwiftData
import Foundation

@Model
class LocalPhoto: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var entityType: String
    var entityId: String
    var localPath: String
    var thumbnailPath: String?
    var uploadedURL: String?
    var fileSize: Int64
    var mimeType: String
    var width: Int
    var height: Int
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    var uploadProgress: Double
    var uploadResumeData: Data?
    var status: String
    var createdAt: Date
    var deletedAt: Date?

    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = true

    init(
        id: String = UUID().uuidString,
        companyId: String,
        entityType: String,
        entityId: String,
        localPath: String,
        fileSize: Int64,
        mimeType: String = "image/jpeg",
        width: Int = 0,
        height: Int = 0,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.entityType = entityType
        self.entityId = entityId
        self.localPath = localPath
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
        self.uploadProgress = 0
        self.status = "local"
        self.createdAt = capturedAt
    }
}
