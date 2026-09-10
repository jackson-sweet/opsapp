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
            "fields": .array(type.fields.map { f in .object([
                "id": .string(f.id), "label": .string(f.label), "kind": .string(f.kind.rawValue),
                "required": .bool(f.required), "helpText": text(f.helpText),
                "sortOrder": .number(Double(f.sortOrder)), "isVisible": .bool(f.isShown)
            ]) })
        ])
    }
    static func values(_ answer: SiteVisitChecklistAnswer) -> SiteVisitWriteJSON {
        let value = answer.answerValue
        var wire: [String: SiteVisitWriteJSON] = [:]
        if !value.artifactIds.isEmpty { wire["artifactIds"] = .array(value.artifactIds.map { .string($0.lowercased()) }) }
        if let v = value.text { wire["text"] = .string(v) }
        if let v = value.boolValue { wire["boolValue"] = .bool(v) }
        if let v = value.choice { wire["choice"] = .string(v) }
        if let v = value.deckDesignId { wire["deckDesignId"] = .string(v.lowercased()) }
        return .object([
            "id": .string(answer.id.lowercased()), "company_id": .string(answer.companyId.lowercased()),
            "site_visit_id": .string(answer.siteVisitId.lowercased()), "site_visit_type_id": text(answer.siteVisitTypeId),
            "field_id": .string(answer.fieldId), "label": .string(answer.label), "kind": .string(answer.kind.rawValue),
            "required": .bool(answer.required), "help_text": text(answer.helpText),
            "sort_order": .number(Double(answer.sortOrder)), "answer_value": .object(wire), "deleted_at": date(answer.deletedAt)
        ])
    }
    static func command(_ answer: SiteVisitChecklistAnswer) -> SiteVisitWriteCommand {
        answer.beginVersionedEdit()
        let state = answer.writeState
        return .init(companyId: answer.companyId.lowercased(), entity: "answer", rows: [
            .init(id: answer.id.lowercased(), baseRevision: state.baseRevision ?? state.revision,
                  before: state.baseRow ?? values(answer), values: values(answer),
                  clearAnswer: state.explicitlyEdited == true && !answer.isAnswered ? true : nil)
        ])
    }
    static func command(_ types: [SiteVisitType]) throws -> SiteVisitWriteCommand {
        guard let first = types.first, types.allSatisfy({ $0.companyId.lowercased() == first.companyId.lowercased() }) else {
            throw SiteVisitWriteError.legacyPayload
        }
        return .init(companyId: first.companyId.lowercased(), entity: "template", rows: types.map { type in
            type.beginVersionedEdit()
            let state = type.writeState
            return .init(id: type.id.lowercased(), baseRevision: state.baseRevision ?? state.revision,
                         before: state.baseRow ?? values(type), values: values(type))
        })
    }
}
