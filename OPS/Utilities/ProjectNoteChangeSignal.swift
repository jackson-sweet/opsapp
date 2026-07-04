//
//  ProjectNoteChangeSignal.swift
//  OPS
//
//  Bug 4353812f — a photo comment posted in the full-screen viewer did not
//  appear in the Activity feed until the project was closed and reopened.
//  `.projectNoteReceived` was only ever posted by RealtimeProcessor (inbound
//  from OTHER devices), so the feed's ProjectNotesViewModel never learned
//  about the local write made by PhotoCommentsViewModel (and vice versa).
//
//  Every local project-note mutation (post / edit / delete, optimistic and
//  confirmed) now fires this signal. Both ViewModels already observe
//  `.projectNoteReceived` and reload from SwiftData — an idempotent, cheap
//  refresh — so the feed and any open photo-comment thread stay live.
//

import Foundation

enum ProjectNoteChangeSignal {
    /// Post on the main queue so observers (both @MainActor ViewModels)
    /// reload immediately after the local SwiftData write.
    static func post(projectId: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .projectNoteReceived,
                object: nil,
                userInfo: ["projectId": projectId]
            )
        }
    }
}
