import SwiftUI
import SwiftData

/// Lives inside Pending Work. Choosing a version persists a resolution command
/// before transmission; Export and the original command retain the audit copy.
struct SiteVisitConflictReview: View {
    let operation: SyncOperation
    private let loadCurrent: (SiteVisitWriteCommand, String) async throws -> [SiteVisitWriteJSON]

    init(operation: SyncOperation,
         loadCurrent: @escaping (SiteVisitWriteCommand, String) async throws -> [SiteVisitWriteJSON] = { try await SiteVisitVersionedSync.review($0, expectedActorId: $1) }) {
        self.operation = operation
        self.loadCurrent = loadCurrent
    }
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var current: [SiteVisitWriteJSON]?
    @State private var busy = false
    @State private var message: String?
    @State private var finished = false

    private var command: SiteVisitWriteCommand? { SiteVisitVersionedSync.command(operation) }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text("REVIEW SAVED FORM").font(OPSStyle.Typography.section)
            if finished {
                Text("Your choice is saved. Both versions remain in the recovery record.")
                    .font(OPSStyle.Typography.body)
            } else if let command {
                if !isCurrent(command) {
                    Text("This saved form belongs to another session. Sign in with its original account, or export it for support review.")
                        .font(OPSStyle.Typography.body)
                }
                Text("Compare the saved version with your pending changes.")
                    .font(OPSStyle.Typography.body)
                ForEach(command.rows, id: \.id) { row in
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text(row.values["label"]?.string ?? row.values["name"]?.string ?? "Checklist")
                            .font(OPSStyle.Typography.bodyBold)
                            .fixedSize(horizontal: false, vertical: true)
                        comparison("PENDING", row.values)
                        let remote = current?.first { $0["id"]?.string == row.id } ?? current?.first {
                            (command.entity == "answer" && $0["site_visit_id"] == row.values["site_visit_id"] && $0["field_id"] == row.values["field_id"]) || (command.entity == "template" && $0["slug"] == row.values["slug"])
                        }
                        comparison("CURRENT", remote)
                        DisclosureGroup { comparison("ORIGINAL", row.before) } label: {
                            Text("Original version").fixedSize(horizontal: false, vertical: true)
                        }
                            .font(OPSStyle.Typography.metadata)
                        if let remote, remote["id"]?.string != row.id {
                            Text(command.entity == "answer" ? "Another device added this field. Using pending keeps its saved field definition and applies your answer." : "Another device added this template. Using pending applies your reviewed changes to the saved template.")
                                .font(OPSStyle.Typography.body)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .glassSurface()
                }
                if command.entity == "template", command.rows.contains(where: { $0.values["is_default"] == .bool(true) }), let current {
                    ForEach(Array(current.filter { row in
                        row["is_default"] == .bool(true) && !command.rows.contains(where: { $0.id == row["id"]?.string })
                    }.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("Using pending also replaces this current default.").font(OPSStyle.Typography.body)
                            comparison("CURRENT DEFAULT", row)
                        }
                    }
                }
                if let message {
                    Text(message).font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.rose)
                }
                if operation.siteVisitWriteResolutionData != nil {
                    Button("RETRY SAVED CHOICE") { Task { await sendChoice() } }
                        .opsPrimaryButtonStyle().disabled(busy || !isCurrent(command))
                } else if current != nil {
                    Button("USE PENDING") { Task { await choose("pending") } }
                        .opsPrimaryButtonStyle().disabled(busy || !isCurrent(command))
                    Button("USE CURRENT") { Task { await choose("current") } }
                        .opsSecondaryButtonStyle().disabled(busy || !isCurrent(command))
                }
                Button(current == nil ? "LOAD CURRENT VERSION" : "REFRESH CURRENT VERSION") {
                    Task { await refresh() }
                }.opsSecondaryButtonStyle().disabled(busy || operation.siteVisitWriteResolutionData != nil)
                if busy { ProgressView().tint(OPSStyle.Colors.text) }
            } else {
                Text("This older form needs support review. Export the saved work before updating OPS.")
                    .font(OPSStyle.Typography.body)
            }
        }
        .foregroundColor(OPSStyle.Colors.text)
        .task { await refresh() }
    }

    private func comparison(_ title: String, _ row: SiteVisitWriteJSON?) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(title).font(OPSStyle.Typography.metadata).foregroundColor(OPSStyle.Colors.text2)
            Text(row.map(Self.summary) ?? (current == nil ? "Load the current version to compare." : "No saved row."))
                .font(OPSStyle.Typography.body).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func summary(_ row: SiteVisitWriteJSON) -> String {
        if let value = row["answer_value"] {
            var lines = [describe(value)]
            for (key, label) in [("label", "Field"), ("kind", "Type"), ("required", "Required"), ("help_text", "Guidance"), ("sort_order", "Order")] {
                if let value = row[key], value != .null { lines.append("\(label): \(describe(value, field: key))") }
            }
            let content = lines.joined(separator: "\n")
            return row["deleted_at"]?.string != nil ? "Removed field\n\(content)" : content
        }
        guard case .object(let values) = row else { return describe(row) }
        let labels = ["name": "Name", "slug": "Reference", "description_text": "Description",
            "is_default": "Default", "fields": "Fields", "deleted_at": "Removed", "sort_order": "Order"]
        return labels.keys.sorted().compactMap { key in
            guard let value = values[key], value != .null else { return nil }
            return "\(labels[key]!): \(describe(value))"
        }.joined(separator: "\n")
    }
    private static func describe(_ value: SiteVisitWriteJSON, field: String) -> String {
        if field == "kind", let raw = value.string, let kind = SiteVisitFieldKind(rawValue: raw) { return kind.displayName }
        return describe(value)
    }
    private static func describe(_ value: SiteVisitWriteJSON) -> String {
        switch value {
        case .null: return "—"
        case .string(let text): return text.isEmpty ? "—" : text
        case .bool(let value): return value ? "Yes" : "No"
        case .number(let value): return value.formatted()
        case .array(let values): return values.isEmpty ? "—" : values.map(describe).joined(separator: "\n")
        case .object(let values):
            let labels = ["text":"Answer", "boolValue":"Checked", "choice":"Answer", "artifactIds":"Evidence",
                "deckDesignId":"Deck", "label":"Field", "kind":"Type", "required":"Required", "helpText":"Guidance", "isVisible":"Shown", "sortOrder":"Order"]
            let lines = values.keys.sorted().compactMap { key -> String? in
                guard let label = labels[key], let value = values[key], value != .null, value != .array([]) else { return nil }
                return "\(label): \(describe(value, field: key))"
            }
            return lines.isEmpty ? "—" : lines.joined(separator: "\n")
        }
    }
    private func isCurrent(_ command: SiteVisitWriteCommand) -> Bool {
        dataController.currentUser?.companyId?.lowercased() == command.companyId &&
        SiteVisitAuthorHeal.sessionUserId()?.lowercased() == operation.siteVisitWriteActorId
    }
    @MainActor private func refresh() async {
        guard let command, isCurrent(command), !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard let actor = operation.siteVisitWriteActorId else { throw SiteVisitWriteError.legacyPayload }
            let rows = try await loadCurrent(command, actor)
            guard isCurrent(command) else { return }
            current = rows; message = nil
        } catch { message = recoveryMessage(error) }
    }
    @MainActor private func choose(_ choice: String) async {
        guard let current, let command, isCurrent(command), !busy, operation.siteVisitWriteResolutionData == nil else { return }
        do {
            operation.siteVisitWriteResolutionData = try JSONEncoder().encode(SiteVisitWriteResolution(id: UUID(), choice: choice, current: current))
            operation.status = "pending"; operation.lastError = nil
            try modelContext.save()
            await sendChoice()
        } catch { message = recoveryMessage(error) }
    }
    @MainActor private func sendChoice() async {
        guard let command, isCurrent(command), !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await SiteVisitVersionedSync.execute(operation: operation, context: modelContext,
                companyId: command.companyId, actorId: SiteVisitAuthorHeal.sessionUserId(), isCurrent: { isCurrent(command) })
            operation.status = "completed"; operation.completedAt = Date(); operation.lastError = nil
            try modelContext.save(); finished = true
            await dataController.syncEngine.triggerSync()
        } catch {
            guard isCurrent(command) else { return }
            if case SiteVisitWriteError.conflict = error {
                // The server returned a definitive non-applied review conflict.
                // Archive the reviewed choice before allowing another review.
                current = nil
            }
            operation.status = "parked"; operation.lastError = error.localizedDescription
            try? modelContext.save(); message = recoveryMessage(error)
        }
    }
    private func recoveryMessage(_ error: Error) -> String {
        let receipt = operation.siteVisitWriteReceiptData.flatMap { try? JSONDecoder().decode(SiteVisitWriteReceipt.self, from: $0) }
        if receipt?.reason == "capture_closed" { return "This visit is closed. Use the current version or export your pending work." }
        if receipt?.reason == "snapshot_changed" { return "The saved field definition differs. Use the current version and export your pending answer for review." }
        let detail = String(describing: error)
        if detail.contains("42501") || detail.contains("AUTHORITY") { return "Access changed. Ask a company admin to restore access, then load the current version." }
        if detail.contains("CLOSED") || detail.contains("capture_closed") { return "This visit is closed. Use the current version or export your pending work." }
        if detail.contains("INVALID") || detail.contains("legacyPayload") { return "This form needs support review. Export the saved work." }
        return "The choice is not confirmed. Both versions are saved. Retry or refresh the current version."
    }
}
