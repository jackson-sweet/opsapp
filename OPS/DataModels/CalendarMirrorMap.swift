//
//  CalendarMirrorMap.swift
//  OPS
//
//  Side-table mapping OPS event IDs to EKEvent identifiers for the
//  iPhone Calendar Mirror feature. Client-local only — never synced to
//  Supabase. Cleared on logout, company switch, or feature disable.
//

import Foundation
import SwiftData

enum MirrorSource: String, Codable {
    case calendarUserEvent
    case projectTask
    // siteVisit reserved for future addition once iOS SiteVisit sync ships
}

@Model
final class CalendarMirrorMap {
    @Attribute(.unique) var opsId: String
    var ekEventIdentifier: String
    var sourceType: String       // MirrorSource.rawValue
    var contentHash: String      // SHA256 of canonical "title|start|end|notes|allDay"
    var lastMirroredAt: Date

    init(opsId: String, ekEventIdentifier: String, sourceType: MirrorSource, contentHash: String) {
        self.opsId = opsId
        self.ekEventIdentifier = ekEventIdentifier
        self.sourceType = sourceType.rawValue
        self.contentHash = contentHash
        self.lastMirroredAt = Date()
    }

    var source: MirrorSource? { MirrorSource(rawValue: sourceType) }
}
