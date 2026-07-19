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
//  Page state is session-local exactly like the single-project order sheet:
//  color/catalog picks write through to the design config on CONFIRM, order
//  mode + roll length persist to materialsSettings, and whatever layout is
//  live at send freezes into each job's snapshot.
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

/// Editable per-page state. Direction/width/seam stay session-transient
/// (parity with the order sheet); order mode + roll length write through to
/// the design's materialsSettings at CONFIRM.
private struct VinylWizardPageState {
    var vinylSettings: VinylOrderSettings
    var materialsSettings: DeckMaterialsSettings
    var po: String
    var confirmed = false
    var showLayout = false
    var plan: VinylCutPlan?
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
                    VStack(spacing: 0) {
                        wizardHeader

                        if onSendPage {
                            VinylBulkOrderSendPageView(
                                context: context,
                                sections: confirmedSections,
                                needs: confirmedNeeds,
                                makeCommitItems: { commitItems() },
                                onBack: { withAnimation(OPSStyle.Animation.page) { pageIndex = max(0, jobs.count - 1) } },
                                onCommitted: { outcome, failedItems in onCommitted(outcome, failedItems) }
                            )
                        } else {
                            pageBody
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        VStack(alignment: .leading, spacing: 3) {
            Text(onSendPage ? "ORDER · SEND" : "ORDER · \(pageIndex + 1) OF \(jobs.count)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            Text(onSendPage ? "FLASHING + GLUE + MESSAGE" : jobs[pageIndex].title.uppercased())
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Per-job page

    private var pageBody: some View {
        let job = jobs[pageIndex]
        return VStack(spacing: 0) {
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

            pageActionBar(job)
        }
    }

    private func pageActionBar(_ job: VinylBulkOrderJob) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                withAnimation(OPSStyle.Animation.page) {
                    if pageIndex > 0 { pageIndex -= 1 }
                }
            } label: {
                Text("BACK")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(.plain)
            .disabled(pageIndex == 0)
            .opacity(pageIndex == 0 ? 0.45 : 1)

            Button {
                confirmPage(at: pageIndex)
            } label: {
                Text("CONFIRM")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.background)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(canConfirmCurrentPage ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(!canConfirmCurrentPage)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background.opacity(0.96))
    }

    private var canConfirmCurrentPage: Bool {
        guard pageIndex < pageStates.count else { return false }
        return !pageStates[pageIndex].vinylSettings.color
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    /// Persist the page's color/catalog pick + order mode to the design so a
    /// later sheet open restores it — the exact fields the order sheet writes,
    /// through the same drawingData accessor discipline (no view model).
    private func writeThroughConfig(at index: Int) {
        let job = jobs[index]
        guard let design = job.design else { return }
        let state = pageStates[index]

        var data = design.drawingData
        let trimmedColor = state.vinylSettings.color.trimmingCharacters(in: .whitespacesAndNewlines)
        let newColor = trimmedColor.isEmpty ? nil : trimmedColor
        let newVariantId = state.vinylSettings.catalogVariantId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newItemId = state.vinylSettings.catalogItemId?.trimmingCharacters(in: .whitespacesAndNewlines)

        var materialsSettings = data.materialsSettings ?? DeckMaterialsSettings()
        let settingsChanged = materialsSettings.orderMode != state.materialsSettings.orderMode
            || materialsSettings.fullRollLengthFeet != state.materialsSettings.fullRollLengthFeet
        materialsSettings.orderMode = state.materialsSettings.orderMode
        materialsSettings.fullRollLengthFeet = state.materialsSettings.fullRollLengthFeet

        let configChanged = data.config.vinylColor != newColor
            || data.config.vinylCatalogVariantId != ((newVariantId?.isEmpty ?? true) ? nil : newVariantId)
            || data.config.vinylCatalogItemId != ((newItemId?.isEmpty ?? true) ? nil : newItemId)

        guard configChanged || settingsChanged else { return }
        data.config.vinylColor = newColor
        data.config.vinylCatalogVariantId = (newVariantId?.isEmpty ?? true) ? nil : newVariantId
        data.config.vinylCatalogItemId = (newItemId?.isEmpty ?? true) ? nil : newItemId
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
                let restored = VinylCatalogSelection.restoredSelection(
                    configItemId: data.config.vinylCatalogItemId?.trimmingCharacters(in: .whitespacesAndNewlines),
                    configVariantId: data.config.vinylCatalogVariantId,
                    configColor: data.config.vinylColor,
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
            .filter { _, state in state.confirmed }
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
                    let rolls = "\(pack.rollCount) ROLL\(pack.rollCount == 1 ? "" : "S") @ \(Int(state.materialsSettings.fullRollLengthFeet))' × \(vinylFormatInches(state.vinylSettings.rollWidthInches))"
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
    /// page's confirmed settings; degenerate jobs contribute nothing.
    private var confirmedNeeds: [VinylConsumableNeed] {
        zip(jobs, pageStates)
            .filter { job, state in state.confirmed && job.degenerateReason == nil }
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
    private func commitItems() -> [VinylBulkMarkItem] {
        zip(jobs, pageStates)
            .filter { _, state in state.confirmed }
            .map { job, state in
                let color = state.vinylSettings.color.trimmingCharacters(in: .whitespacesAndNewlines)
                let po = state.po.trimmingCharacters(in: .whitespacesAndNewlines)

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
                        po: po.isEmpty ? nil : po
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
                    po: po.isEmpty ? nil : po
                )
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
                cutsSection(plan)

                VinylCutPreview(plan: plan)
                    .frame(height: OPSStyle.Layout.touchTargetLarge * 3)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )

                layoutSection
            }
        }
    }

    private func degenerateBanner(_ reason: VinylBulkOrderJob.DegenerateReason) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            Text(reason.label)
                .font(OPSStyle.Typography.captionBold)
                .tracking(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(OPSStyle.Colors.warningStatus)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.warningStatus.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.45), lineWidth: OPSStyle.Layout.Border.standard)
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
        VStack(spacing: OPSStyle.Layout.spacing2) {
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

            if state.vinylSettings.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    state.vinylSettings.color = "FIELD CONFIRM"
                } label: {
                    Text("USE FIELD CONFIRM")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .buttonStyle(.plain)
            }
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

    private func cutsSection(_ plan: VinylCutPlan) -> some View {
        pageSection(title: "CUTS") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                if state.materialsSettings.orderMode == .fullRolls {
                    let pack = VinylRollPacker.rollsNeeded(
                        stripLengthsFeet: plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12.0 },
                        rollLengthFeet: state.materialsSettings.fullRollLengthFeet
                    )
                    metricRow("ROLLS", "\(pack.rollCount) @ \(Int(state.materialsSettings.fullRollLengthFeet))' × \(vinylFormatInches(state.vinylSettings.rollWidthInches))")
                }
                metricRow("ORDER AREA", "\(plan.totalOrderedSqFt) SQ FT")

                ForEach(VinylCutGroup.groups(from: plan.surfaces.flatMap(\.purchasedCuts))) { group in
                    Text(group.displayLine)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
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
                        Image(systemName: state.showLayout ? "chevron.up" : "chevron.down")
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
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5, alignment: .leading)
                Text(formatted)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 0)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer(minLength: 0)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.trailing)
        }
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

struct VinylBulkOrderSendPageView: View {
    let context: VinylBulkOrderWizardContext
    let sections: [VinylBulkOrderSection]
    let needs: [VinylConsumableNeed]
    let makeCommitItems: () -> [VinylBulkMarkItem]
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
        VStack(spacing: 0) {
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
        Stepper(value: count, in: 0...200) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(support)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                Spacer(minLength: 0)
                Text("\(count.wrappedValue) \(unit)\(count.wrappedValue == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(count.wrappedValue == 0 ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    private func tubeConfigStepper(label: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 1...200) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)
                Text("\(value.wrappedValue)")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
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
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                onBack()
            } label: {
                Text("BACK")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isCommitting)

            Button {
                handleSendAction()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if isCommitting {
                        ProgressView().tint(OPSStyle.Colors.background)
                    } else {
                        Image(systemName: "message.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    }
                    Text(MFMessageComposeViewController.canSendText() ? "TEXT ORDER" : "COPY ORDER")
                        .font(OPSStyle.Typography.buttonLabel)
                }
                .foregroundColor(OPSStyle.Colors.background)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(sections.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(sections.isEmpty || isCommitting)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background.opacity(0.96))
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
    private func commitAll() {
        guard let userId = context.userId, !isCommitting else { return }
        isCommitting = true

        let items = makeCommitItems()
        let service = VinylBulkMarkService(userId: userId) { pid, fields in
            try await dataController.updateProjectFields(projectId: pid, fields: fields)
        }
        Task { @MainActor in
            let outcome = await service.markOrdered(items: items)
            // ONE summary notification whenever anything marked (spec § 12.9) —
            // a partial failure still ordered the succeeded jobs.
            if !outcome.succeeded.isEmpty {
                await postSummaryNotification(markedCount: outcome.succeeded.count)
            }
            UINotificationFeedbackGenerator().notificationOccurred(outcome.failed.isEmpty ? .success : .warning)
            isCommitting = false
            let failedItems = items.filter { outcome.failed.contains($0.projectId) }
            onCommitted(outcome, failedItems)
        }
    }

    private func postSummaryNotification(markedCount: Int) async {
        guard let userId = context.userId else { return }
        do {
            try await NotificationRepository.shared.createNotification(
                NotificationRepository.CreateNotificationDTO(
                    userId: userId,
                    companyId: context.companyId,
                    type: "vinyl_bulk_ordered",
                    title: "// VINYL ORDERED",
                    body: "\(markedCount) PROJECT\(markedCount == 1 ? "" : "S") · \(DateHelper.simpleDateString(from: Date()).uppercased())",
                    projectId: nil,
                    noteId: nil,
                    deepLinkType: nil,
                    persistent: false,
                    actionUrl: nil,
                    actionLabel: nil
                )
            )
        } catch {
            print("[VinylBulkOrderSendPageView] summary notification failed: \(error)")
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
