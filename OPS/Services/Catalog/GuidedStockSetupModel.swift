import Foundation
import Combine

// MARK: - Guided stock setup data model (backbone for all later phases)

enum GuidedStockStage: Int, Codable, CaseIterable, Hashable {
    case prime = 0
    case capture
    case structure
    case blueprint
    case done
}

/// Does the operator stock it, sell it, or both.
enum GuidedItemKind: String, Codable, CaseIterable, Hashable {
    case stock
    case sell
    case both
}

/// One raw thing the operator dumped out in the CAPTURE step.
struct GuidedCapturedItem: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var kind: GuidedItemKind

    init(id: String = UUID().uuidString, name: String, kind: GuidedItemKind = .stock) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// How on-hand quantity is tracked for a family.
enum GuidedMeasurement: String, Codable, CaseIterable, Hashable {
    case piece   // counted
    case length  // measured in length units (ft)
    case area    // width x length (sq ft)
}

/// One attribute (e.g. "Color") with its candidate values (e.g. Black/White/Grey).
struct GuidedAttribute: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var values: [String]

    init(id: String = UUID().uuidString, name: String = "", values: [String] = []) {
        self.id = id
        self.name = name
        self.values = values
    }
}

/// Stock reality answers for one variant of a family.
/// `variantKey` is the sorted-joined option-value signature, or "" for a single-variant family.
struct GuidedStockEntry: Codable, Hashable {
    var variantKey: String
    var pieceCount: Double?          // measurement == .piece
    var fullUnitWidth: Double?       // measurement == .area
    var fullUnitLength: Double?      // measurement == .length || .area
    var fullUnitCount: Double?       // how many full units on hand
    var offcutLengths: [Double]      // remaining lengths of partial/offcut units (same width)

    init(variantKey: String = "", pieceCount: Double? = nil, fullUnitWidth: Double? = nil,
         fullUnitLength: Double? = nil, fullUnitCount: Double? = nil, offcutLengths: [Double] = []) {
        self.variantKey = variantKey
        self.pieceCount = pieceCount
        self.fullUnitWidth = fullUnitWidth
        self.fullUnitLength = fullUnitLength
        self.fullUnitCount = fullUnitCount
        self.offcutLengths = offcutLengths
    }
}

enum GuidedSellMode: String, Codable, CaseIterable, Hashable {
    case onItsOwn
    case inPackage
    case both
}

/// A child item inside a package/bundle, marked required or suggested.
struct GuidedBundleChild: Codable, Hashable {
    var capturedItemId: String
    var isRequired: Bool

    init(capturedItemId: String, isRequired: Bool = true) {
        self.capturedItemId = capturedItemId
        self.isRequired = isRequired
    }
}

/// Product / bundle / recipe answers for a SELL or BOTH family (capability-gated in P5).
struct GuidedProductAnswers: Codable, Hashable {
    var sellMode: GuidedSellMode?
    var sellingUsesStock: Bool?            // recipe link (product_materials) when stocked + sold
    var bundleChildren: [GuidedBundleChild]

    init(sellMode: GuidedSellMode? = nil, sellingUsesStock: Bool? = nil, bundleChildren: [GuidedBundleChild] = []) {
        self.sellMode = sellMode
        self.sellingUsesStock = sellingUsesStock
        self.bundleChildren = bundleChildren
    }
}

/// A confirmed group of captured items that becomes ONE catalog family.
struct GuidedStructuredGroup: Identifiable, Codable, Hashable {
    var id: String
    var familyName: String
    var memberItemIds: [String]
    var isSingleItem: Bool                 // "one thing" vs "different versions"
    var attributes: [GuidedAttribute]      // empty when isSingleItem
    var measurement: GuidedMeasurement?
    var lengthUnit: String
    var widthUnit: String
    var stockEntries: [GuidedStockEntry]
    var product: GuidedProductAnswers
    var isConfirmed: Bool                  // grouping confirmed by the operator (screen 2a)

    init(id: String = UUID().uuidString, familyName: String = "", memberItemIds: [String] = [],
         isSingleItem: Bool = true, attributes: [GuidedAttribute] = [], measurement: GuidedMeasurement? = nil,
         lengthUnit: String = "ft", widthUnit: String = "ft", stockEntries: [GuidedStockEntry] = [],
         product: GuidedProductAnswers = GuidedProductAnswers(), isConfirmed: Bool = false) {
        self.id = id
        self.familyName = familyName
        self.memberItemIds = memberItemIds
        self.isSingleItem = isSingleItem
        self.attributes = attributes
        self.measurement = measurement
        self.lengthUnit = lengthUnit
        self.widthUnit = widthUnit
        self.stockEntries = stockEntries
        self.product = product
        self.isConfirmed = isConfirmed
    }
}

/// Summary counts shown on the DONE screen and in the completion notification.
struct GuidedStockSummary: Codable, Hashable {
    var familyCount: Int
    var variantCount: Int
    var rollCount: Int
    var offcutCount: Int
    var productCount: Int
    var bundleCount: Int

    init(familyCount: Int = 0, variantCount: Int = 0, rollCount: Int = 0,
         offcutCount: Int = 0, productCount: Int = 0, bundleCount: Int = 0) {
        self.familyCount = familyCount
        self.variantCount = variantCount
        self.rollCount = rollCount
        self.offcutCount = offcutCount
        self.productCount = productCount
        self.bundleCount = bundleCount
    }
}

/// Commit orchestration state (P6). Not persisted; resume is driven by committedGroupIds.
enum GuidedCommitProgress: Codable, Hashable {
    case idle
    case running(done: Int, total: Int)
    case partial(failedGroupIds: [String])
    case complete(GuidedStockSummary)
}

// MARK: - State machine

@MainActor
final class GuidedStockSetupModel: ObservableObject {
    @Published var stage: GuidedStockStage = .prime
    @Published var capturedItems: [GuidedCapturedItem] = []
    @Published var groups: [GuidedStructuredGroup] = []          // produced in P3
    @Published var committedGroupIds: [String] = []              // resume support (P6)
    @Published var commitProgress: GuidedCommitProgress = .idle

    let companyId: String
    let userId: String
    private let draftStore: GuidedStockSetupDraftStore

    init(companyId: String, userId: String, draftStore: GuidedStockSetupDraftStore = .shared) {
        self.companyId = companyId
        self.userId = userId
        self.draftStore = draftStore
    }

    private var draftContext: CatalogSetupDraftContext? {
        guard let base = CatalogSetupDraftContext.make(companyId: companyId, userId: userId) else { return nil }
        return CatalogSetupDraftContext(companyId: base.companyId, userId: base.userId, scope: "guided")
    }

    // MARK: - Capture helpers

    /// Captured items with a real (non-blank) name.
    var capturableItems: [GuidedCapturedItem] {
        capturedItems.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var capturableItemCount: Int { capturableItems.count }

    /// Drop blank rows (called when leaving CAPTURE).
    func pruneEmptyCapturedItems() {
        capturedItems.removeAll { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Navigation — clamped to the valid stage range; persists after every move.

    func advance() {
        if stage == .capture { pruneEmptyCapturedItems() }
        let all = GuidedStockStage.allCases
        if let idx = all.firstIndex(of: stage), idx + 1 < all.count {
            stage = all[idx + 1]
            persist()
        }
    }

    func back() {
        let all = GuidedStockStage.allCases
        if let idx = all.firstIndex(of: stage), idx > 0 {
            stage = all[idx - 1]
            persist()
        }
    }

    // MARK: - Structure seeding

    /// Build candidate groups from the captured list using deterministic clustering.
    /// Idempotent: only seeds when `groups` is empty (so re-entering STRUCTURE keeps edits).
    func seedGroupsFromCapture(threshold: Double = 0.5) {
        guard groups.isEmpty else { return }
        let items = capturableItems
        let clusters = GuidedStockStructuring.cluster(items, threshold: threshold)
        let clusteredIds = Set(clusters.flatMap { $0.memberItemIds })
        var seeded: [GuidedStructuredGroup] = []

        for cluster in clusters {
            let stableId = "group::" + cluster.memberItemIds.sorted().joined(separator: ":")
            let proposed = GuidedStockStructuring.proposeValues(for: cluster)
            // Proposed as "comes in versions"; stash the differing tokens as the first attribute's prefill values.
            seeded.append(GuidedStructuredGroup(
                id: stableId,
                familyName: cluster.stem,
                memberItemIds: cluster.memberItemIds,
                isSingleItem: false,
                attributes: proposed.isEmpty ? [] : [GuidedAttribute(name: "", values: proposed)],
                isConfirmed: false
            ))
        }
        for item in items where !clusteredIds.contains(item.id) {
            seeded.append(GuidedStructuredGroup(
                id: "group::" + item.id,
                familyName: item.name,
                memberItemIds: [item.id],
                isSingleItem: true,
                attributes: [],
                isConfirmed: false
            ))
        }
        groups = seeded
        persist()
    }

    // MARK: - Draft persistence

    func persist() {
        guard let context = draftContext else { return }
        let snapshot = GuidedStockSetupDraftSnapshot(
            context: context,
            stage: stage.rawValue,
            capturedItems: capturedItems,
            groups: groups,
            committedGroupIds: committedGroupIds
        )
        do {
            try draftStore.save(snapshot)
        } catch {
            print("[GuidedStockSetupModel] draft persist failed: \(error)")
        }
    }

    @discardableResult
    func restoreIfAvailable() -> Bool {
        guard let context = draftContext else { return false }
        do {
            guard let snapshot = try draftStore.load(context: context) else { return false }
            stage = GuidedStockStage(rawValue: snapshot.stage) ?? .prime
            capturedItems = snapshot.capturedItems
            groups = snapshot.groups
            committedGroupIds = snapshot.committedGroupIds
            return true
        } catch {
            print("[GuidedStockSetupModel] draft restore failed: \(error)")
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

    // MARK: - Commit orchestration (P6)

    /// Build one family's full catalog_setup_save payload (stock core via makeSavePayload +
    /// guided product section). `resolveUnitId` maps the group's measurement to a catalog_units
    /// id (creating one if needed). `childProductIdByItemId` carries resolved SERVER product ids
    /// from already-committed groups (for bundle children).
    private func buildPayload(
        for group: GuidedStructuredGroup,
        resolveUnitId: (GuidedMeasurement) async throws -> String,
        childProductIdByItemId: [String: String]
    ) async throws -> CatalogSetupSavePayload {
        let attributes = GuidedStockDraftBuilder.attributeDrafts(for: group)
        var variants = GuidedStockDraftBuilder.variantDrafts(for: group).map { variant -> CatalogSetupVariantDraft in
            var v = variant
            if let entry = group.stockEntries.first(where: { $0.variantKey == v.id }) {
                v.stockUnits = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)
            }
            return v
        }
        try CatalogSetupWorkflow.validateStockQuantities(variants: variants)

        var unitId: String? = nil
        if let measurement = group.measurement {
            unitId = try await resolveUnitId(measurement)
        }

        var payload = CatalogSetupWorkflow.makeSavePayload(
            mode: "create",
            draftId: group.id,
            familyName: group.familyName,
            familyDescription: "",
            familyImageUrl: "",
            selectedCategoryId: nil,
            selectedUnitId: unitId,
            defaultWarningThreshold: nil,
            defaultCriticalThreshold: nil,
            attributes: attributes,
            variants: variants,
            selectedProduct: nil,
            productOptionSelectionByAttributeId: [:],
            productValueSelectionByCatalogValueId: [:],
            productOptions: [],
            productOptionValues: []
        )
        payload.products = GuidedStockProductBuilder.productPayloads(
            for: group,
            companyId: companyId,
            familyClientId: payload.family.clientId,
            recipeVariantClientId: nil,
            childProductIdByItemId: childProductIdByItemId
        )
        return payload
    }

    /// Summarise what was committed across all successfully committed groups.
    private func buildSummary(committed: [GuidedStructuredGroup]) -> GuidedStockSummary {
        var s = GuidedStockSummary()
        s.familyCount = committed.count
        for g in committed {
            s.variantCount += GuidedStockDraftBuilder.variantCount(for: g)
            for entry in g.stockEntries {
                for draft in GuidedStockDraftBuilder.stockUnitDrafts(for: g, entry: entry) {
                    if draft.unitKind == .offcut {
                        s.offcutCount += 1
                    } else if draft.unitKind == .roll {
                        s.rollCount += 1
                    }
                }
            }
            if g.product.sellMode != nil { s.productCount += 1 }
            if g.product.sellMode == .inPackage { s.bundleCount += 1 }
        }
        return s
    }

    /// Commit every confirmed group through the atomic per-family RPC.
    ///
    /// Resumable (skips ids already in committedGroupIds), idempotent (SaveAttempt per
    /// family), offline-safe (no calls when offline → stays .idle / held).
    /// Bundles commit AFTER non-bundle groups so their children are resolvable by server id.
    func commitAll(
        service: CatalogSetupCommitting,
        resolveUnitId: @escaping (GuidedMeasurement) async throws -> String,
        isOnline: Bool
    ) async {
        guard isOnline else { commitProgress = .idle; return }

        let committable = groups.filter { $0.isConfirmed }
        // Non-package groups first; package (bundle) groups last so child product ids resolve.
        let ordered = committable.sorted { a, b in
            (a.product.sellMode == .inPackage ? 1 : 0) < (b.product.sellMode == .inPackage ? 1 : 0)
        }
        guard !ordered.isEmpty else { commitProgress = .complete(GuidedStockSummary()); return }

        var childProductIdByItemId: [String: String] = [:]
        var failed: [String] = []
        var done = 0
        commitProgress = .running(done: 0, total: ordered.count)

        for group in ordered {
            if committedGroupIds.contains(group.id) {
                done += 1
                commitProgress = .running(done: done, total: ordered.count)
                continue
            }
            do {
                let payload = try await buildPayload(
                    for: group,
                    resolveUnitId: resolveUnitId,
                    childProductIdByItemId: childProductIdByItemId
                )
                let attempt = try CatalogSetupSaveAttempt.resolve(payload: payload, existingAttempt: nil)
                let outcome = try await service.commit(payload: payload, saveAttempt: attempt)
                switch outcome {
                case .committed(let response):
                    _ = service.reconcile(payload: payload, response: response)
                    if !committedGroupIds.contains(group.id) {
                        committedGroupIds.append(group.id)
                    }
                    // Expose this group's server product id for downstream bundle children.
                    let productClientId = GuidedStockProductBuilder.productClientId(for: group)
                    if let pid = response.idMap[productClientId], !pid.isEmpty {
                        for itemId in group.memberItemIds {
                            childProductIdByItemId[itemId] = pid
                        }
                    }
                    done += 1
                case .rejected:
                    failed.append(group.id)
                }
            } catch {
                failed.append(group.id)
            }
            persist()
            commitProgress = .running(done: done, total: ordered.count)
        }

        if failed.isEmpty {
            let committedGroups = ordered.filter { committedGroupIds.contains($0.id) }
            commitProgress = .complete(buildSummary(committed: committedGroups))
            clearDraft()
        } else {
            commitProgress = .partial(failedGroupIds: failed)
        }
    }
}
