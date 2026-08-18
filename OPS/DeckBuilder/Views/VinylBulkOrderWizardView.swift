//
//  VinylBulkOrderWizardView.swift
//  OPS
//
//  The bulk ORDER wizard (spec §§ 6–7): one review page per selected job —
//  color, PO, cuts, roll visualization, collapsed layout knobs — then a
//  consumables + send page that aggregates flashing tubes and glue buckets
//  across every confirmed job, composes ONE combined supplier text, and
//  auto-marks every job ordered when the message sends.
//
//  Page state mirrors the single-project order sheet: confirmed vinyl layout,
//  color/catalog picks, order mode, and roll length write through to the design,
//  and whatever layout is live at send freezes into each job's snapshot.
//

import MessageUI
import SwiftData
import SwiftUI
import UIKit

// MARK: - Wizard inputs

/// One selected job, assembled by the board with everything its page needs.
struct VinylBulkOrderJob: Identifiable {
    enum DegenerateReason {
        case noDrawing
        case unconfirmedScale

        var label: String {
            switch self {
            case .noDrawing:
                return "NO DECK DRAWING — ORDERS COLOR + PO ONLY."
            case .unconfirmedScale:
                return "SCALE UNCONFIRMED — CUTS UNAVAILABLE. CONFIRM AN EDGE LENGTH ON THE DECK TAB TO ORDER CUTS."
            }
        }
    }

    let projectId: String
    let title: String
    let design: DeckDesign?
    let resolved: DeckMaterialsResolver.Resolved?
    let facesByLevel: [[DetectedSurface]]
    let taskTypeDisplays: [String]
    let degenerateReason: DegenerateReason?

    var id: String { projectId }
}

struct VinylBulkOrderWizardContext: Identifiable {
    let companyId: String
    let userId: String?
    let jobs: [VinylBulkOrderJob]

    var id: String { jobs.map(\.projectId).joined(separator: "|") }
}

/// Editable per-page state. Vinyl layout settings, order mode, and roll length
/// write through to the design at CONFIRM.
private struct VinylWizardPageState {
    var vinylSettings: VinylOrderSettings
    var materialsSettings: DeckMaterialsSettings
    var po: String
    var confirmed = false
    var showLayout = false
    var plan: VinylCutPlan?
    /// Where this job's material comes from. `.shop` drops the job out of the
    /// supplier message entirely — you do not ask a supplier for material that
    /// is already on your rack — while still committing the job as handled.
    var disposition: VinylOrderDisposition = .supplier
    /// The vinyl quantity the operator is actually ordering for this job. Seeded
    /// from the calculator, then nudgeable — the calculated plan is a starting
    /// point, and what gets recorded is what the operator wrote.
    ///
    /// nil until the plan first resolves; `orderedVinylQuantity` reads through
    /// to the calculated value while it is nil so an untouched page always
    /// commits the calculator's number.
    var orderedSqFtOverride: Int?
    var orderedRollsOverride: Int?

    /// True when the operator moved either vinyl quantity off the calculation.
    var hasQuantityOverride: Bool {
        orderedSqFtOverride != nil || orderedRollsOverride != nil
    }
}

// MARK: - Wizard root

struct VinylBulkOrderWizardView: View {
    let context: VinylBulkOrderWizardContext
    /// Called after the commit pass with the outcome AND the failed subset of
    /// items so the board's banner can offer RETRY on partial failure.
    let onCommitted: (VinylBulkMarkOutcome, [VinylBulkMarkItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @Query private var catalogItems: [CatalogItem]
    @Query private var catalogVariants: [CatalogVariant]
    @Query private var catalogOptionValues: [CatalogOptionValue]
    @Query private var catalogVariantOptionValues: [CatalogVariantOptionValue]

    @State private var pageIndex = 0
    @State private var pageStates: [VinylWizardPageState] = []
    @State private var showingCancelConfirm = false
    @State private var didSeed = false

    private var jobs: [VinylBulkOrderJob] { context.jobs }
    private var onSendPage: Bool { pageIndex >= jobs.count }
    private var hasConfirmedAny: Bool { pageStates.contains(where: \.confirmed) }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                if didSeed {
                    if onSendPage {
                        VinylBulkOrderSendPageView(
                            context: context,
                            sections: confirmedSections,
                            needs: confirmedNeeds,
                            makeCommitItems: { commitItems(purchasedConsumables: $0) },
                            onBack: { withAnimation(OPSStyle.Animation.page) { pageIndex = max(0, jobs.count - 1) } },
                            onCommitted: { outcome, failedItems in onCommitted(outcome, failedItems) }
                        )
                    } else {
                        pageBody
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    wizardHeader
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CANCEL") {
                        if hasConfirmedAny {
                            showingCancelConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .toolbarBackground(OPSStyle.Colors.cardBackgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                "CANCEL ORDER?",
                isPresented: $showingCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("CANCEL ORDER", role: .destructive) { dismiss() }
                Button("KEEP ORDERING", role: .cancel) {}
            } message: {
                Text("NOTHING SENDS AND NOTHING IS MARKED.")
            }
            .interactiveDismissDisabled(hasConfirmedAny)
            .task { seedIfNeeded() }
        }
    }

    // MARK: - Header

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(onSendPage ? "ORDER · SEND" : "ORDER · \(pageIndex + 1) OF \(jobs.count)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text(onSendPage ? "FLASHING + GLUE + MESSAGE" : jobs[pageIndex].title.uppercased())
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Per-job page

    private var pageBody: some View {
        let job = jobs[pageIndex]
        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    VinylBulkOrderPageView(
                        job: job,
                        state: pageStateBinding(pageIndex),
                        catalogChoices: catalogChoices,
                        optionValues: catalogOptionValues,
                        variantOptionValues: catalogVariantOptionValues,
                        onPlanInputChange: { recomputePlan(at: pageIndex) }
                    )
                    Color.clear.frame(height: OPSStyle.Layout.touchTargetLarge * 2)
                }
                .padding(OPSStyle.Layout.spacing3)
            }

            pageActionBar
        }
    }

    private var pageActionBar: some View {
        OPSFloatingButtonBar(
            horizontalPadding: OPSStyle.Layout.spacing3,
            verticalPadding: OPSStyle.Layout.spacing2
        ) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button {
                    withAnimation(OPSStyle.Animation.page) {
                        if pageIndex > 0 { pageIndex -= 1 }
                    }
                } label: {
                    Text("BACK")
                }
                .opsSecondaryButtonStyle()
                .disabled(pageIndex == 0)
                .opacity(pageIndex == 0 ? OPSStyle.Layout.Opacity.medium : 1)

                Button {
                    confirmPage(at: pageIndex)
                } label: {
                    Text("CONFIRM")
                }
                .opsPrimaryButtonStyle(isDisabled: !canConfirmCurrentPage)
                .disabled(!canConfirmCurrentPage)
            }
        }
    }

    private var canConfirmCurrentPage: Bool {
        pageStates.indices.contains(pageIndex)
    }

    private func confirmPage(at index: Int) {
        guard index < pageStates.count else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        pageStates[index].confirmed = true
        writeThroughConfig(at: index)
        withAnimation(OPSStyle.Animation.page) {
            pageIndex = index + 1
        }
    }

    /// Persist the confirmed layout, color/catalog pick, and order mode so a
    /// later sheet open restores exactly what the operator reviewed.
    private func writeThroughConfig(at index: Int) {
        let job = jobs[index]
        guard let design = job.design else { return }
        let state = pageStates[index]

        var data = design.drawingData
        let trimmedColor = state.vinylSettings.color.trimmingCharacters(in: .whitespacesAndNewlines)
        let newColor = trimmedColor.isEmpty ? nil : trimmedColor
        let newVariantId = state.vinylSettings.catalogVariantId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newItemId = state.vinylSettings.catalogItemId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVariantId = (newVariantId?.isEmpty ?? true) ? nil : newVariantId
        let normalizedItemId = (newItemId?.isEmpty ?? true) ? nil : newItemId

        var persistedVinylSettings = state.vinylSettings
        persistedVinylSettings.color = newColor ?? ""
        persistedVinylSettings.catalogVariantId = normalizedVariantId
        persistedVinylSettings.catalogItemId = normalizedItemId

        var materialsSettings = data.materialsSettings ?? DeckMaterialsSettings()
        let settingsChanged = materialsSettings.orderMode != state.materialsSettings.orderMode
            || materialsSettings.fullRollLengthFeet != state.materialsSettings.fullRollLengthFeet
        materialsSettings.orderMode = state.materialsSettings.orderMode
        materialsSettings.fullRollLengthFeet = state.materialsSettings.fullRollLengthFeet

        let configChanged = data.config.vinylColor != newColor
            || data.config.vinylCatalogVariantId != normalizedVariantId
            || data.config.vinylCatalogItemId != normalizedItemId
        let vinylSettingsChanged = data.vinylOrderSettings != persistedVinylSettings

        guard configChanged || settingsChanged || vinylSettingsChanged else { return }
        data.config.vinylColor = newColor
        data.config.vinylCatalogVariantId = normalizedVariantId
        data.config.vinylCatalogItemId = normalizedItemId
        data.vinylOrderSettings = persistedVinylSettings
        data.materialsSettings = materialsSettings
        design.drawingData = data
    }

    // MARK: - State seeding + plan recompute

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        pageStates = jobs.map { job in
            var vinyl = VinylOrderSettings.default
            var materials = DeckMaterialsSettings()
            if let design = job.design {
                let data = design.drawingData
                vinyl = data.vinylOrderSettings ?? .default
                let restoredItemId = data.config.vinylCatalogItemId ?? vinyl.catalogItemId
                let restored = VinylCatalogSelection.restoredSelection(
                    configItemId: restoredItemId?.trimmingCharacters(in: .whitespacesAndNewlines),
                    configVariantId: data.config.vinylCatalogVariantId ?? vinyl.catalogVariantId,
                    configColor: data.config.vinylColor ?? vinyl.color,
                    availableItemIds: Set(catalogChoices.map(\.id)),
                    variantIdsByItem: Dictionary(
                        uniqueKeysWithValues: catalogChoices.map { ($0.id, Set($0.variants.map(\.id))) }
                    )
                )
                vinyl.catalogItemId = restored.itemId
                vinyl.catalogVariantId = restored.variantId
                vinyl.color = restored.color ?? ""
                materials = data.materialsSettings ?? DeckMaterialsSettings()
            }
            var state = VinylWizardPageState(
                vinylSettings: vinyl,
                materialsSettings: materials,
                po: job.title
            )
            if let inputs = job.resolved?.vinylInputs, job.degenerateReason == nil {
                state.plan = VinylCutListEngine.makePlan(surfaces: inputs, settings: vinyl)
            }
            return state
        }
    }

    private func pageStateBinding(_ index: Int) -> Binding<VinylWizardPageState> {
        Binding(
            get: { pageStates.indices.contains(index) ? pageStates[index] : VinylWizardPageState(
                vinylSettings: .default, materialsSettings: DeckMaterialsSettings(), po: ""
            ) },
            set: { if pageStates.indices.contains(index) { pageStates[index] = $0 } }
        )
    }

    private func recomputePlan(at index: Int) {
        guard pageStates.indices.contains(index),
              let inputs = jobs[index].resolved?.vinylInputs,
              jobs[index].degenerateReason == nil else { return }
        pageStates[index].plan = VinylCutListEngine.makePlan(
            surfaces: inputs,
            settings: pageStates[index].vinylSettings
        )
    }

    private var catalogChoices: [VinylCatalogProductChoice] {
        VinylCatalogSelection.productChoices(
            companyId: context.companyId,
            items: catalogItems,
            variants: catalogVariants,
            optionValues: catalogOptionValues,
            variantOptionValues: catalogVariantOptionValues
        )
    }

    // MARK: - Send-page assembly

    /// Message sections for every confirmed job, wizard order (spec § 7).
    /// Cut lines render through the user's existing cut-template preference.
    private var confirmedSections: [VinylBulkOrderSection] {
        let cutTemplate = UserDefaults.standard.string(forKey: VinylCutListTextTemplate.cutStorageKey)
            ?? VinylCutListTextTemplate.defaultCutTemplate

        return zip(jobs, pageStates)
            // A job pulled FROM SHOP needs nothing from the supplier, so it
            // contributes no section — asking for material already on the rack
            // is exactly the over-ordering this board exists to stop. It still
            // commits below as handled.
            .filter { _, state in state.confirmed && state.disposition == .supplier }
            .map { job, state in
                let color = state.vinylSettings.color.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let plan = state.plan, job.degenerateReason == nil else {
                    return VinylBulkOrderSection(po: state.po, color: color, cutLines: [], rollsLine: nil)
                }
                if state.materialsSettings.orderMode == .fullRolls {
                    let pack = VinylRollPacker.rollsNeeded(
                        stripLengthsFeet: plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12.0 },
                        rollLengthFeet: state.materialsSettings.fullRollLengthFeet
                    )
                    // The supplier is told what the operator is actually buying,
                    // not what the calculator suggested.
                    let rollCount = state.orderedRollsOverride ?? pack.rollCount
                    guard rollCount > 0 else {
                        return VinylBulkOrderSection(po: state.po, color: color, cutLines: [], rollsLine: nil)
                    }
                    let rolls = "\(rollCount) ROLL\(rollCount == 1 ? "" : "S") @ \(Int(state.materialsSettings.fullRollLengthFeet))' × \(vinylFormatInches(state.vinylSettings.rollWidthInches))"
                    return VinylBulkOrderSection(po: state.po, color: color, cutLines: [], rollsLine: rolls)
                }
                let lines = VinylCutListTextTemplate.cutLines(for: plan, cutTemplate: cutTemplate)
                return VinylBulkOrderSection(
                    po: state.po,
                    color: color,
                    cutLines: lines == ["—"] ? [] : lines,
                    rollsLine: nil
                )
            }
    }

    /// Per-job consumable needs for the aggregator — resolved materials at the
    /// page's confirmed settings. Degenerate jobs contribute nothing, and
    /// neither do shop-sourced jobs: their flashing and glue came off the same
    /// rack as their vinyl.
    private var confirmedNeeds: [VinylConsumableNeed] {
        zip(jobs, pageStates)
            .filter { job, state in
                state.confirmed && job.degenerateReason == nil && state.disposition == .supplier
            }
            .compactMap { job, state in
                guard let resolved = job.resolved, !resolved.vinylInputs.isEmpty else { return nil }
                let materials = DeckMaterialsEngine.compute(
                    vinylInputs: resolved.vinylInputs,
                    allDetectedFacesByLevel: job.facesByLevel,
                    settings: state.materialsSettings,
                    vinylSettings: state.vinylSettings
                )
                return VinylConsumableNeed(
                    dripSticks: materials.dripEdge.sticks,
                    ninetySticks: materials.ninetyFlash.sticks,
                    clipSticks: materials.clip.sticks,
                    glueAreaSqFt: materials.glueAreaSqFt,
                    glueCoverageSqFt: state.materialsSettings.glueCoverageSqFt
                )
            }
    }

    /// Commit items for every confirmed job — materials recomputed at the
    /// page's confirmed settings so each frozen snapshot mirrors exactly what
    /// the message ordered; degenerate jobs commit marker fields only.
    ///
    /// `purchasedConsumables` are the operator's FINAL tube/bucket counts from
    /// the send page. Those numbers were previously composed into the supplier
    /// text and then thrown away — the record kept whatever the calculator had
    /// said. They are now attributed back to every job that shared the purchase,
    /// as the shared count plus its sharing partners (never a per-job fraction:
    /// three tubes across four jobs is three tubes, and 0.75 of a tube is a
    /// quantity nobody ordered).
    private func commitItems(
        purchasedConsumables: [VinylSharedConsumable.Kind: Int]
    ) -> [VinylBulkMarkItem] {
        let confirmedPairs = zip(jobs, pageStates).filter { _, state in state.confirmed }
        // Only supplier-sourced jobs took part in the purchase, so only they
        // appear in one another's "shared with" list.
        let supplierTitles = confirmedPairs
            .filter { _, state in state.disposition == .supplier }
            .map { job, _ in job.title }

        return confirmedPairs.map { job, state in
            let color = state.vinylSettings.color.trimmingCharacters(in: .whitespacesAndNewlines)
            let po = state.po.trimmingCharacters(in: .whitespacesAndNewlines)
            let shared = sharedConsumables(
                for: job,
                state: state,
                purchased: purchasedConsumables,
                supplierTitles: supplierTitles
            )

            guard let design = job.design,
                  let resolved = job.resolved,
                  !resolved.vinylInputs.isEmpty,
                  job.degenerateReason == nil else {
                return VinylBulkMarkItem(
                    projectId: job.projectId,
                    design: nil,
                    materials: nil,
                    settings: state.materialsSettings,
                    vinylSettings: state.vinylSettings,
                    color: color.isEmpty ? nil : color,
                    po: po.isEmpty ? nil : po,
                    projectTitle: job.title,
                    disposition: state.disposition,
                    sharedConsumables: shared,
                    orderedSqFtOverride: state.orderedSqFtOverride,
                    orderedRollsOverride: state.orderedRollsOverride
                )
            }

            let materials = DeckMaterialsEngine.compute(
                vinylInputs: resolved.vinylInputs,
                allDetectedFacesByLevel: job.facesByLevel,
                settings: state.materialsSettings,
                vinylSettings: state.vinylSettings
            )
            return VinylBulkMarkItem(
                projectId: job.projectId,
                design: design,
                materials: materials,
                settings: state.materialsSettings,
                vinylSettings: state.vinylSettings,
                color: color.isEmpty ? nil : color,
                po: po.isEmpty ? nil : po,
                projectTitle: job.title,
                disposition: state.disposition,
                sharedConsumables: shared,
                orderedSqFtOverride: state.orderedSqFtOverride,
                orderedRollsOverride: state.orderedRollsOverride
            )
        }
    }

    /// This job's share of the purchased consumables. A shop-sourced job bought
    /// nothing, so it records nothing.
    private func sharedConsumables(
        for job: VinylBulkOrderJob,
        state: VinylWizardPageState,
        purchased: [VinylSharedConsumable.Kind: Int],
        supplierTitles: [String]
    ) -> [VinylSharedConsumable] {
        guard state.disposition == .supplier else { return [] }
        let partners = supplierTitles.filter { $0 != job.title }
        return VinylSharedConsumable.Kind.allCases.compactMap { kind in
            guard let count = purchased[kind], count > 0 else { return nil }
            return VinylSharedConsumable(kind: kind, count: count, sharedWith: partners)
        }
    }
}

// MARK: - Per-job review page

private struct VinylBulkOrderPageView: View {
    let job: VinylBulkOrderJob
    @Binding var state: VinylWizardPageState
    let catalogChoices: [VinylCatalogProductChoice]
    let optionValues: [CatalogOptionValue]
    let variantOptionValues: [CatalogVariantOptionValue]
    let onPlanInputChange: () -> Void

    private var selectedChoice: VinylCatalogProductChoice? {
        guard let itemId = state.vinylSettings.catalogItemId else { return nil }
        return catalogChoices.first { $0.id == itemId }
    }

    var body: some View {
        Group {
            if let reason = job.degenerateReason {
                degenerateBanner(reason)
            }

            colorSection
            poSection

            if job.degenerateReason == nil, let plan = state.plan {
                orderSection(plan)

                VinylOrderLayoutWindow(
                    plan: plan,
                    projectTitle: job.title,
                    subtitle: orderLayoutSubtitle(for: plan)
                )

                layoutSection
            } else {
                // No cut plan to order against, but the job still has a
                // disposition worth recording — a drawing-less job can be
                // handled entirely off the shop rack.
                pageSection(title: "SOURCE") { sourceControl }
            }
        }
    }

    // MARK: Source

    /// WHERE this job's material comes from. It sits at the head of the ORDER
    /// section, immediately above the quantity it governs, so its consequence is
    /// visible in the same glance — and it does not add a step to the common
    /// path, which is a page full of jobs that are all being ordered.
    private var sourceControl: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                ForEach(VinylOrderDisposition.allCases, id: \.self) { option in
                    Button {
                        selectSource(option)
                    } label: {
                        Text(option.sourceLabel)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(
                                option == state.disposition
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(
                                option == state.disposition
                                    ? OPSStyle.Colors.surfaceActive
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == state.disposition ? [.isSelected] : [])
                }
            }
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )

            if state.disposition == .shop {
                Text("Stays off the supplier message. Recorded as pulled from the shop.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectSource(_ option: VinylOrderDisposition) {
        guard option != state.disposition else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(OPSStyle.Animation.panel) {
            state.disposition = option
            if option == .shop {
                // Nothing is being bought for this job.
                state.orderedSqFtOverride = 0
                state.orderedRollsOverride = 0
            } else {
                // Back to the calculator's numbers rather than leaving the
                // operator with zeros to rebuild by hand.
                state.orderedSqFtOverride = nil
                state.orderedRollsOverride = nil
            }
        }
    }

    private func degenerateBanner(_ reason: VinylBulkOrderJob.DegenerateReason) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.alert)
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            Text(reason.label)
                .font(OPSStyle.Typography.captionBold)
                .tracking(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(OPSStyle.Colors.warningStatus)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.warningStatus.opacity(OPSStyle.Layout.Opacity.subtle))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    OPSStyle.Colors.warningStatus.opacity(OPSStyle.Layout.Opacity.medium),
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: Color

    private var colorSection: some View {
        pageSection(title: "COLOR") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if !catalogChoices.isEmpty {
                    catalogPickers
                }
                if selectedChoice == nil {
                    freeTextColorField
                }
            }
        }
    }

    private var catalogPickers: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            pickerRow(label: "PRODUCT", selection: Binding(
                get: { state.vinylSettings.catalogItemId ?? "" },
                set: { newValue in
                    state.vinylSettings.catalogItemId = newValue.isEmpty ? nil : newValue
                    state.vinylSettings.catalogVariantId = nil
                    if newValue.isEmpty { state.vinylSettings.color = "" }
                }
            )) {
                Text("FIELD TEXT").tag("")
                ForEach(catalogChoices) { choice in
                    Text(choice.item.name.uppercased()).tag(choice.id)
                }
            }

            if let choice = selectedChoice {
                pickerRow(label: "VARIANT", selection: Binding(
                    get: { state.vinylSettings.catalogVariantId ?? "" },
                    set: { newValue in
                        guard !newValue.isEmpty,
                              let variant = choice.variants.first(where: { $0.id == newValue }) else {
                            state.vinylSettings.catalogVariantId = nil
                            state.vinylSettings.color = ""
                            return
                        }
                        state.vinylSettings.catalogVariantId = variant.id
                        state.vinylSettings.color = VinylCatalogSelection.variantDisplayName(
                            variant,
                            optionValues: optionValues,
                            variantOptionValues: variantOptionValues
                        )
                    }
                )) {
                    Text("SELECT").tag("")
                    ForEach(choice.variants) { variant in
                        Text(
                            VinylCatalogSelection.variantDisplayName(
                                variant,
                                optionValues: optionValues,
                                variantOptionValues: variantOptionValues
                            ).uppercased()
                        )
                        .tag(variant.id)
                    }
                }
            }
        }
    }

    private func pickerRow<PickerContent: View>(
        label: String,
        selection: Binding<String>,
        @ViewBuilder content: () -> PickerContent
    ) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5, alignment: .leading)

            Picker(label, selection: selection) {
                content()
            }
            .pickerStyle(.menu)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    private var freeTextColorField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("COLOR")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5, alignment: .leading)
            TextField("FIELD CONFIRM", text: $state.vinylSettings.color)
                .font(OPSStyle.Typography.body)
                .textInputAutocapitalization(.words)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    // MARK: PO

    private var poSection: some View {
        pageSection(title: "PO") {
            TextField("PO", text: $state.po)
                .font(OPSStyle.Typography.body)
                .textInputAutocapitalization(.words)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    // MARK: Cuts

    /// What is actually being ordered for this job — the wizard's per-job
    /// "overwrite the calculated list" step.
    ///
    /// The calculation opens the section; the operator can move it. The itemized
    /// cut lines stay below, unedited, because they are the on-site CUTTING
    /// GUIDE (geometry), not an order quantity — editing them would change what
    /// the crew cuts, which is not what a purchasing correction means.
    ///
    /// Flashing and glue deliberately do NOT appear here. Their whole value in a
    /// bulk run is cross-job batching — sticks summed across every job, then one
    /// round-up to tubes — so they are confirmed once on the send page and
    /// recorded against every job that shared them.
    private func orderSection(_ plan: VinylCutPlan) -> some View {
        let isRollMode = state.materialsSettings.orderMode == .fullRolls
        let packingPlan = VinylRollPacker.packingPlan(
            stripLengthsFeet: plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12.0 },
            rollLengthFeet: state.materialsSettings.fullRollLengthFeet
        )
        let calculatedRolls = packingPlan.rolls.count
        let calculatedSqFt = plan.totalOrderedSqFt

        return pageSection(title: "ORDER") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                sourceControl

                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: OPSStyle.Layout.Border.standard)

                if isRollMode {
                    OPSCounterRow(
                        label: "ROLLS",
                        value: Binding(
                            get: { state.orderedRollsOverride ?? calculatedRolls },
                            set: { state.orderedRollsOverride = $0 }
                        ),
                        range: 0...500,
                        support: quantitySupport(
                            calculated: calculatedRolls,
                            current: state.orderedRollsOverride ?? calculatedRolls,
                            suffix: "@ \(Int(state.materialsSettings.fullRollLengthFeet))' × \(vinylFormatInches(state.vinylSettings.rollWidthInches))"
                        )
                    )
                    VinylRollUtilizationView(plan: packingPlan)
                    if !packingPlan.overlengthStripLengthsFeet.isEmpty {
                        overlengthWarning(count: packingPlan.overlengthStripLengthsFeet.count)
                    }
                } else {
                    OPSCounterRow(
                        label: "ORDER SQ FT",
                        value: Binding(
                            get: { state.orderedSqFtOverride ?? calculatedSqFt },
                            set: { state.orderedSqFtOverride = $0 }
                        ),
                        range: 0...20000,
                        step: 5,
                        support: quantitySupport(
                            calculated: calculatedSqFt,
                            current: state.orderedSqFtOverride ?? calculatedSqFt,
                            suffix: nil
                        )
                    )
                }

                Text("// CUT LIST")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .tracking(1.1)
                    .padding(.top, OPSStyle.Layout.spacing1)

                ForEach(VinylCutGroup.groups(from: plan.surfaces.flatMap(\.purchasedCuts))) { group in
                    Text(group.displayLine)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .monospacedDigit()
                }
            }
        }
    }

    /// The support line under a quantity: the calculated value once the operator
    /// has moved off it, plus any fixed unit note. An untouched line stays quiet
    /// rather than restating its own number back at the reader.
    private func quantitySupport(calculated: Int, current: Int, suffix: String?) -> String? {
        var parts: [String] = []
        if current != calculated { parts.append("CALC \(calculated)") }
        if let suffix { parts.append(suffix) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func orderLayoutSubtitle(for plan: VinylCutPlan) -> String {
        if state.materialsSettings.orderMode == .fullRolls {
            let packingPlan = VinylRollPacker.packingPlan(
                stripLengthsFeet: plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12.0 },
                rollLengthFeet: state.materialsSettings.fullRollLengthFeet
            )
            return "\(packingPlan.rolls.count) ROLL\(packingPlan.rolls.count == 1 ? "" : "S")"
        }
        return "\(plan.totalStripCount) CUT\(plan.totalStripCount == 1 ? "" : "S")"
    }

    private func overlengthWarning(count: Int) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.alert)
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            Text("CUT LONGER THAN ROLL · \(count)")
                .font(OPSStyle.Typography.captionBold)
            Spacer(minLength: 0)
        }
        .foregroundColor(OPSStyle.Colors.warningStatus)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.warningStatus.opacity(OPSStyle.Layout.Opacity.subtle))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    OPSStyle.Colors.warningStatus.opacity(OPSStyle.Layout.Opacity.medium),
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: Layout (collapsed by default)

    private var layoutSection: some View {
        pageSection(title: "LAYOUT") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Button {
                    withAnimation(OPSStyle.Animation.panel) { state.showLayout.toggle() }
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(state.showLayout ? "HIDE LAYOUT" : "EDIT LAYOUT")
                            .font(OPSStyle.Typography.buttonLabel)
                        Spacer(minLength: 0)
                        Image(systemName: state.showLayout ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                }
                .buttonStyle(.plain)

                if state.showLayout {
                    segmentRow(label: "RUN", options: VinylLayoutDirection.allCases, selected: state.vinylSettings.direction, optionLabel: \.label) { direction in
                        state.vinylSettings.direction = direction
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onPlanInputChange()
                    }

                    segmentRow(label: "PATTERN", options: VinylPatternMode.allCases, selected: state.vinylSettings.patternMode, optionLabel: \.label) { mode in
                        state.vinylSettings.patternMode = mode
                        if mode == .linear { state.vinylSettings.allowsDirectionalChanges = false }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onPlanInputChange()
                    }

                    settingStepper(label: "ROLL", value: Binding(
                        get: { state.vinylSettings.rollWidthInches },
                        set: { state.vinylSettings.rollWidthInches = $0; onPlanInputChange() }
                    ), range: 24...144, step: 6, formatted: vinylFormatInches(state.vinylSettings.rollWidthInches))

                    settingStepper(label: "SEAM", value: Binding(
                        get: { state.vinylSettings.seamOverlapInches },
                        set: { state.vinylSettings.seamOverlapInches = $0; onPlanInputChange() }
                    ), range: 0...12, step: 0.25, formatted: vinylFormatInches(state.vinylSettings.seamOverlapInches))

                    settingStepper(label: "WRAP", value: Binding(
                        get: { state.vinylSettings.edgeWrapInches },
                        set: { state.vinylSettings.edgeWrapInches = $0; onPlanInputChange() }
                    ), range: 0...18, step: 0.5, formatted: vinylFormatInches(state.vinylSettings.edgeWrapInches))

                    segmentRow(label: "ORDER", options: VinylOrderMode.allCases, selected: state.materialsSettings.orderMode, optionLabel: \.presetLabel) { mode in
                        state.materialsSettings.orderMode = mode
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                    if state.materialsSettings.orderMode == .fullRolls {
                        settingStepper(label: "ROLL LENGTH", value: Binding(
                            get: { state.materialsSettings.fullRollLengthFeet },
                            set: { state.materialsSettings.fullRollLengthFeet = $0 }
                        ), range: 25...300, step: 5, formatted: "\(Int(state.materialsSettings.fullRollLengthFeet))'")
                    }
                }
            }
        }
    }

    private func segmentRow<Option: Hashable>(
        label: String,
        options: [Option],
        selected: Option,
        optionLabel: KeyPath<Option, String>,
        onSelect: @escaping (Option) -> Void
    ) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Text(option[keyPath: optionLabel])
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(option == selected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(option == selected ? OPSStyle.Colors.surfaceActive : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private func settingStepper(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formatted: String
    ) -> some View {
        OPSCounterRow(
            label: label,
            value: formatted,
            canDecrement: value.wrappedValue > range.lowerBound,
            canIncrement: value.wrappedValue < range.upperBound,
            onDecrement: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) },
            onIncrement: { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) }
        )
    }

    private func pageSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

// MARK: - Consumables + send page

/// Seam for the bulk-order summary rail row. Conformed to by
/// `NotificationRepository` (the `notify_vinyl_bulk_ordered` RPC); tests
/// substitute a spy.
protocol VinylBulkOrderedNotifying {
    @discardableResult
    func notifyVinylBulkOrdered(markedCount: Int) async throws -> String
}

extension NotificationRepository: VinylBulkOrderedNotifying {}

/// ONE summary row per bulk run — never one per job (spec § 12.9). The server
/// stamps the date from its own clock, so the run hands over nothing but the
/// count. The jobs are already marked ordered by the time this runs, so a
/// failed row is contained.
enum VinylBulkOrderNotificationDispatcher {
    static func dispatchSummary(
        markedCount: Int,
        syncer: VinylBulkOrderedNotifying = NotificationRepository.shared
    ) async {
        do {
            _ = try await syncer.notifyVinylBulkOrdered(markedCount: markedCount)
        } catch {
            print("[VinylBulkOrderSendPageView] summary notification failed: \(error)")
        }
    }
}

struct VinylBulkOrderSendPageView: View {
    let context: VinylBulkOrderWizardContext
    let sections: [VinylBulkOrderSection]
    let needs: [VinylConsumableNeed]
    /// Builds the commit items, given the operator's FINAL purchased consumable
    /// counts — the numbers they nudged on this page, which are what actually
    /// get bought and therefore what belongs in each job's record.
    let makeCommitItems: ([VinylSharedConsumable.Kind: Int]) -> [VinylBulkMarkItem]
    let onBack: () -> Void
    let onCommitted: (VinylBulkMarkOutcome, [VinylBulkMarkItem]) -> Void

    @EnvironmentObject private var dataController: DataController

    @AppStorage(VinylBulkOrderComposer.clipPerTubeStorageKey)
    private var clipPerTube = VinylBulkOrderComposer.defaultClipPerTube
    @AppStorage(VinylBulkOrderComposer.flashingPerTubeStorageKey)
    private var flashingPerTube = VinylBulkOrderComposer.defaultFlashingPerTube
    @AppStorage(VinylBulkOrderComposer.sectionTemplateStorageKey)
    private var sectionTemplate = VinylBulkOrderComposer.defaultSectionTemplate
    @AppStorage(VinylCutListTextTemplate.separatorStorageKey)
    private var cutSeparatorRawValue = VinylCutListSeparator.lines.rawValue

    @State private var dripTubes = 0
    @State private var ninetyTubes = 0
    @State private var clipTubes = 0
    @State private var glueBuckets = 0
    @State private var didSeedCounts = false
    @State private var showingTemplateEditor = false
    @State private var showingMessageComposer = false
    @State private var showingCopyConfirm = false
    @State private var isCommitting = false
    @State private var commitError = false

    private var suggestion: VinylConsumablesSuggestion {
        VinylConsumablesAggregator.suggest(
            needs: needs,
            clipPerTube: clipPerTube,
            flashingPerTube: flashingPerTube
        )
    }

    private var cutSeparator: VinylCutListSeparator {
        VinylCutListSeparator(rawValue: cutSeparatorRawValue) ?? .lines
    }

    /// The live message: confirmed sections + the operator's stepper values.
    private var messageText: String {
        var edited = suggestion
        edited.dripTubes = dripTubes
        edited.ninetyTubes = ninetyTubes
        edited.clipTubes = clipTubes
        edited.glueBuckets = glueBuckets
        return VinylBulkOrderComposer.compose(
            sections: sections,
            consumables: edited,
            sectionTemplate: sectionTemplate,
            cutSeparator: cutSeparator
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    consumablesSection
                    messageSection
                    Color.clear.frame(height: OPSStyle.Layout.touchTargetLarge * 2)
                }
                .padding(OPSStyle.Layout.spacing3)
            }

            sendActionBar
        }
        .task { seedCountsIfNeeded() }
        .sheet(isPresented: $showingMessageComposer) {
            VinylOrderMessageComposeView(
                body: messageText,
                onCompletion: { result in
                    showingMessageComposer = false
                    if result == .sent {
                        commitAll()
                    }
                }
            )
        }
        .confirmationDialog(
            "COPIED. MARK \(sections.count) ORDERED?",
            isPresented: $showingCopyConfirm,
            titleVisibility: .visible
        ) {
            Button("MARK ORDERED") { commitAll() }
            Button("CANCEL", role: .cancel) {}
        }
    }

    // MARK: Consumables

    private var consumablesSection: some View {
        sendSection(title: "FLASHING + GLUE") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                consumableRow(
                    label: "DRIP EDGE",
                    count: $dripTubes,
                    unit: "TUBE",
                    support: "NEED \(suggestion.totalDripSticks) STICKS"
                )
                consumableRow(
                    label: "90 FLASH",
                    count: $ninetyTubes,
                    unit: "TUBE",
                    support: "NEED \(suggestion.totalNinetySticks) STICKS"
                )
                consumableRow(
                    label: "CLIP",
                    count: $clipTubes,
                    unit: "TUBE",
                    support: "NEED \(suggestion.totalClipSticks) STICKS"
                )
                consumableRow(
                    label: "GLUE",
                    count: $glueBuckets,
                    unit: "BUCKET",
                    support: "NEED \(formattedBuckets(suggestion.exactGlueBuckets)) BUCKETS"
                )

                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: OPSStyle.Layout.Border.standard)
                    .padding(.vertical, OPSStyle.Layout.spacing1)

                tubeConfigStepper(label: "CLIP PER TUBE", value: $clipPerTube)
                tubeConfigStepper(label: "FLASHING PER TUBE", value: $flashingPerTube)
            }
        }
    }

    private func consumableRow(
        label: String,
        count: Binding<Int>,
        unit: String,
        support: String
    ) -> some View {
        OPSCounterRow(
            label: label,
            value: count,
            range: 0...200,
            unit: count.wrappedValue == 1 ? unit : "\(unit)S",
            support: support
        )
    }

    private func tubeConfigStepper(label: String, value: Binding<Int>) -> some View {
        OPSCounterRow(label: label, value: value, range: 1...200)
            .onChange(of: value.wrappedValue) { _, _ in reseedSuggestedCounts() }
    }

    private func formattedBuckets(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func seedCountsIfNeeded() {
        guard !didSeedCounts else { return }
        didSeedCounts = true
        reseedSuggestedCounts()
    }

    /// Steppers seed from the aggregator; a tube-capacity change re-suggests
    /// (the operator owns any further nudges).
    private func reseedSuggestedCounts() {
        let s = suggestion
        dripTubes = s.dripTubes
        ninetyTubes = s.ninetyTubes
        clipTubes = s.clipTubes
        glueBuckets = s.glueBuckets
    }

    // MARK: Message

    private var messageSection: some View {
        sendSection(title: "ORDER MESSAGE") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                ScrollView {
                    Text(messageText)
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OPSStyle.Layout.spacing2)
                }
                .frame(maxHeight: OPSStyle.Layout.touchTargetLarge * 4)
                .background(OPSStyle.Colors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))

                Button {
                    withAnimation(OPSStyle.Animation.panel) { showingTemplateEditor.toggle() }
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        Text(showingTemplateEditor ? "HIDE TEMPLATE" : "EDIT TEMPLATE")
                            .font(OPSStyle.Typography.buttonLabel)
                        Spacer(minLength: 0)
                        Image(systemName: showingTemplateEditor ? "chevron.up" : "chevron.down")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                }
                .buttonStyle(.plain)

                if showingTemplateEditor {
                    templateEditor
                }
            }
        }
    }

    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("SECTION")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            TextEditor(text: $sectionTemplate)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .padding(OPSStyle.Layout.spacing2)
                .frame(minHeight: OPSStyle.Layout.touchTargetLarge * 2)
                .background(OPSStyle.Colors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("SECTION: [project] [color] [cuts]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)
                Button("RESET") {
                    sectionTemplate = VinylBulkOrderComposer.defaultSectionTemplate
                }
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Send + commit

    private var sendActionBar: some View {
        OPSFloatingButtonBar(
            horizontalPadding: OPSStyle.Layout.spacing3,
            verticalPadding: OPSStyle.Layout.spacing2
        ) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button("BACK") {
                    onBack()
                }
                .opsSecondaryButtonStyle()
                .disabled(isCommitting)

                Button {
                    handleSendAction()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if isCommitting {
                            ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        } else {
                            Image(systemName: OPSStyle.Icons.message)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        }
                        Text(MFMessageComposeViewController.canSendText() ? "TEXT ORDER" : "COPY ORDER")
                    }
                }
                .opsPrimaryButtonStyle(isDisabled: sections.isEmpty || isCommitting)
                .disabled(sections.isEmpty || isCommitting)
            }
        }
    }

    private func handleSendAction() {
        if MFMessageComposeViewController.canSendText() {
            showingMessageComposer = true
        } else {
            UIPasteboard.general.string = messageText
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showingCopyConfirm = true
        }
    }

    /// Commit every confirmed job through the bulk mark service, then one
    /// summary notification — never n (spec § 12.9).
    /// The operator's final counts, keyed for attribution back to each job.
    private var purchasedConsumables: [VinylSharedConsumable.Kind: Int] {
        [
            .dripEdge: dripTubes,
            .ninetyFlash: ninetyTubes,
            .clip: clipTubes,
            .glue: glueBuckets
        ]
    }

    private func commitAll() {
        guard let userId = context.userId, !isCommitting else { return }
        isCommitting = true

        let items = makeCommitItems(purchasedConsumables)
        let companyId = context.companyId
        let controller = dataController
        let service = VinylBulkMarkService(
            userId: userId,
            updateProjectFields: { pid, fields in
                try await dataController.updateProjectFields(projectId: pid, fields: fields)
            },
            recordActivity: { item, record in
                VinylOrderActivityRecorder.record(
                    projectId: item.projectId,
                    companyId: companyId,
                    authorId: userId,
                    record: record,
                    dataController: controller
                )
            }
        )
        Task { @MainActor in
            let outcome = await service.markOrdered(items: items)
            // ONE summary notification whenever anything marked (spec § 12.9) —
            // a partial failure still ordered the succeeded jobs.
            if !outcome.succeeded.isEmpty {
                await VinylBulkOrderNotificationDispatcher.dispatchSummary(
                    markedCount: outcome.succeeded.count
                )
            }
            UINotificationFeedbackGenerator().notificationOccurred(outcome.failed.isEmpty ? .success : .warning)
            isCommitting = false
            let failedItems = items.filter { outcome.failed.contains($0.projectId) }
            onCommitted(outcome, failedItems)
        }
    }

    private func sendSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}
