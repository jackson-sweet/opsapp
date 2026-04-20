//
//  ProjectAccessHelper.swift
//  OPS
//
//  Centralized visibility logic for Project records. Distinguishes "narrow"
//  surfaces (team-assigned only) from "wide" surfaces (team OR mention-granted).
//  Bug G9 — tag-based project view permission.
//
//  Surface-to-predicate mapping (locked, 2026-04-20):
//    NARROW (team-only):  Job Board, Calendar, Schedule, Map, Home.
//    WIDE (team+mention): Universal Search, iOS Spotlight, push deep link.
//

import Foundation

@MainActor
enum ProjectAccessHelper {
    /// Narrow surfaces — mention-granted projects are NOT visible here.
    /// Use for: JobBoardView, CalendarView/ViewModel, ScheduleView, MapView,
    /// HomeView/HomeContentView, Calendar Tab ProjectSearchSheet.
    static func narrowVisible(_ project: Project, userId: String) -> Bool {
        project.getTeamMemberIds().contains(userId)
    }

    /// Wide surfaces — mention-granted projects ARE visible here.
    /// Use for: UniversalSearchSheet.availableProjects, SpotlightIndexManager
    /// passesProjectScopeFilter / passesTaskScopeFilter.
    static func wideVisible(_ project: Project, userId: String) -> Bool {
        if project.getTeamMemberIds().contains(userId) { return true }
        return MentionAccessIndex.shared.contains(project.id)
    }

    /// True if the user only has mention-based access to this project
    /// (not on team, no full "all" scope). Drives the read-only UI lock in
    /// ProjectDetailsView / FloatingActionMenu.
    ///
    /// Full-scope users (Admin/Owner/Office with "all") are never mention-only —
    /// they can edit any project regardless of how they arrived at it.
    static func isMentionOnly(_ project: Project, userId: String) -> Bool {
        if PermissionStore.shared.hasFullAccess("projects.view") { return false }
        if project.getTeamMemberIds().contains(userId) { return false }
        return MentionAccessIndex.shared.contains(project.id)
    }
}
