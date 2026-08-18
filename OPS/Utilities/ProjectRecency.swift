//
//  ProjectRecency.swift
//  OPS
//
//  One definition of "most recently touched" for a project, and the order
//  every project choice list uses.
//

import Foundation

enum ProjectRecency {
    /// "Most recently touched" stamp. Prefers the server-maintained
    /// `updatedAt`, which Supabase bumps on every write; falls back to
    /// `createdAt` for legacy rows synced before that column was plumbed
    /// (bug 70a4d9fd). Never `lastSyncedAt` — that records when this device
    /// last talked to the server, not when the work changed.
    static func stamp(for project: Project) -> Date {
        max(project.updatedAt ?? .distantPast, project.createdAt ?? .distantPast)
    }

    /// The order for any list of projects offered as a choice: the job touched
    /// most recently leads. Whatever you were just working on is nearly always
    /// what you are filing the next task, expense, or photo against, and an
    /// alphabetical list buried it below whichever job starts with an "A".
    /// Ties fall back to the title so the order is never arbitrary.
    /// Bug b79abf79.
    static func pickerOrdered(_ projects: [Project]) -> [Project] {
        projects.sorted { left, right in
            let leftStamp = stamp(for: left)
            let rightStamp = stamp(for: right)
            if leftStamp != rightStamp { return leftStamp > rightStamp }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }
}
