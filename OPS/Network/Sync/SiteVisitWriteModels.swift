import Foundation
import SwiftData

extension SiteVisitType {
    var writeState: SiteVisitWriteState {
        get { siteVisitWriteStateData.flatMap { try? JSONDecoder().decode(SiteVisitWriteState.self, from: $0) } ?? .init() }
        set { siteVisitWriteStateData = try? JSONEncoder().encode(newValue) }
    }
    func beginVersionedEdit() { var s = writeState; s.begin(SiteVisitWriteModels.values(self)); writeState = s }
}
extension SiteVisitChecklistAnswer {
    var writeState: SiteVisitWriteState {
        get { siteVisitWriteStateData.flatMap { try? JSONDecoder().decode(SiteVisitWriteState.self, from: $0) } ?? .init() }
        set { siteVisitWriteStateData = try? JSONEncoder().encode(newValue) }
    }
    func beginVersionedEdit() { var s = writeState; s.begin(SiteVisitWriteModels.values(self)); writeState = s }
}

enum SiteVisitWriteModels {
    private static func text(_ v: String?) -> SiteVisitWriteJSON { v.map(SiteVisitWriteJSON.string) ?? .null }
    private static func date(_ v: Date?) -> SiteVisitWriteJSON { text(v.map(SupabaseDate.format)) }
    static func values(_ type: SiteVisitType) -> SiteVisitWriteJSON {
        .object([
            "id": .string(type.id.lowercased()), "company_id": .string(type.companyId.lowercased()),
            "slug": .string(type.slug), "name": .string(type.name), "description_text": text(type.descriptionText),
            "is_system_template": .bool(type.isSystemTemplate), "is_default": .bool(type.isDefault),
            "sort_order": .number(Double(type.sortOrder)), "deleted_at": date(type.deletedAt),
            "fields": .array(type.fields.map { f in
                var field: [String: SiteVisitWriteJSON] = [
                    "id": .string(f.id), "label": .string(f.label), "kind": .string(f.kind.rawValue),
                    "required": .bool(f.required), "helpText": text(f.helpText),
                    "sortOrder": .number(Double(f.sortOrder)), "isVisible": .bool(f.isShown)
                ]
                if let choice = f.singleChoice { field["singleChoice"] = choiceJSON(choice) }
                return .object(field)
            })
        ])
    }
    static func values(_ answer: SiteVisitChecklistAnswer) -> SiteVisitWriteJSON {
        let value = answer.answerValue
        var wire: [String: SiteVisitWriteJSON] = [:]
        if !value.artifactIds.isEmpty { wire["artifactIds"] = .array(value.artifactIds.map { .string($0.lowercased()) }) }
        if let v = value.text, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { wire["text"] = .string(v) }
        if let v = value.boolValue { wire["boolValue"] = .bool(v) }
        if let v = value.choice, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { wire["choice"] = .string(v) }
        if let v = value.deckDesignId { wire["deckDesignId"] = .string(v.lowercased()) }
        var row: [String: SiteVisitWriteJSON] = [
            "id": .string(answer.id.lowercased()), "company_id": .string(answer.companyId.lowercased()),
            "site_visit_id": .string(answer.siteVisitId.lowercased()), "site_visit_type_id": text(answer.siteVisitTypeId),
            "field_id": .string(answer.fieldId), "label": .string(answer.label), "kind": .string(answer.kind.rawValue),
            "required": .bool(answer.required), "help_text": text(answer.helpText),
            "sort_order": .number(Double(answer.sortOrder)), "answer_value": .object(wire), "deleted_at": date(answer.deletedAt)
        ]
        if let snapshot = value.choiceSnapshot { row["choice_snapshot"] = choiceJSON(snapshot) }
        return .object(row)
    }

    private static func choiceJSON(_ choice: SiteVisitSingleChoice) -> SiteVisitWriteJSON {
        .object(["version": .number(Double(choice.version)), "options": .array(choice.options.map {
            .object(["id": .string($0.id), "label": .string($0.label)])
        })])
    }

    private static func requiresChoiceProtocol(_ values: SiteVisitWriteJSON, state: SiteVisitWriteState) -> Bool {
        values.containsChoiceMetadata || state.baseRow?.containsChoiceMetadata == true || state.remoteRow?.containsChoiceMetadata == true
    }
    static func command(_ answer: SiteVisitChecklistAnswer, forceChoiceProtocol: Bool = false) -> SiteVisitWriteCommand {
        answer.beginVersionedEdit()
        let state = answer.writeState
        return .init(protocol: forceChoiceProtocol || requiresChoiceProtocol(values(answer), state: state) ? SiteVisitWriteCommand.choiceRevision : SiteVisitWriteCommand.revision,
                     companyId: answer.companyId.lowercased(), entity: "answer", rows: [
            .init(id: answer.id.lowercased(), baseRevision: state.baseRevision ?? state.revision,
                  before: state.baseRow ?? values(answer), values: values(answer),
                  clearAnswer: state.explicitlyEdited == true && !answer.answerValue.hasContent ? true : nil)
        ])
    }
    static func command(_ types: [SiteVisitType]) throws -> SiteVisitWriteCommand {
        guard let first = types.first, types.allSatisfy({ $0.companyId.lowercased() == first.companyId.lowercased() }) else {
            throw SiteVisitWriteError.legacyPayload
        }
        var command = SiteVisitWriteCommand(companyId: first.companyId.lowercased(), entity: "template", rows: types.map { type in
            type.beginVersionedEdit()
            let state = type.writeState
            return .init(id: type.id.lowercased(), baseRevision: state.baseRevision ?? state.revision,
                         before: state.baseRow ?? values(type), values: values(type))
        })
        if types.contains(where: { requiresChoiceProtocol(values($0), state: $0.writeState) }) {
            command.protocol = SiteVisitWriteCommand.choiceRevision
        }
        return command
    }

    static func currentTemplateHasChoice(for answer: SiteVisitChecklistAnswer, context: ModelContext) throws -> Bool {
        guard let templateId = answer.siteVisitTypeId,
              let type = try SiteVisitTypeServerMerge.fetch(id: templateId, context: context),
              type.companyId.lowercased() == answer.companyId.lowercased() else { return false }
        return type.fields.contains { $0.id == answer.fieldId && $0.singleChoice != nil }
    }

    /// Routing for an explicit review may use current metadata; the original
    /// queued request remains unchanged for idempotency and custody.
    static func needsChoiceReview(_ command: SiteVisitWriteCommand, context: ModelContext) throws -> Bool {
        if command.protocol == SiteVisitWriteCommand.choiceRevision { return true }
        for row in command.rows {
            if row.before.containsChoiceMetadata || row.values.containsChoiceMetadata { return true }
            if command.entity == "template" {
                if let type = try SiteVisitTypeServerMerge.fetch(id: row.id, context: context),
                   type.companyId.lowercased() == command.companyId,
                   requiresChoiceProtocol(values(type), state: type.writeState) { return true }
            } else {
                let id = row.id
                if let answer = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(predicate: #Predicate { $0.id == id })).first,
                   answer.companyId.lowercased() == command.companyId,
                   requiresChoiceProtocol(values(answer), state: answer.writeState) { return true }
                if let templateId = row.values["site_visit_type_id"]?.string,
                   let type = try SiteVisitTypeServerMerge.fetch(id: templateId, context: context),
                   type.companyId.lowercased() == command.companyId,
                   type.fields.contains(where: { $0.id == row.values["field_id"]?.string && $0.singleChoice != nil }) { return true }
            }
        }
        return false
    }
}
