//
//  GuidedCatalogSetupModel.swift
//  OPS
//
//  State machine for the Guided Catalog Setup flow: survey → plan → modules →
//  done. Owns the BusinessProfile, the derived module list, the current
//  module's working set of product-line drafts, the lines committed this run,
//  draft persistence/resume, and the product-create action. Mirrors the
//  GuidedStockSetupModel pattern. Not the overlay Wizard System.
//

import Foundation
import SwiftData
import UIKit

@MainActor
final class GuidedCatalogSetupModel: ObservableObject {

    @Published var phase: GuidedCatalogPhase = .survey(questionIndex: 0)
    @Published var profile: BusinessProfile?
    @Published var productLines: [ProductLineDraft] = []   // current module's working set
    @Published var savedLines: [SavedProductLine] = []     // committed to the catalog this run
    @Published var isSaving = false
    @Published var errorMessage: String?

    private var didPostCompletion = false

    let companyId: String
    let userId: String
    private let draftStore: GuidedCatalogSetupDraftStore

    init(companyId: String, userId: String,
         draftStore: GuidedCatalogSetupDraftStore = .shared) {
        self.companyId = companyId
        self.userId = userId
        self.draftStore = draftStore
    }

    // MARK: - Derived

    var modules: [SetupModuleKind] { profile?.setupModules ?? [] }

    var currentModule: SetupModuleKind? {
        guard case .module(let i) = phase, modules.indices.contains(i) else { return nil }
        return modules[i]
    }

    var savedServiceCount: Int { savedLines.filter { $0.kind == .service }.count }
    var savedGoodCount: Int { savedLines.filter { $0.kind == .good }.count }

    // MARK: - Navigation

    /// Survey complete → show the tailored plan.
    func completeSurvey(with profile: BusinessProfile) {
        self.profile = profile
        phase = .plan
        persist()
    }

    /// Plan confirmed → enter the first module (or finish if none).
    func confirmPlan() {
        phase = modules.isEmpty ? .done : .module(index: 0)
        persist()
    }

    /// Advance to the next module, or to done after the last one.
    func advanceModule() {
        guard case .module(let i) = phase else { return }
        let next = i + 1
        phase = next < modules.count ? .module(index: next) : .done
        productLines = []   // each module opens with a clean working set
        persist()
    }

    func skipModule() { advanceModule() }

    // MARK: - Summary

    /// "2 services · 3 goods" — only non-zero parts, correct singular/plural.
    nonisolated static func summaryLine(services: Int, goods: Int) -> String {
        func part(_ n: Int, _ singular: String, _ plural: String) -> String? {
            n > 0 ? "\(n) \(n == 1 ? singular : plural)" : nil
        }
        let parts = [
            part(services, "service", "services"),
            part(goods, "good", "goods")
        ].compactMap { $0 }
        return parts.isEmpty ? "Nothing built" : parts.joined(separator: " · ")
    }

    // MARK: - Save a product line (service or good)

    /// Has this name already been used by a line saved this run (case-insensitive)?
    func isDuplicateName(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return savedLines.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    func saveProductLine(_ draft: ProductLineDraft,
                         trackCost: Bool,
                         units: [CatalogUnit],
                         categories: [CatalogCategory],
                         modelContext: ModelContext) async {
        guard !isSaving else { return }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let sell = parseMoney(draft.sellText) else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let category = draft.kind.productCategory
        let unit = units.first { $0.id == draft.unitId }
        let cost = trackCost ? parseMoney(draft.costText) : nil

        let dto = CreateProductDTO(
            companyId: companyId,
            name: trimmedName,
            description: nil,
            basePrice: sell,
            unitCost: cost,
            unit: unit?.display,
            pricingUnit: pricingUnit(for: unit).rawValue,
            unitId: unit?.id,
            category: categories.first { $0.id == draft.categoryId }?.name,
            categoryId: draft.categoryId,
            sku: nil,
            thumbnailUrl: nil,
            kind: category.derivedKindRaw,
            type: category.derivedType.rawValue,
            isTaxable: category.defaultTaxable,
            taskTypeId: nil,
            taskTypeRef: nil,
            linkedCatalogItemId: nil
        )

        do {
            let created = try await ProductRepository(companyId: companyId).create(dto)
            modelContext.insert(created.toModel())
            try? modelContext.save()
            savedLines.append(SavedProductLine(id: created.id, name: created.name,
                                               kind: draft.kind, sell: created.basePrice))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            persist()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Money helpers (mirror GuidedProductSetupFlow)

    func parseMoney(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    /// Live margin percent for a sell/cost pair, or nil if not computable.
    func marginPercent(sellText: String, costText: String) -> Double? {
        guard let sell = parseMoney(sellText), sell > 0, let cost = parseMoney(costText) else { return nil }
        return ((sell - cost) / sell) * 100
    }

    /// Currency string for display (whole dollars when even, else 2 decimals).
    nonisolated func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    // MARK: - Draft persistence (mirror GuidedStockSetupModel)

    private var draftContext: CatalogSetupDraftContext? {
        guard let base = CatalogSetupDraftContext.make(companyId: companyId, userId: userId) else { return nil }
        return CatalogSetupDraftContext(companyId: base.companyId, userId: base.userId, scope: "catalog-guided")
    }

    func persist() {
        guard let context = draftContext else { return }
        let snapshot = GuidedCatalogSetupDraftSnapshot(
            context: context,
            phase: phase,
            profile: profile,
            productLines: productLines,
            savedLines: savedLines
        )
        do { try draftStore.save(snapshot) }
        catch { print("[GuidedCatalogSetupModel] draft persist failed: \(error)") }
    }

    @discardableResult
    func restoreIfAvailable() -> Bool {
        guard let context = draftContext else { return false }
        do {
            guard let snapshot = try draftStore.load(context: context) else { return false }
            phase = snapshot.phase
            profile = snapshot.profile
            productLines = snapshot.productLines
            savedLines = snapshot.savedLines
            return true
        } catch {
            print("[GuidedCatalogSetupModel] draft restore failed: \(error)")
            return false
        }
    }

    func clearDraft() {
        guard let context = draftContext else { return }
        try? draftStore.clear(context: context)
    }

    var hasDraftToResume: Bool {
        guard let context = draftContext else { return false }
        return (try? draftStore.load(context: context)) != nil
    }

    // MARK: - §14 completion notification

    /// Fires once, only when something was actually created this run.
    func postCompletionNotification() {
        guard !didPostCompletion, !savedLines.isEmpty else { return }
        guard !userId.isEmpty, !companyId.isEmpty else { return }
        didPostCompletion = true
        let body = "\(GuidedCatalogSetupModel.summaryLine(services: savedServiceCount, goods: savedGoodCount)) saved for estimating."
        let userId = self.userId
        let companyId = self.companyId
        Task {
            try? await NotificationRepository.shared.createNotification(.init(
                userId: userId,
                companyId: companyId,
                type: "standard",
                title: "CATALOG SETUP COMPLETE",
                body: body,
                deepLinkType: "catalog_products",
                persistent: false,
                actionUrl: "/catalog?segment=products",
                actionLabel: "VIEW PRODUCTS"
            ))
            NotificationCenter.default.post(name: .notificationReceived, object: nil)
        }
    }
}
