import Foundation

struct ProjectPhotoFormFields: Codable, Equatable, Sendable {
    var title: String
    var titleIsAuto: Bool
    var clientID: String?
    var address: String
    var description: String
    var notes: String
    var status: String
    var startDate: Date?
    var endDate: Date?
}

struct ProjectPhotoFormDraft: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let projectID: String
    let companyID: String
    let userID: String
    var fields: ProjectPhotoFormFields
    var batchIDs: [String]
    var updatedAt: Date
    var owner: StagedCaptureOwner {
        StagedCaptureOwner(companyID: companyID, userID: userID, contextID: "project-draft:\(projectID.lowercased())")
    }
}

/// A form-owned destination receipt exists before the camera releases its batch.
/// Its reserved project identity never changes at create or recovery time.
actor ProjectPhotoFormDraftStore {
    static let shared = ProjectPhotoFormDraftStore()
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ProjectPhotoDrafts", isDirectory: true)
    }
    func save(_ draft: ProjectPhotoFormDraft) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = try file(draft.id)
        guard !FileManager.default.fileExists(atPath: url.appendingPathExtension("closed").path) else { throw CaptureStagingError.closedDraft }
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try JSONDecoder().decode(ProjectPhotoFormDraft.self, from: Data(contentsOf: url))
            guard previous.projectID == draft.projectID, previous.companyID == draft.companyID, previous.userID == draft.userID else { throw CaptureStagingError.invalidIdentity }
            if previous.updatedAt > draft.updatedAt { return }
        }
        try JSONEncoder().encode(draft).write(to: url, options: .atomic)
    }
    func pending(companyID: String, userID: String) throws -> [ProjectPhotoFormDraft] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var drafts: [ProjectPhotoFormDraft] = []
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            guard !FileManager.default.fileExists(atPath: url.appendingPathExtension("closed").path) else { continue }
            let draft = try JSONDecoder().decode(ProjectPhotoFormDraft.self, from: Data(contentsOf: url))
            if draft.companyID == companyID.lowercased() && draft.userID == userID.lowercased() { drafts.append(draft) }
        }
        return drafts.sorted { $0.updatedAt > $1.updatedAt }
    }
    func remove(_ draft: ProjectPhotoFormDraft) throws {
        let url = try file(draft.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let current = try JSONDecoder().decode(ProjectPhotoFormDraft.self, from: Data(contentsOf: url))
        guard current.projectID == draft.projectID, current.companyID == draft.companyID, current.userID == draft.userID else { throw CaptureStagingError.invalidIdentity }
        // Persist completion first. An already queued form-field save cannot
        // recreate this draft, including after interruption before removal.
        try JSONEncoder().encode(current).write(to: url.appendingPathExtension("closed"), options: .atomic)
        try FileManager.default.removeItem(at: url)
    }
    private func file(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw CaptureStagingError.invalidIdentity }
        return root.appendingPathComponent(id).appendingPathExtension("json")
    }
}
