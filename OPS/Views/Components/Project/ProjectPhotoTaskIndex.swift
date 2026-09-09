//
//  ProjectPhotoTaskIndex.swift
//  OPS
//
//  Bug a290934f — which task does this photo document?
//
//  Every surface that shows the answer (the gallery tile's colour bar, the
//  task's own photo strip, the pinned task-note strip, the viewer's TASK
//  action) asks it the same way, through this one pure index. Built once per
//  render from the rows a view already holds — no fetch, no model reads while
//  a feed scrolls, and no chance of two surfaces disagreeing about the same
//  photo.
//
//  Resolution is deliberately narrow: a link only counts when the task it
//  names is a LIVE task on THIS project. A photo carrying a deleted task, or a
//  task that belongs to some other job, reads as unlinked rather than as a
//  badge nobody can act on — the same rule the server's write guard enforces.
//

import SwiftUI

/// One task, flattened out of SwiftData so the views below never re-read the
/// model while a feed scrolls.
struct ProjectPhotoTask: Equatable, Identifiable {
    let id: String
    let title: String
    let color: Color
    let status: TaskStatus

    var isTerminal: Bool { status.isTerminal }

    /// Only terminal work earns a status chip — an active task's chip would say
    /// nothing the crew does not already assume.
    var statusChip: String? {
        switch status {
        case .active:    return nil
        case .completed: return "COMPLETE"
        case .cancelled: return "CANCELLED"
        }
    }
}

struct ProjectPhotoTaskIndex: Equatable {
    /// Live tasks on this project, in the order the project presents them.
    let tasks: [ProjectPhotoTask]

    /// Photo url → the task it documents.
    private let taskByURL: [String: ProjectPhotoTask]

    /// Task id → that task's photo urls, newest first.
    private let urlsByTaskID: [String: [String]]

    /// Photo url → its server-generated small rendition, when one exists.
    private let thumbnailByURL: [String: String]

    static let empty = ProjectPhotoTaskIndex(photos: [], tasks: [])

    /// - Parameters:
    ///   - photos: the project's synced `project_photos` rows. Soft-deleted
    ///     rows are ignored here so no caller has to remember to filter them.
    ///   - tasks: the project's tasks. Deleted and cancelled tasks are dropped:
    ///     a cancelled task has no standing claim on evidence, exactly as it has
    ///     no standing instruction (`PinnedTaskNotesBuilder`).
    init(photos: [ProjectPhoto], tasks: [ProjectTask]) {
        let live = tasks
            .filter { $0.deletedAt == nil && $0.status != .cancelled }
            .sorted { $0.displayOrder < $1.displayOrder }
            .map {
                ProjectPhotoTask(
                    id: $0.id.lowercased(),
                    title: $0.displayTitle,
                    color: Color(hex: $0.effectiveColor) ?? OPSStyle.Colors.primaryAccent,
                    status: $0.status
                )
            }
        self.tasks = live

        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Newest first, matching the gallery's own order (bug e7ef2c88): the
        // photo someone just took is the one they are looking for.
        let ordered = photos
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }

        var taskByURL: [String: ProjectPhotoTask] = [:]
        var urlsByTaskID: [String: [String]] = [:]
        var thumbnailByURL: [String: String] = [:]
        for photo in ordered {
            if let thumbnail = photo.thumbnailURL, !thumbnail.isEmpty, thumbnailByURL[photo.url] == nil {
                thumbnailByURL[photo.url] = thumbnail
            }
            guard let taskID = ProjectPhotoTaskLink.canonical(photo.taskId),
                  let task = byID[taskID] else { continue }
            // One url can carry more than one row. The first (newest) wins, so
            // the tile and the strip agree.
            if taskByURL[photo.url] == nil {
                taskByURL[photo.url] = task
            }
            if urlsByTaskID[taskID]?.contains(photo.url) != true {
                urlsByTaskID[taskID, default: []].append(photo.url)
            }
        }
        self.taskByURL = taskByURL
        self.urlsByTaskID = urlsByTaskID
        self.thumbnailByURL = thumbnailByURL
    }

    /// The task this photo documents, or nil.
    func task(forURL url: String) -> ProjectPhotoTask? { taskByURL[url] }

    /// This task's photos, newest first.
    func urls(forTaskID taskID: String) -> [String] {
        guard let id = ProjectPhotoTaskLink.canonical(taskID) else { return [] }
        return urlsByTaskID[id] ?? []
    }

    /// Server-generated small renditions, keyed by full photo url.
    var thumbnails: [String: String] { thumbnailByURL }

    /// Whether any photo on this project documents a task. Drives nothing on
    /// its own — it exists so a surface can stay completely silent on a project
    /// where nobody has tagged anything yet.
    var hasAnyTaggedPhoto: Bool { !taskByURL.isEmpty }
}
