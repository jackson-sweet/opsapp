//
//  CatalogBulkVariantExpansionModel.swift
//  OPS
//
//  Draft, navigation, and apply-state ownership for the three-stage bulk
//  variant expansion flow. Catalog planning remains in the pure planner.
//

import Combine
import Foundation

enum CatalogBulkVariantFlowStage: String, Codable, CaseIterable, Identifiable {
    case families
    case change
    case review

    var id: String { rawValue }

    var label: String {
        switch self {
        case .families: return "FAMILIES"
        case .change: return "CHANGE"
        case .review: return "REVIEW"
        }
    }
}

struct CatalogBulkVariantDraftValue: Codable, Equatable, Identifiable {
    let id: String
    var text: String

    init(id: String = UUID().uuidString.lowercased(), text: String = "") {
        self.id = id
        self.text = text
    }
}

struct CatalogBulkVariantCompletion: Equatable {
    let familyCount: Int
    let newVariantCount: Int
}

private struct CatalogBulkVariantExpansionDraft: Codable, Equatable {
    let companyId: String
    let selectedFamilyIds: [String]
    let axisName: String
    let existingValue: String
    let newValues: [CatalogBulkVariantDraftValue]
    let stage: CatalogBulkVariantFlowStage
    let idempotencyKey: String
}

@MainActor
final class CatalogBulkVariantExpansionModel: ObservableObject {
    @Published private(set) var stage: CatalogBulkVariantFlowStage = .families
    @Published private(set) var selectedFamilyIds: Set<String> = []
    @Published var searchText: String = ""
    @Published private(set) var axisName: String = ""
    @Published private(set) var existingValue: String = ""
    @Published private(set) var newValues: [CatalogBulkVariantDraftValue] = [.init()]
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var completion: CatalogBulkVariantCompletion?

    let companyId: String
    private(set) var idempotencyKey: String

    private let defaults: UserDefaults
    private let draftKey: String

    init(
        companyId: String,
        defaults: UserDefaults = .standard,
        draftKeyPrefix: String = "catalog.bulk-variant-expansion"
    ) {
        self.companyId = companyId
        self.defaults = defaults
        self.draftKey = "\(draftKeyPrefix).\(companyId.lowercased())"
        self.idempotencyKey = UUID().uuidString.lowercased()
        restoreDraft()
    }

    var trimmedNewValues: [String] {
        newValues.map { clean($0.text) }.filter { !$0.isEmpty }
    }

    var hasMeaningfulDraft: Bool {
        !selectedFamilyIds.isEmpty
            || !clean(axisName).isEmpty
            || !clean(existingValue).isEmpty
            || !trimmedNewValues.isEmpty
    }

    var changeValidationMessage: String? {
        let cleanAxis = clean(axisName)
        let cleanExisting = clean(existingValue)
        let values = newValues.map { clean($0.text) }

        if cleanAxis.isEmpty { return "Enter an option name." }
        if cleanExisting.isEmpty { return "Enter the value your current variants use." }
        if values.isEmpty || values.contains(where: \.isEmpty) {
            return "Add at least one new value."
        }

        let normalized = values.map(normalize)
        if Set(normalized).count != normalized.count {
            return "Each new value must be unique."
        }
        if normalized.contains(normalize(cleanExisting)) {
            return "A new value matches the existing value."
        }
        return nil
    }

    var canAdvance: Bool {
        switch stage {
        case .families:
            return !selectedFamilyIds.isEmpty
        case .change:
            return changeValidationMessage == nil
        case .review:
            return false
        }
    }

    func canApply(isOnline: Bool, canManage: Bool, previewCanApply: Bool) -> Bool {
        stage == .review
            && isOnline
            && canManage
            && previewCanApply
            && !isSaving
            && completion == nil
    }

    func toggleFamily(_ id: String, selectableFamilyIds: Set<String>) {
        guard selectableFamilyIds.contains(id) else { return }
        if selectedFamilyIds.contains(id) {
            selectedFamilyIds.remove(id)
        } else {
            selectedFamilyIds.insert(id)
        }
        inputChanged()
    }

    func selectAllVisible(_ visibleIds: [String], selectableFamilyIds: Set<String>) {
        selectedFamilyIds.formUnion(visibleIds.filter(selectableFamilyIds.contains))
        inputChanged()
    }

    func clearVisible(_ visibleIds: [String]) {
        selectedFamilyIds.subtract(visibleIds)
        inputChanged()
    }

    func removeUnavailableSelections(validFamilyIds: Set<String>) {
        let validSelections = selectedFamilyIds.intersection(validFamilyIds)
        guard validSelections != selectedFamilyIds else { return }
        selectedFamilyIds = validSelections
        inputChanged()
    }

    func setAxisName(_ value: String) {
        axisName = value
        inputChanged()
    }

    func setExistingValue(_ value: String) {
        existingValue = value
        inputChanged()
    }

    func setNewValue(_ value: String, at id: String) {
        guard let index = newValues.firstIndex(where: { $0.id == id }) else { return }
        newValues[index].text = value
        inputChanged()
    }

    func addNewValue() {
        guard newValues.count < 20 else { return }
        newValues.append(.init())
        inputChanged()
    }

    func removeNewValue(id: String) {
        guard newValues.count > 1 else {
            setNewValue("", at: id)
            return
        }
        newValues.removeAll { $0.id == id }
        inputChanged()
    }

    func advance() {
        guard canAdvance else { return }
        switch stage {
        case .families: stage = .change
        case .change: stage = .review
        case .review: return
        }
        errorMessage = nil
        persist()
    }

    func goBack() {
        guard !isSaving else { return }
        switch stage {
        case .families: return
        case .change: stage = .families
        case .review: stage = .change
        }
        errorMessage = nil
        persist()
    }

    func beginApply() {
        isSaving = true
        errorMessage = nil
    }

    func finishApply() {
        isSaving = false
    }

    func handleRejection(code: String?, message: String) {
        isSaving = false
        completion = nil
        stage = .review
        errorMessage = message
        persist()
    }

    func handleFailure(message: String) {
        isSaving = false
        errorMessage = message
        persist()
    }

    func renewIdempotencyKey() {
        idempotencyKey = UUID().uuidString.lowercased()
        persist()
    }

    func handleSuccess(familyCount: Int, newVariantCount: Int) {
        isSaving = false
        errorMessage = nil
        completion = .init(familyCount: familyCount, newVariantCount: newVariantCount)
        defaults.removeObject(forKey: draftKey)
    }

    func discardDraft() {
        defaults.removeObject(forKey: draftKey)
        stage = .families
        selectedFamilyIds = []
        searchText = ""
        axisName = ""
        existingValue = ""
        newValues = [.init()]
        isSaving = false
        errorMessage = nil
        completion = nil
        idempotencyKey = UUID().uuidString.lowercased()
    }

    private func inputChanged() {
        errorMessage = nil
        persist()
    }

    private func persist() {
        guard completion == nil else { return }
        let draft = CatalogBulkVariantExpansionDraft(
            companyId: companyId,
            selectedFamilyIds: selectedFamilyIds.sorted(),
            axisName: axisName,
            existingValue: existingValue,
            newValues: newValues,
            stage: stage,
            idempotencyKey: idempotencyKey
        )
        guard let encoded = try? JSONEncoder().encode(draft) else { return }
        defaults.set(encoded, forKey: draftKey)
    }

    private func restoreDraft() {
        guard let data = defaults.data(forKey: draftKey),
              let draft = try? JSONDecoder().decode(CatalogBulkVariantExpansionDraft.self, from: data),
              draft.companyId == companyId else {
            return
        }
        stage = draft.stage
        selectedFamilyIds = Set(draft.selectedFamilyIds)
        axisName = draft.axisName
        existingValue = draft.existingValue
        newValues = draft.newValues.isEmpty ? [.init()] : draft.newValues
        idempotencyKey = draft.idempotencyKey.isEmpty
            ? UUID().uuidString.lowercased()
            : draft.idempotencyKey
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ value: String) -> String {
        clean(value).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
