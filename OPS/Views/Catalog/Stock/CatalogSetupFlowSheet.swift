//
//  CatalogSetupFlowSheet.swift
//  OPS
//
//  Field-ready stock setup: family -> attributes -> valid matrix -> variants
//  -> physical stock units -> optional product option mappings.
//

import SwiftUI
import SwiftData

enum CatalogSetupStep: String, CaseIterable, Identifiable {
    case family = "FAMILY"
    case attributes = "ATTRIBUTES"
    case matrix = "MATRIX"
    case variants = "VARIANTS"
    case stock = "STOCK"
    case links = "LINKS"
    case review = "REVIEW"

    var id: String { rawValue }
}

struct CatalogSetupStepRailState: Equatable {
    let steps: [CatalogSetupStep]
    let selectedStep: CatalogSetupStep

    init(
        steps: [CatalogSetupStep] = CatalogSetupStep.allCases,
        selectedStep: CatalogSetupStep
    ) {
        self.steps = steps
        self.selectedStep = selectedStep
    }

    var selectedIndex: Int {
        steps.firstIndex(of: selectedStep) ?? 0
    }

    var progressText: String {
        "\(selectedIndex + 1)/\(steps.count)"
    }

    var previousStep: CatalogSetupStep? {
        guard selectedIndex > 0 else { return nil }
        return steps[selectedIndex - 1]
    }

    var nextStep: CatalogSetupStep? {
        guard selectedIndex + 1 < steps.count else { return nil }
        return steps[selectedIndex + 1]
    }
}

enum CatalogSetupLocalReconciliationError: LocalizedError, Equatable {
    case missingServerId(clientId: String)
    case missingVariantReference(stockUnitClientId: String)
    case missingProductReference(clientId: String)

    var errorDescription: String? {
        switch self {
        case .missingServerId(let clientId):
            return "Server save response did not include an id for \(clientId)."
        case .missingVariantReference(let stockUnitClientId):
            return "Server save response did not include a variant id for stock unit \(stockUnitClientId)."
        case .missingProductReference(let clientId):
            return "Server save response did not include a product id for \(clientId)."
        }
    }
}

struct CatalogSetupFlowSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var permissionStore = PermissionStore.shared

    @Query private var allFamilies: [CatalogItem]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]
    @Query private var allStockUnits: [CatalogStockUnit]
    @Query private var allProducts: [Product]
    @Query private var allProductOptions: [ProductOption]
    @Query private var allProductOptionValues: [ProductOptionValue]
    @Query private var allProductPricingModifiers: [ProductPricingModifier]
    @Query private var allProductMaterials: [ProductMaterial]
    @Query private var allProductBundleItems: [ProductBundleItem]
    @Query private var allCatalogProductOptionMappings: [CatalogProductOptionMapping]

    @State private var editFamilyId: String?
    @State private var selectedStep: CatalogSetupStep = .family
    @State private var familyName: String = ""
    @State private var familyDescription: String = ""
    @State private var familyImageUrl: String = ""
    @State private var selectedCategoryId: String?
    @State private var selectedUnitId: String?
    @State private var defaultWarningText: String = ""
    @State private var defaultCriticalText: String = ""
    @State private var attributes: [CatalogSetupAttributeDraft] = [
        CatalogSetupAttributeDraft(values: [
            CatalogSetupAttributeValueDraft(),
            CatalogSetupAttributeValueDraft()
        ])
    ]
    @State private var invalidCombinations: [CatalogSetupInvalidCombination] = []
    @State private var invalidSelectionByAttributeId: [String: String] = [:]
    @State private var setupVariants: [CatalogSetupVariantDraft] = []
    @State private var generatedMatrixOnce: Bool = false
    @State private var selectedProductId: String?
    @State private var productOptionAuthoringProduct: Product?
    @State private var productOptionSelectionByAttributeId: [String: String] = [:]
    @State private var productValueSelectionByCatalogValueId: [String: String] = [:]
    @State private var catalogCapabilities: CatalogSchemaCapabilities = CatalogSchemaCapabilityGate.current
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var qaCommitMessage: String?
    @State private var setupDraftId: String = UUID().uuidString
    @State private var deletedIds: CatalogSetupDeletedIds = CatalogSetupDeletedIds()
    @State private var activeSaveAttempt: CatalogSetupSaveAttempt?
    @State private var rpcWarnings: [CatalogSetupSaveIssue] = []
    @State private var rpcBlockers: [CatalogSetupSaveIssue] = []
    @State private var stockLifecycleNoteByUnitId: [String: String] = [:]
    @State private var stockConsumeAmountByUnitId: [String: String] = [:]
    @State private var stockOffcutLengthByUnitId: [String: String] = [:]
    @State private var didAttemptDraftRestore: Bool = false
    @State private var didClearDraftAfterSuccessfulSave: Bool = false
    #if DEBUG
    @State private var didLoadQAFixtureDraft: Bool = false
    #endif

    private let draftStore: CatalogSetupDraftStore
    private let initialEditFamilyId: String?
    private let initialMissingMappingKey: String?

    init(
        existingFamily: CatalogItem? = nil,
        missingMappingKey: String? = nil,
        draftStore: CatalogSetupDraftStore = .shared
    ) {
        let editFamilyId = existingFamily?.id
        self.initialEditFamilyId = editFamilyId
        self.initialMissingMappingKey = missingMappingKey
        self.draftStore = draftStore
        _editFamilyId = State(initialValue: editFamilyId)
        _selectedStep = State(initialValue: missingMappingKey == nil ? .family : .links)
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var currentUserId: String {
        dataController.currentUser?.id ?? ""
    }

    private var canManageProducts: Bool {
        permissionStore.can("catalog.products.manage")
    }

    private var draftContext: CatalogSetupDraftContext? {
        CatalogSetupDraftContext.make(companyId: companyId, userId: currentUserId, editFamilyId: editFamilyId)
    }

    private var isEditMode: Bool {
        editFamilyId != nil
    }

    private var saveMode: String {
        isEditMode ? "edit" : "create"
    }

    private var isQAMode: Bool {
        #if DEBUG
        CatalogSetupQARuntime.isEnabled()
        #else
        false
        #endif
    }

    private var supportsProductOptionMappings: Bool {
        isQAMode || catalogCapabilities.catalogProductOptionMappings
    }

    private var supportsProductBundleRelationshipFields: Bool {
        isQAMode || catalogCapabilities.productBundleRelationshipFields
    }

    private var isOffline: Bool {
        !dataController.isConnected
    }

    private var activeAttributes: [CatalogSetupAttributeDraft] {
        attributes.compactMap { attribute in
            let name = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let values = attribute.values.compactMap { value -> CatalogSetupAttributeValueDraft? in
                let trimmed = value.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return CatalogSetupAttributeValueDraft(id: value.id, serverId: value.serverId, value: trimmed)
            }
            guard !name.isEmpty, !values.isEmpty else { return nil }
            return CatalogSetupAttributeDraft(
                id: attribute.id,
                serverId: attribute.serverId,
                name: name,
                values: values
            )
        }
    }

    private var companyCategories: [CatalogCategory] {
        allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private var companyProducts: [Product] {
        allProducts
            .filter { $0.companyId == companyId && $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedProduct: Product? {
        guard let selectedProductId else { return nil }
        return companyProducts.first { $0.id == selectedProductId }
    }

    private var selectedProductOptions: [ProductOption] {
        guard let product = selectedProduct else { return [] }
        return allProductOptions
            .filter { $0.productId == product.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var selectableProductOptions: [ProductOption] {
        selectedProductOptions.filter { $0.kind == .select }
    }

    private var selectedProductOptionValues: [ProductOptionValue] {
        let optionIds = Set(selectedProductOptions.map(\.id))
        return allProductOptionValues
            .filter { optionIds.contains($0.optionId) }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
    }

    private var enabledVariants: [CatalogSetupVariantDraft] {
        setupVariants.filter(\.isEnabled)
    }

    private var duplicateMatrixSignatures: Set<String> {
        let signatures = enabledVariants.map { CatalogSetupWorkflow.signature(for: $0.optionValueIds) }
        let grouped = Dictionary(grouping: signatures, by: { $0 })
        return Set(grouped.filter { $0.value.count > 1 }.map(\.key))
    }

    private var validationResult: CatalogVariantIdentityValidationResult {
        CatalogSetupWorkflow.validate(
            variants: enabledVariants,
            companyId: companyId,
            catalogItemId: editFamilyId ?? "__new_catalog_setup_family__",
            existingVariants: allVariants.filter { $0.companyId == companyId },
            existingOptionValues: allVariantOptionValues
        )
    }

    private var hasBlockingMatrixConflict: Bool {
        !duplicateMatrixSignatures.isEmpty || !validationResult.blockingViolations.isEmpty
    }

    private var hasDraftStockUnits: Bool {
        enabledVariants.contains { !$0.stockUnits.isEmpty }
    }

    private var productMappingViolations: [CatalogProductOptionMappingViolation] {
        guard let selectedProduct,
              supportsProductOptionMappings
        else { return [] }

        return CatalogSetupWorkflow.validateProductOptionMappingDraft(
            companyId: companyId,
            productId: selectedProduct.id,
            attributes: activeAttributes,
            productOptionSelectionByAttributeId: productOptionSelectionByAttributeId,
            productValueSelectionByCatalogValueId: productValueSelectionByCatalogValueId,
            productOptions: selectedProductOptions,
            productOptionValues: selectedProductOptionValues
        )
    }

    private var canGenerateMatrix: Bool {
        !activeAttributes.isEmpty && activeAttributes.allSatisfy { !$0.values.isEmpty }
    }

    private var hasPersistableDraftContent: Bool {
        isEditMode ||
        !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !familyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !familyImageUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        selectedCategoryId != nil ||
        selectedUnitId != nil ||
        !defaultWarningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !defaultCriticalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        attributes.contains { attribute in
            !attribute.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            attribute.values.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } ||
        !invalidCombinations.isEmpty ||
        !setupVariants.isEmpty ||
        selectedProductId != nil ||
        !productOptionSelectionByAttributeId.isEmpty ||
        !productValueSelectionByCatalogValueId.isEmpty ||
        !deletedIds.isEmpty ||
        activeSaveAttempt != nil ||
        !rpcWarnings.isEmpty ||
        !rpcBlockers.isEmpty
    }

    private var canCommit: Bool {
        let savePathReady = isQAMode || (!isOffline && (!hasDraftStockUnits || catalogCapabilities.catalogStockUnits))
        return !isSaving &&
        !companyId.isEmpty &&
        !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !enabledVariants.isEmpty &&
        !hasBlockingMatrixConflict &&
        productMappingViolations.isEmpty &&
        savePathReady
    }

    var body: some View {
        setupNavigation
            .sheet(item: $productOptionAuthoringProduct, onDismiss: {
                autoSelectProductMappings()
                persistDraft()
            }) { product in
                ProductOptionAuthoringSheet(product: product)
                    .environmentObject(dataController)
            }
    }

    private var setupNavigation: some View {
        NavigationStack {
            setupNavigationContent
        }
    }

    private var setupNavigationContent: AnyView {
        let base = AnyView(
            setupScrollContent
                .navigationTitle(isEditMode ? "EDIT STOCK SETUP" : "STOCK SETUP")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear(perform: loadPersistedDraftOrFixtureIfNeeded)
                .toolbar {
                    setupToolbar
                }
                .task(id: companyId) {
                    await refreshCatalogCapabilities()
                }
        )

        let context = AnyView(
            base
                .onChange(of: companyId) { _, _ in
                    handleDraftContextChanged()
                }
                .onChange(of: currentUserId) { _, _ in
                    handleDraftContextChanged()
                }
                .onChange(of: selectedStep) { _, _ in persistDraft() }
                .onChange(of: familyName) { _, _ in persistDraft() }
                .onChange(of: familyDescription) { _, _ in persistDraft() }
                .onChange(of: familyImageUrl) { _, _ in persistDraft() }
                .onChange(of: selectedCategoryId) { _, _ in persistDraft() }
                .onChange(of: selectedUnitId) { _, _ in persistDraft() }
        )

        let draft = AnyView(
            context
                .onChange(of: defaultWarningText) { _, _ in persistDraft() }
                .onChange(of: defaultCriticalText) { _, _ in persistDraft() }
                .onChange(of: attributes) { _, _ in persistDraft() }
                .onChange(of: invalidCombinations) { _, _ in persistDraft() }
                .onChange(of: invalidSelectionByAttributeId) { _, _ in persistDraft() }
                .onChange(of: setupVariants) { _, _ in persistDraft() }
                .onChange(of: generatedMatrixOnce) { _, _ in persistDraft() }
                .onChange(of: selectedProductId) { _, _ in persistDraft() }
        )

        return AnyView(
            draft
                .onChange(of: productOptionSelectionByAttributeId) { _, _ in persistDraft() }
                .onChange(of: productValueSelectionByCatalogValueId) { _, _ in persistDraft() }
                .onChange(of: setupDraftId) { _, _ in persistDraft() }
                .onChange(of: deletedIds) { _, _ in persistDraft() }
                .onChange(of: activeSaveAttempt) { _, _ in persistDraft() }
                .onChange(of: rpcWarnings) { _, _ in persistDraft() }
                .onChange(of: rpcBlockers) { _, _ in persistDraft() }
                .onChange(of: errorMessage) { _, _ in persistDraft() }
        )
    }

    private var setupScrollContent: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    headerBlock
                    stepRail
                    statusBlock
                    currentStepView
                }
                .padding(OPSStyle.Layout.spacing3)
            }
        }
    }

    @ToolbarContentBuilder
    private var setupToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
                .foregroundColor(OPSStyle.Colors.primaryText)
        }

        ToolbarItem(placement: .topBarTrailing) {
            commitButton
        }
    }

    private var commitButton: some View {
        Button {
            Task { await commitSetup() }
        } label: {
            commitButtonLabel
        }
        .disabled(!canCommit)
        .accessibilityLabel(commitAccessibilityLabel)
        .accessibilityHint(commitAccessibilityHint)
        .accessibilityValue(commitAccessibilityValue)
    }

    @ViewBuilder
    private var commitButtonLabel: some View {
        if isSaving {
            ProgressView().tint(OPSStyle.Colors.primaryAccent)
        } else {
            Text(isQAMode ? "QA CHECK" : (isEditMode ? "UPDATE" : "COMMIT"))
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(canCommit ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Layout

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(isEditMode ? "// EDIT STOCK SETUP" : "// STOCK SETUP")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(isEditMode
                 ? "UPDATE THE EXISTING FAMILY. Omitted rows stay untouched unless deleted."
                 : "BUILD REAL STOCK SYSTEMS FROM FAMILY, OPTIONS, UNITS, AND SELLABLE LINKS.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private var stepRailState: CatalogSetupStepRailState {
        CatalogSetupStepRailState(selectedStep: selectedStep)
    }

    private var stepRail: some View {
        let state = stepRailState

        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                stepAdvanceButton(title: "PREV", targetStep: state.previousStep)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.progressText)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .monospacedDigit()

                    Text(state.selectedStep.rawValue)
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Setup step")
                .accessibilityValue("\(state.selectedStep.rawValue), \(state.progressText)")

                stepAdvanceButton(title: "NEXT", targetStep: state.nextStep)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(state.steps) { step in
                            stepRailPill(step)
                                .id(step)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.trailing, OPSStyle.Layout.touchTargetMin)
                }
                .onAppear {
                    proxy.scrollTo(selectedStep, anchor: .center)
                }
                .onChange(of: selectedStep) { _, step in
                    proxy.scrollTo(step, anchor: .center)
                }
            }
        }
    }

    private func stepRailPill(_ step: CatalogSetupStep) -> some View {
        let isActive = selectedStep == step

        return Button {
            selectStep(step)
        } label: {
            Text(step.rawValue)
                .font(OPSStyle.Typography.category)
                .foregroundColor(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(minWidth: 76, minHeight: OPSStyle.Layout.touchTargetMin)
                .background(isActive ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(step.rawValue) step")
        .accessibilityHint("Moves the setup flow to \(step.rawValue).")
        .accessibilityValue(isActive ? "Selected" : "Not selected")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func stepAdvanceButton(title: String, targetStep: CatalogSetupStep?) -> some View {
        Button {
            if let targetStep {
                selectStep(targetStep)
            }
        } label: {
            Text(title)
                .font(OPSStyle.Typography.category)
                .foregroundColor(targetStep == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .frame(minWidth: 64, minHeight: OPSStyle.Layout.touchTargetMin)
                .background(targetStep == nil ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            targetStep == nil ? OPSStyle.Colors.cardBorder : OPSStyle.Colors.primaryAccent,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(targetStep == nil)
        .accessibilityLabel(title == "PREV" ? "Previous setup step" : "Next setup step")
        .accessibilityHint(targetStep.map { "Moves to \($0.rawValue)." } ?? "No step available.")
        .accessibilityValue(targetStep == nil ? "Locked" : "Ready")
    }

    private func selectStep(_ step: CatalogSetupStep) {
        selectedStep = step
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @ViewBuilder
    private var statusBlock: some View {
        if isQAMode {
            setupBanner(title: "QA :: LOCAL ONLY", message: "Fixture data is in memory. Save runs a no-write check.")
        }
        if isEditMode {
            setupBanner(title: "MODE :: UPDATE", message: "Existing row IDs are retained. Deleted rows require explicit delete markers.")
        }
        if initialMissingMappingKey != nil {
            setupBanner(title: "ACTION :: FIX MAPPING", message: "Open LINKS and connect product choices to stock.")
        }
        if isSaving {
            setupBanner(title: "SYS :: SAVING", message: "Saving setup in one atomic request.")
        }
        if isOffline {
            setupBanner(title: "SYS :: OFFLINE - DRAFT HELD", message: "Commit is locked until the device is back online. Draft values stay on screen.")
        }
        if let qaCommitMessage {
            setupBanner(title: "QA :: SAVE BLOCKED", message: qaCommitMessage)
        }
        if let errorMessage {
            setupBanner(title: "SYS :: SAVE BLOCKED", message: errorMessage, isError: true)
        }
        if rpcBlockers.isEmpty == false {
            setupBanner(title: "RPC :: BLOCKERS", message: "\(rpcBlockers.count) server blocker(s) preserved for review.", isError: true)
        }
        if rpcWarnings.isEmpty == false {
            setupBanner(title: "RPC :: WARNINGS", message: "\(rpcWarnings.count) server warning(s) preserved for review.")
        }
        if !validationResult.warnings.isEmpty {
            setupBanner(title: "WARN :: SKU MATCH", message: "Duplicate SKU found. Save remains available unless the option matrix is duplicated.")
        }
        if hasBlockingMatrixConflict {
            setupBanner(title: "BLOCK :: MATRIX MATCH", message: "A variant option signature is duplicated. Remove or disable the duplicate before commit.", isError: true)
        }
        if hasDraftStockUnits && !catalogCapabilities.catalogStockUnits {
            setupBanner(title: "BLOCK :: STOCK SCHEMA", message: "Stock units cannot commit on this Supabase target. No catalog rows will be created.", isError: true)
        }
        if !productMappingViolations.isEmpty {
            setupBanner(title: "BLOCK :: PRODUCT LINK", message: "A selected product value no longer belongs to the selected product option.", isError: true)
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch selectedStep {
        case .family:
            familySection
        case .attributes:
            attributesSection
        case .matrix:
            matrixSection
        case .variants:
            variantsSection
        case .stock:
            stockUnitsSection
        case .links:
            linksSection
        case .review:
            reviewSection
        }
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("FAMILY")
            CatalogFieldLabel("Name")
            TextField("", text: $familyName)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Description")
            TextField("", text: $familyDescription, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Image URL")
            TextField("", text: $familyImageUrl)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Category")
            pickerContainer {
                Picker("Category", selection: $selectedCategoryId) {
                    Text("None").tag(String?.none)
                    ForEach(companyCategories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(OPSStyle.Colors.primaryText)
            }

            CatalogFieldLabel("Default unit")
            pickerContainer {
                Picker("Unit", selection: $selectedUnitId) {
                    Text("None").tag(String?.none)
                    ForEach(companyUnits) { unit in
                        Text(unit.display).tag(Optional(unit.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(OPSStyle.Colors.primaryText)
            }

            compactAwarePair {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel("Warning")
                    TextField("", text: $defaultWarningText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(CatalogTextFieldStyle())
                }
            } second: {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel("Critical")
                    TextField("", text: $defaultCriticalText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(CatalogTextFieldStyle())
                }
            }
        }
        .setupPanel()
    }

    private var attributesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                CatalogSectionHeader("ATTRIBUTES")
                Spacer()
                Button {
                    attributes.append(CatalogSetupAttributeDraft(values: [CatalogSetupAttributeValueDraft()]))
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .accessibilityLabel("Add attribute")
                .accessibilityHint("Adds another option axis to the setup.")
            }

            if attributes.isEmpty {
                emptyState("NO ATTRIBUTES", "Add an option axis before generating variants.")
            }

            ForEach($attributes) { $attribute in
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    HStack {
                        Text("AXIS")
                            .font(OPSStyle.Typography.category)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                        Button {
                            removeAttribute(attribute.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(OPSStyle.Colors.errorText)
                                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        }
                        .accessibilityLabel("Remove attribute")
                        .accessibilityHint(attribute.name.isEmpty ? "Removes this option axis." : "Removes \(attribute.name).")
                    }

                    CatalogFieldLabel("Name")
                    TextField("", text: $attribute.name)
                        .textFieldStyle(CatalogTextFieldStyle())

                    CatalogFieldLabel("Values")
                    ForEach($attribute.values) { $value in
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            TextField("", text: $value.value)
                                .textFieldStyle(CatalogTextFieldStyle())
                            Button {
                                removeValue(value.id, from: attribute.id)
                            } label: {
                                Image(systemName: "minus")
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                            }
                            .accessibilityLabel("Remove value")
                            .accessibilityHint(value.value.isEmpty ? "Removes this attribute value." : "Removes \(value.value).")
                        }
                    }

                    Button {
                        appendValue(to: attribute.id)
                    } label: {
                        Label("ADD VALUE", systemImage: "plus")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                    .accessibilityLabel("Add value")
                    .accessibilityHint(attribute.name.isEmpty ? "Adds a value to this option axis." : "Adds a value to \(attribute.name).")
                }
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
        }
        .setupPanel()
    }

    private var matrixSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                CatalogSectionHeader("VALID MATRIX")
                Spacer()
                Button {
                    regenerateMatrix()
                } label: {
                    Label("GENERATE", systemImage: "square.grid.3x3")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(canGenerateMatrix ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .disabled(!canGenerateMatrix)
                .accessibilityLabel("Generate variant matrix")
                .accessibilityHint(canGenerateMatrix ? "Creates valid variant rows from the current attributes." : "Add named attributes and values first.")
                .accessibilityValue(canGenerateMatrix ? "Ready" : "Locked")
            }

            if !canGenerateMatrix {
                emptyState("NO MATRIX", "Add named attributes and values first.")
            } else {
                invalidCombinationBuilder
            }

            if generatedMatrixOnce {
                matrixSummaryRows
            }
        }
        .setupPanel()
    }

    private var invalidCombinationBuilder: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("MARK INVALID COMBINATIONS BEFORE VARIANTS EXIST.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            ForEach(activeAttributes) { attribute in
                CatalogFieldLabel(attribute.name)
                pickerContainer {
                    Picker(attribute.name, selection: Binding(
                        get: { invalidSelectionByAttributeId[attribute.id] ?? "" },
                        set: { value in
                            if value.isEmpty {
                                invalidSelectionByAttributeId.removeValue(forKey: attribute.id)
                            } else {
                                invalidSelectionByAttributeId[attribute.id] = value
                            }
                        }
                    )) {
                        Text("Any").tag("")
                        ForEach(attribute.values) { value in
                            Text(value.value).tag(value.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(OPSStyle.Colors.primaryText)
                }
            }

            Button {
                addInvalidCombination()
            } label: {
                Label("BLOCK SELECTED COMBO", systemImage: "nosign")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(canAddInvalidCombination ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(!canAddInvalidCombination)
            .accessibilityLabel("Block selected combination")
            .accessibilityHint(canAddInvalidCombination ? "Marks the selected catalog values as an invalid variant combination." : "Select at least one catalog value first.")
            .accessibilityValue(canAddInvalidCombination ? "Ready" : "Locked")

            if invalidCombinations.isEmpty {
                Text("NO INVALID COMBOS MARKED")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(invalidCombinations) { combo in
                    HStack {
                        Text(label(for: combo.valueIds))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        Button {
                            invalidCombinations.removeAll { $0.id == combo.id }
                            if generatedMatrixOnce { regenerateMatrix() }
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        }
                        .accessibilityLabel("Remove invalid combination")
                        .accessibilityValue(label(for: combo.valueIds))
                        .accessibilityHint("Restores this combination to the valid matrix.")
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Invalid combination \(label(for: combo.valueIds))")
                    .accessibilityValue("Blocked")
                }
            }
        }
    }

    private var matrixSummaryRows: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                metricPill(label: "VALID", value: "\(setupVariants.count)")
                metricPill(label: "BLOCKED", value: "\(invalidCombinations.count)")
                metricPill(label: "ENABLED", value: "\(enabledVariants.count)")
            }
            if setupVariants.isEmpty {
                emptyState("NO VALID VARIANTS", "The invalid-combo rules removed every generated row.")
            } else {
                ForEach($setupVariants) { $variant in
                    Toggle(isOn: $variant.isEnabled) {
                        Text(label(for: variant.optionValueIds))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .tint(OPSStyle.Colors.text)
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }

    private var variantsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("VARIANTS")
            if setupVariants.isEmpty {
                emptyState("GENERATE MATRIX", "Generate valid combinations before setting SKUs and thresholds.")
            } else {
                ForEach($setupVariants) { $variant in
                    if variant.isEnabled {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text(label(for: variant.optionValueIds))
                                .font(OPSStyle.Typography.panelTitle)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            if skuWarningApplies(to: variant) {
                                Text("WARN :: SKU MATCH")
                                    .font(OPSStyle.Typography.metadata)
                                    .foregroundColor(OPSStyle.Colors.warningText)
                            }
                            if matrixBlockApplies(to: variant) {
                                Text("BLOCK :: MATRIX MATCH")
                                    .font(OPSStyle.Typography.metadata)
                                    .foregroundColor(OPSStyle.Colors.errorText)
                            }

                            CatalogFieldLabel("SKU")
                            TextField("", text: $variant.sku)
                                .textInputAutocapitalization(.characters)
                                .textFieldStyle(CatalogTextFieldStyle())

                            CatalogFieldLabel("Unit")
                            pickerContainer {
                                Picker("Unit", selection: $variant.unitId) {
                                    Text("Inherit").tag(String?.none)
                                    ForEach(companyUnits) { unit in
                                        Text(unit.display).tag(Optional(unit.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(OPSStyle.Colors.primaryText)
                            }

                            compactAwarePair {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                    CatalogFieldLabel("Warning")
                                    TextField("Inherit", text: $variant.warningThresholdText)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(CatalogTextFieldStyle())
                                }
                            } second: {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                    CatalogFieldLabel("Critical")
                                    TextField("Inherit", text: $variant.criticalThresholdText)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(CatalogTextFieldStyle())
                                }
                            }
                        }
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
        .setupPanel()
    }

    private var stockUnitsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PHYSICAL STOCK")
            if setupVariants.isEmpty {
                emptyState("NO VARIANTS", "Generate and enable variants before adding rolls or offcuts.")
            } else {
                ForEach($setupVariants) { $variant in
                    if variant.isEnabled {
                        stockUnitEditor(for: $variant)
                    }
                }
            }
        }
        .setupPanel()
    }

    private func stockUnitEditor(for variant: Binding<CatalogSetupVariantDraft>) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(for: variant.wrappedValue.optionValueIds))
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("MIRROR \(CatalogSetupWorkflow.mirroredQuantityLabel(for: variant.wrappedValue.stockUnits)) · \(CatalogSetupWorkflow.mirroredQuantityBasis(for: variant.wrappedValue.stockUnits))")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
                Menu {
                    Button {
                        addStockUnit(to: variant.wrappedValue.id, kind: .roll)
                    } label: {
                        Label("Roll", systemImage: "ruler")
                    }
                    Button {
                        addStockUnit(to: variant.wrappedValue.id, kind: .offcut)
                    } label: {
                        Label("Offcut", systemImage: "scissors")
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .accessibilityLabel("Add stock unit")
                .accessibilityHint("Choose roll or offcut for \(label(for: variant.wrappedValue.optionValueIds)).")
            }

            if variant.wrappedValue.stockUnits.isEmpty {
                emptyState("NO UNITS", "Add a roll or offcut. Variant quantity mirrors area when length and width use the same unit.")
            }

            ForEach(variant.stockUnits) { $unit in
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    compactAwareTriple {
                        pickerContainer {
                            Picker("Kind", selection: $unit.unitKind) {
                                ForEach(CatalogStockUnitKind.allCases, id: \.self) { kind in
                                    Text(kind.rawValue.uppercased()).tag(kind)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(OPSStyle.Colors.primaryText)
                            .accessibilityLabel("Stock unit kind")
                            .accessibilityValue(unit.unitKind.rawValue.uppercased())
                        }
                    } second: {
                        pickerContainer {
                            Picker("Status", selection: $unit.status) {
                                ForEach(CatalogStockUnitStatus.allCases, id: \.self) { status in
                                    Text(status.rawValue.uppercased()).tag(status)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(OPSStyle.Colors.primaryText)
                            .accessibilityLabel("Stock unit status")
                            .accessibilityValue(unit.status.rawValue.uppercased())
                        }
                    } third: {
                        Button {
                            removeStockUnit(unit.id, from: variant.wrappedValue.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(OPSStyle.Colors.errorText)
                                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        }
                        .accessibilityLabel("Remove stock unit")
                        .accessibilityHint(unit.label.isEmpty ? "Removes this stock unit." : "Removes \(unit.label).")
                    }

                    compactAwarePair {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Label")
                            TextField("", text: $unit.label)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    } second: {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Lot code")
                            TextField("", text: $unit.lotCode)
                                .textInputAutocapitalization(.characters)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    }

                    compactAwarePair {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Remaining length")
                            TextField("0", text: optionalDoubleText($unit.remainingLengthValue))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    } second: {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Original length")
                            TextField("0", text: optionalDoubleText($unit.originalLengthValue))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    }

                    compactAwareTriple {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Length unit")
                            TextField("ft", text: $unit.lengthUnit)
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    } second: {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Width")
                            TextField("0", text: optionalDoubleText($unit.widthValue))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    } third: {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Width unit")
                            TextField("ft", text: $unit.widthUnit)
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    }

                    compactAwarePair {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Qty")
                            TextField("0", text: doubleText($unit.quantityValue))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    } second: {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Location")
                            TextField("", text: $unit.location)
                                .textFieldStyle(CatalogTextFieldStyle())
                        }
                    }

                    CatalogFieldLabel("Notes")
                    TextField("", text: $unit.notes, axis: .vertical)
                        .lineLimit(2...3)
                        .textFieldStyle(CatalogTextFieldStyle())

                    stockLifecycleControls(for: $unit, variantId: variant.wrappedValue.id)
                }
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private func stockLifecycleControls(
        for unit: Binding<CatalogSetupStockUnitDraft>,
        variantId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogFieldLabel("Lifecycle note")
            TextField("", text: lifecycleNoteText(for: unit.wrappedValue.id), axis: .vertical)
                .lineLimit(1...2)
                .textFieldStyle(CatalogTextFieldStyle())

            compactAwarePair {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel(consumeFieldLabel(for: unit.wrappedValue))
                    TextField("0", text: consumeAmountText(for: unit.wrappedValue.id))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(CatalogTextFieldStyle())
                }
            } second: {
                stockLifecycleButton(
                    title: "CONSUME",
                    color: OPSStyle.Colors.primaryAccent,
                    isDisabled: !canConsume(unit.wrappedValue)
                ) {
                    consumeStockUnit(unit.wrappedValue.id, from: variantId)
                }
            }

            compactAwareTriple {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel("Offcut length")
                    TextField("0", text: offcutLengthText(for: unit.wrappedValue.id))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(CatalogTextFieldStyle())
                }
            } second: {
                stockLifecycleButton(
                    title: "OFFCUT",
                    color: OPSStyle.Colors.primaryAccent,
                    isDisabled: !canCreateOffcut(from: unit.wrappedValue)
                ) {
                    createOffcut(from: unit.wrappedValue.id, variantId: variantId)
                }
            } third: {
                stockLifecycleButton(
                    title: "SCRAP",
                    color: OPSStyle.Colors.errorText,
                    isDisabled: !canScrap(unit.wrappedValue)
                ) {
                    scrapStockUnit(unit.wrappedValue.id, from: variantId)
                }
            }

            if !unit.wrappedValue.lifecycleEvents.isEmpty {
                Text(lifecycleSummary(for: unit.wrappedValue))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func stockLifecycleButton(
        title: String,
        color: Color,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : color)
                .frame(width: 88)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.subtleBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(stockLifecycleAccessibilityLabel(for: title))
        .accessibilityHint(stockLifecycleAccessibilityHint(for: title))
        .accessibilityValue(isDisabled ? "Locked" : "Ready")
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PRODUCT LINK")
            CatalogFieldLabel("Sellable product")
            pickerContainer {
                Picker("Product", selection: $selectedProductId) {
                    Text("None").tag(String?.none)
                    ForEach(companyProducts) { product in
                        Text(product.name).tag(Optional(product.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(OPSStyle.Colors.primaryText)
            }
            .onChange(of: selectedProductId) { _, _ in
                productOptionSelectionByAttributeId.removeAll()
                productValueSelectionByCatalogValueId.removeAll()
                autoSelectProductMappings()
            }

            if let selectedProduct {
                if canManageProducts {
                    productOptionAuthoringButton(selectedProduct)
                }
                if !supportsProductOptionMappings {
                    setupBanner(title: "SYS :: OPTION MAPS OFFLINE", message: "Product link can save, but option mappings require the live mapping schema.", isError: true)
                } else if selectableProductOptions.isEmpty {
                    emptyState("NO SELECT OPTIONS", "Author select options on the linked product, then map values here.")
                } else {
                    productMappingRows
                }
            }
        }
        .setupPanel()
    }

    private func productOptionAuthoringButton(_ product: Product) -> some View {
        Button {
            guard permissionStore.can("catalog.products.manage") else { return }
            productOptionAuthoringProduct = product
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                Text("AUTHOR OPTIONS")
                    .font(OPSStyle.Typography.buttonLabel)
                Spacer()
                Text(product.name.uppercased())
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Author product options")
        .accessibilityValue(product.name)
        .accessibilityHint("Opens the shared product option authoring sheet.")
    }

    private var productMappingRows: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            ForEach(activeAttributes) { attribute in
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text(attribute.name.uppercased())
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    CatalogFieldLabel("Product option")
                    pickerContainer {
                        Picker(attribute.name, selection: Binding(
                            get: { productOptionSelectionByAttributeId[attribute.id] ?? "" },
                            set: { value in
                                CatalogSetupWorkflow.setProductOptionSelection(
                                    attributeId: attribute.id,
                                    selectedProductOptionId: value,
                                    attributes: activeAttributes,
                                    productOptionSelectionByAttributeId: &productOptionSelectionByAttributeId,
                                    productValueSelectionByCatalogValueId: &productValueSelectionByCatalogValueId
                                )
                            }
                        )) {
                            Text("None").tag("")
                            ForEach(selectableProductOptions) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(OPSStyle.Colors.primaryText)
                        .accessibilityLabel("Product option for \(attribute.name)")
                    }

                    if let productOptionId = productOptionSelectionByAttributeId[attribute.id], !productOptionId.isEmpty {
                        ForEach(attribute.values) { value in
                            CatalogFieldLabel(value.value)
                            pickerContainer {
                                Picker(value.value, selection: Binding(
                                    get: { productValueSelectionByCatalogValueId[value.id] ?? "" },
                                    set: { selected in
                                        if selected.isEmpty {
                                            productValueSelectionByCatalogValueId.removeValue(forKey: value.id)
                                        } else if productValues(for: productOptionId).contains(where: { $0.id == selected }) {
                                            productValueSelectionByCatalogValueId[value.id] = selected
                                        } else {
                                            productValueSelectionByCatalogValueId.removeValue(forKey: value.id)
                                        }
                                    }
                                )) {
                                    Text("None").tag("")
                                    ForEach(productValues(for: productOptionId)) { productValue in
                                        Text(productValue.value).tag(productValue.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(OPSStyle.Colors.primaryText)
                                .accessibilityLabel("Product value for \(value.value)")
                            }
                        }
                    }
                }
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("REVIEW")
            HStack {
                metricPill(label: "AXES", value: "\(activeAttributes.count)")
                metricPill(label: "VARIANTS", value: "\(enabledVariants.count)")
                metricPill(label: "UNITS", value: "\(enabledVariants.flatMap(\.stockUnits).count)")
            }
            HStack {
                metricPill(label: "SKU WARNS", value: "\(validationResult.warnings.count)")
                metricPill(label: "BLOCKS", value: "\(validationResult.blockingViolations.count + duplicateMatrixSignatures.count + productMappingViolations.count)")
            }
            setupBanner(title: "STOCK MIRROR", message: "Variant quantity mirrors available area when length and width share a unit. Otherwise it mirrors one physical unit system or count.")
            if let selectedProduct {
                setupBanner(title: "LINK :: \(selectedProduct.name.uppercased())", message: "Required bundle children remain in pricing rollup. Suggested children stay separate.")
            }
            // Inventory mode lives here too (Closed PM Decision 4) so an operator
            // setting up stock can flip tracking on/off without leaving the flow.
            // Gated to catalog.manage — never role.
            if permissionStore.can("catalog.manage"), !companyId.isEmpty {
                InventoryModeControl(
                    client: CompanyInventoryModeRepository(companyId: companyId)
                )
            }
            Button {
                Task { await commitSetup() }
            } label: {
                Text(isSaving
                     ? (isQAMode ? "CHECKING" : (isEditMode ? "UPDATING" : "COMMITTING"))
                     : (isQAMode ? "QA CHECK SETUP" : (isEditMode ? "UPDATE SETUP" : "COMMIT SETUP")))
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(canCommit ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(canCommit ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(!canCommit)
            .accessibilityLabel(commitAccessibilityLabel)
            .accessibilityHint(commitAccessibilityHint)
            .accessibilityValue(commitAccessibilityValue)
        }
        .setupPanel()
    }

    // MARK: - Actions

    private func loadPersistedDraftOrFixtureIfNeeded() {
        guard !didAttemptDraftRestore else { return }
        didAttemptDraftRestore = true

        if loadPersistedDraftIfAvailable() {
            return
        }

        if hydrateEditFamilyIfNeeded() {
            return
        }

        loadQAFixtureDraftIfNeeded()
    }

    @discardableResult
    private func loadPersistedDraftIfAvailable() -> Bool {
        guard let draftContext,
              let snapshot = try? draftStore.load(context: draftContext)
        else { return false }

        apply(snapshot)
        return true
    }

    private func apply(_ snapshot: CatalogSetupDraftSnapshot) {
        guard snapshot.context == draftContext else { return }

        setupDraftId = snapshot.draftId
        editFamilyId = snapshot.editFamilyId ?? editFamilyId
        selectedStep = CatalogSetupStep(rawValue: snapshot.selectedStep) ?? .family
        familyName = snapshot.familyName
        familyDescription = snapshot.familyDescription
        familyImageUrl = snapshot.familyImageUrl
        selectedCategoryId = snapshot.selectedCategoryId
        selectedUnitId = snapshot.selectedUnitId
        defaultWarningText = snapshot.defaultWarningText
        defaultCriticalText = snapshot.defaultCriticalText
        attributes = snapshot.attributes
        invalidCombinations = snapshot.invalidCombinations
        invalidSelectionByAttributeId = snapshot.invalidSelectionByAttributeId
        setupVariants = snapshot.setupVariants
        generatedMatrixOnce = snapshot.generatedMatrixOnce
        selectedProductId = snapshot.selectedProductId
        productOptionSelectionByAttributeId = snapshot.productOptionSelectionByAttributeId
        productValueSelectionByCatalogValueId = snapshot.productValueSelectionByCatalogValueId
        deletedIds = snapshot.deletedIds ?? CatalogSetupDeletedIds()
        activeSaveAttempt = snapshot.activeSaveAttempt
        rpcWarnings = snapshot.rpcWarnings
        rpcBlockers = snapshot.rpcBlockers
        errorMessage = snapshot.saveErrorMessage
    }

    @discardableResult
    private func hydrateEditFamilyIfNeeded() -> Bool {
        guard let editFamilyId else { return false }
        guard let family = allFamilies.first(where: {
            $0.id == editFamilyId &&
            $0.companyId == companyId &&
            $0.deletedAt == nil
        }) else {
            errorMessage = "SYS :: FAMILY NOT AVAILABLE"
            return false
        }

        setupDraftId = "edit:\(family.id)"
        familyName = family.name
        familyDescription = family.itemDescription ?? ""
        familyImageUrl = family.imageUrl ?? ""
        selectedCategoryId = family.categoryId
        selectedUnitId = family.defaultUnitId
        defaultWarningText = family.defaultWarningThreshold.map { StockNumberFormatter.quantity($0) } ?? ""
        defaultCriticalText = family.defaultCriticalThreshold.map { StockNumberFormatter.quantity($0) } ?? ""

        let familyOptions = allOptions
            .filter { $0.catalogItemId == family.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        let optionValuesByOptionId = Dictionary(grouping: allOptionValues, by: \.optionId)
        attributes = familyOptions.map { option in
            CatalogSetupAttributeDraft(
                id: option.id,
                serverId: option.id,
                name: option.name,
                values: (optionValuesByOptionId[option.id] ?? [])
                    .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
                    .map {
                        CatalogSetupAttributeValueDraft(
                            id: $0.id,
                            serverId: $0.id,
                            value: $0.value
                        )
                    }
            )
        }

        let optionValueById = Dictionary(uniqueKeysWithValues: allOptionValues.map { ($0.id, $0) })
        let activeOptionIds = Set(familyOptions.map(\.id))
        let joinsByVariantId = Dictionary(grouping: allVariantOptionValues, by: \.variantId)
        let stockUnitsByVariantId = Dictionary(
            grouping: allStockUnits.filter { $0.companyId == companyId && $0.deletedAt == nil },
            by: \.catalogVariantId
        )

        setupVariants = allVariants
            .filter { $0.companyId == companyId && $0.catalogItemId == family.id && $0.deletedAt == nil }
            .sorted { ($0.sku ?? $0.id).localizedCaseInsensitiveCompare($1.sku ?? $1.id) == .orderedAscending }
            .map { variant in
                let joins = joinsByVariantId[variant.id] ?? []
                var valueIdsByAttributeId: [String: String] = [:]
                var valueIds = Set<String>()
                for join in joins {
                    guard let optionValue = optionValueById[join.optionValueId],
                          activeOptionIds.contains(optionValue.optionId)
                    else { continue }
                    valueIdsByAttributeId[optionValue.optionId] = optionValue.id
                    valueIds.insert(optionValue.id)
                }

                let stockUnits = (stockUnitsByVariantId[variant.id] ?? [])
                    .sorted { ($0.label ?? $0.id).localizedCaseInsensitiveCompare($1.label ?? $1.id) == .orderedAscending }
                    .map { unit in
                        CatalogSetupStockUnitDraft(
                            id: unit.id,
                            serverId: unit.id,
                            unitKind: unit.unitKind,
                            label: unit.label ?? "",
                            lotCode: unit.lotCode ?? "",
                            widthValue: unit.widthValue,
                            widthUnit: unit.widthUnit ?? "ft",
                            originalLengthValue: unit.originalLengthValue,
                            remainingLengthValue: unit.remainingLengthValue,
                            lengthUnit: unit.lengthUnit ?? "ft",
                            quantityValue: unit.quantityValue,
                            location: unit.location ?? "",
                            status: unit.status,
                            notes: unit.notes ?? ""
                        )
                    }

                return CatalogSetupVariantDraft(
                    id: variant.id,
                    serverId: variant.id,
                    optionValueIdsByAttributeId: valueIdsByAttributeId,
                    optionValueIds: valueIds,
                    sku: variant.sku ?? "",
                    warningThresholdText: variant.warningThreshold.map { StockNumberFormatter.quantity($0) } ?? "",
                    criticalThresholdText: variant.criticalThreshold.map { StockNumberFormatter.quantity($0) } ?? "",
                    unitId: variant.unitId,
                    imageUrl: "",
                    stockUnits: stockUnits,
                    isEnabled: variant.isActive
                )
            }

        invalidCombinations = []
        invalidSelectionByAttributeId = [:]
        generatedMatrixOnce = !setupVariants.isEmpty
        deletedIds = CatalogSetupDeletedIds()
        activeSaveAttempt = nil
        rpcWarnings = []
        rpcBlockers = []
        errorMessage = nil
        qaCommitMessage = nil

        if let linkedProduct = linkedProduct(for: family.id) {
            selectedProductId = linkedProduct.id
            hydrateProductMappings(familyId: family.id, productId: linkedProduct.id)
        } else {
            selectedProductId = nil
            productOptionSelectionByAttributeId = [:]
            productValueSelectionByCatalogValueId = [:]
        }

        persistDraft()
        return true
    }

    private func linkedProduct(for familyId: String) -> Product? {
        if let direct = companyProducts.first(where: { $0.linkedCatalogItemId == familyId }) {
            return direct
        }
        let mappedProductIds = Set(
            allCatalogProductOptionMappings
                .filter { $0.companyId == companyId && $0.catalogItemId == familyId && $0.deletedAt == nil }
                .map(\.productId)
        )
        return companyProducts.first { mappedProductIds.contains($0.id) }
    }

    private func hydrateProductMappings(familyId: String, productId: String) {
        productOptionSelectionByAttributeId = [:]
        productValueSelectionByCatalogValueId = [:]
        let selectableOptionIds = Set(selectableProductOptions.map(\.id))
        let productOptionValuesById = Dictionary(
            uniqueKeysWithValues: selectedProductOptionValues.map { ($0.id, $0) }
        )

        for mapping in activeCatalogProductOptionMappings(familyId: familyId, productId: productId) {
            guard selectableOptionIds.contains(mapping.productOptionId) else { continue }

            switch mapping.mappingKind {
            case .axis:
                productOptionSelectionByAttributeId[mapping.catalogOptionId] = mapping.productOptionId
            case .value:
                guard let catalogOptionValueId = mapping.catalogOptionValueId,
                      let productOptionValueId = mapping.productOptionValueId,
                      productOptionValuesById[productOptionValueId]?.optionId == mapping.productOptionId
                else { continue }
                productOptionSelectionByAttributeId[mapping.catalogOptionId] = mapping.productOptionId
                productValueSelectionByCatalogValueId[catalogOptionValueId] = productOptionValueId
            }
        }
        sanitizeProductMappings()
    }

    private func handleDraftContextChanged() {
        resetDraftStateForContextChange()
        didAttemptDraftRestore = false
        loadPersistedDraftOrFixtureIfNeeded()
    }

    private func resetDraftStateForContextChange() {
        selectedStep = .family
        familyName = ""
        familyDescription = ""
        familyImageUrl = ""
        selectedCategoryId = nil
        selectedUnitId = nil
        defaultWarningText = ""
        defaultCriticalText = ""
        attributes = [
            CatalogSetupAttributeDraft(values: [
                CatalogSetupAttributeValueDraft(),
                CatalogSetupAttributeValueDraft()
            ])
        ]
        invalidCombinations = []
        invalidSelectionByAttributeId = [:]
        setupVariants = []
        generatedMatrixOnce = false
        selectedProductId = nil
        productOptionSelectionByAttributeId = [:]
        productValueSelectionByCatalogValueId = [:]
        productOptionAuthoringProduct = nil
        editFamilyId = initialEditFamilyId
        setupDraftId = UUID().uuidString
        deletedIds = CatalogSetupDeletedIds()
        activeSaveAttempt = nil
        rpcWarnings = []
        rpcBlockers = []
        errorMessage = nil
        qaCommitMessage = nil
        didClearDraftAfterSuccessfulSave = false
        #if DEBUG
        didLoadQAFixtureDraft = false
        #endif
    }

    private func currentDraftSnapshot(context: CatalogSetupDraftContext) -> CatalogSetupDraftSnapshot {
        CatalogSetupDraftSnapshot(
            context: context,
            draftId: setupDraftId,
            editFamilyId: editFamilyId,
            selectedStep: selectedStep.rawValue,
            familyName: familyName,
            familyDescription: familyDescription,
            familyImageUrl: familyImageUrl,
            selectedCategoryId: selectedCategoryId,
            selectedUnitId: selectedUnitId,
            defaultWarningText: defaultWarningText,
            defaultCriticalText: defaultCriticalText,
            attributes: attributes,
            invalidCombinations: invalidCombinations,
            invalidSelectionByAttributeId: invalidSelectionByAttributeId,
            setupVariants: setupVariants,
            generatedMatrixOnce: generatedMatrixOnce,
            selectedProductId: selectedProductId,
            productOptionSelectionByAttributeId: productOptionSelectionByAttributeId,
            productValueSelectionByCatalogValueId: productValueSelectionByCatalogValueId,
            deletedIds: deletedIds,
            activeSaveAttempt: activeSaveAttempt,
            rpcWarnings: rpcWarnings,
            rpcBlockers: rpcBlockers,
            saveErrorMessage: errorMessage
        )
    }

    private func persistDraft() {
        guard let draftContext, hasPersistableDraftContent, !didClearDraftAfterSuccessfulSave else { return }
        try? draftStore.save(currentDraftSnapshot(context: draftContext))
    }

    private func clearPersistedDraft() {
        guard let draftContext else { return }
        try? draftStore.clear(context: draftContext)
    }

    private func loadQAFixtureDraftIfNeeded() {
        #if DEBUG
        guard !isEditMode, isQAMode, !didLoadQAFixtureDraft else { return }
        didLoadQAFixtureDraft = true
        catalogCapabilities = .catalogSetupQALocalOnly
        errorMessage = nil
        qaCommitMessage = nil

        familyName = CatalogSetupQAFixtures.draftFamilyName
        familyDescription = "Local QA material family. No Supabase writes."
        selectedCategoryId = CatalogSetupQAFixtures.categoryId
        selectedUnitId = CatalogSetupQAFixtures.areaUnitId
        defaultWarningText = "40"
        defaultCriticalText = "15"
        attributes = CatalogSetupQAFixtures.draftAttributes()
        invalidCombinations = [CatalogSetupQAFixtures.invalidCombination]
        invalidSelectionByAttributeId = [
            CatalogSetupQAFixtures.finishAttributeId: CatalogSetupQAFixtures.finishRawValueId,
            CatalogSetupQAFixtures.gaugeAttributeId: CatalogSetupQAFixtures.gaugeHeavyValueId
        ]
        selectedProductId = CatalogSetupQAFixtures.productId

        regenerateMatrix()

        let duplicateSignature = CatalogSetupWorkflow.signature(for: CatalogSetupQAFixtures.duplicateMatrixValueIds)
        let stockSignature = CatalogSetupWorkflow.signature(for: CatalogSetupQAFixtures.stockFixtureValueIds)
        for index in setupVariants.indices {
            let signature = CatalogSetupWorkflow.signature(for: setupVariants[index].optionValueIds)
            if signature == duplicateSignature {
                setupVariants[index].sku = CatalogSetupQAFixtures.duplicateSKU
            } else {
                setupVariants[index].sku = "QA-PANEL-\(index + 1)"
            }

            if signature == stockSignature {
                setupVariants[index].stockUnits = [
                    CatalogSetupStockUnitDraft(
                        unitKind: .roll,
                        label: "QA ROLL 01",
                        lotCode: "QA-LOT-01",
                        widthValue: 6,
                        widthUnit: "ft",
                        originalLengthValue: 75,
                        remainingLengthValue: 75,
                        lengthUnit: "ft",
                        quantityValue: 1,
                        location: "QA rack",
                        status: .full,
                        notes: "Local fixture"
                    ),
                    CatalogSetupStockUnitDraft(
                        unitKind: .offcut,
                        label: "QA OFFCUT 01",
                        lotCode: "QA-LOT-02",
                        widthValue: 6,
                        widthUnit: "ft",
                        originalLengthValue: 12,
                        remainingLengthValue: 9,
                        lengthUnit: "ft",
                        quantityValue: 1,
                        location: "QA rack",
                        status: .partial,
                        notes: "Local fixture"
                    )
                ]
            }
        }

        autoSelectProductMappings()
        persistDraft()
        #endif
    }

    private var canAddInvalidCombination: Bool {
        Set(invalidSelectionByAttributeId.values.filter { !$0.isEmpty }).count >= 2
    }

    private func appendValue(to attributeId: String) {
        guard let index = attributes.firstIndex(where: { $0.id == attributeId }) else { return }
        attributes[index].values.append(CatalogSetupAttributeValueDraft())
    }

    private func removeValue(_ valueId: String, from attributeId: String) {
        guard let index = attributes.firstIndex(where: { $0.id == attributeId }) else { return }
        let removedValue = attributes[index].values.first { $0.id == valueId }
        attributes[index].values.removeAll { $0.id == valueId }
        deletedIds.appendUnique(removedValue?.serverId, to: \.catalogOptionValues)
        markDeletedMappings(catalogOptionIds: Set([attributeId]), catalogOptionValueIds: Set([valueId]))
        markDeletedVariants(containingAnyOptionValueIdIn: Set([valueId]))
        invalidCombinations.removeAll { $0.valueIds.contains(valueId) }
        productValueSelectionByCatalogValueId.removeValue(forKey: valueId)
    }

    private func removeAttribute(_ attributeId: String) {
        let removedAttribute = attributes.first { $0.id == attributeId }
        let removedValueIds = removedAttribute?.values.map(\.id) ?? []
        deletedIds.appendUnique(removedAttribute?.serverId, to: \.catalogOptions)
        for value in removedAttribute?.values ?? [] {
            deletedIds.appendUnique(value.serverId, to: \.catalogOptionValues)
        }
        markDeletedMappings(catalogOptionIds: Set([attributeId]), catalogOptionValueIds: Set(removedValueIds))
        markDeletedVariants(containingAnyOptionValueIdIn: Set(removedValueIds))
        attributes.removeAll { $0.id == attributeId }
        invalidSelectionByAttributeId.removeValue(forKey: attributeId)
        productOptionSelectionByAttributeId.removeValue(forKey: attributeId)
        for valueId in removedValueIds {
            productValueSelectionByCatalogValueId.removeValue(forKey: valueId)
        }
        invalidCombinations.removeAll { combo in
            !Set(removedValueIds).isDisjoint(with: combo.valueIds)
        }
    }

    private func addInvalidCombination() {
        let selected = Set(invalidSelectionByAttributeId.values.filter { !$0.isEmpty })
        guard selected.count >= 2 else { return }
        if !invalidCombinations.contains(where: { $0.valueIds == selected }) {
            invalidCombinations.append(CatalogSetupInvalidCombination(valueIds: selected))
        }
        if generatedMatrixOnce {
            regenerateMatrix()
        }
    }

    private func regenerateMatrix() {
        let previousBySignature = Dictionary(uniqueKeysWithValues: setupVariants.map {
            (CatalogSetupWorkflow.signature(for: $0.optionValueIds), $0)
        })
        var generated = CatalogSetupWorkflow.generateVariantDrafts(
            attributes: activeAttributes,
            invalidCombinations: invalidCombinations
        )
        generated = generated.map { draft in
            let signature = CatalogSetupWorkflow.signature(for: draft.optionValueIds)
            guard var previous = previousBySignature[signature] else {
                var next = draft
                next.unitId = selectedUnitId
                return next
            }
            previous.optionValueIdsByAttributeId = draft.optionValueIdsByAttributeId
            previous.optionValueIds = draft.optionValueIds
            return previous
        }
        setupVariants = generated
        generatedMatrixOnce = true
        autoSelectProductMappings()
    }

    private func addStockUnit(to variantId: String, kind: CatalogStockUnitKind) {
        guard let index = setupVariants.firstIndex(where: { $0.id == variantId }) else { return }
        let count = setupVariants[index].stockUnits.count + 1
        let status: CatalogStockUnitStatus = kind == .offcut ? .partial : .full
        let unit = CatalogSetupStockUnitDraft(
            unitKind: kind,
            label: "\(kind.rawValue.uppercased()) \(count)",
            widthValue: kind == .roll || kind == .offcut ? 6 : nil,
            originalLengthValue: kind == .roll ? 75 : (kind == .offcut ? 12 : nil),
            remainingLengthValue: kind == .roll ? 75 : (kind == .offcut ? 12 : nil),
            quantityValue: 1,
            status: status,
            lifecycleEvents: [
                CatalogSetupStockUnitEventDraft(
                    eventType: .receive,
                    fromStatus: nil,
                    toStatus: status,
                    quantityDelta: 1,
                    remainingLengthDelta: kind == .roll ? 75 : (kind == .offcut ? 12 : nil),
                    metadata: lifecycleMetadata(action: "receive", variantId: variantId)
                )
            ]
        )
        setupVariants[index].stockUnits.append(unit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func removeStockUnit(_ unitId: String, from variantId: String) {
        guard let index = setupVariants.firstIndex(where: { $0.id == variantId }) else { return }
        let removedUnit = setupVariants[index].stockUnits.first { $0.id == unitId }
        deletedIds.appendUnique(removedUnit?.serverId, to: \.catalogStockUnits)
        setupVariants[index].stockUnits.removeAll { $0.id == unitId }
    }

    private func consumeStockUnit(_ unitId: String, from variantId: String) {
        guard let indices = stockUnitIndices(unitId: unitId, variantId: variantId),
              let requested = parsedDouble(stockConsumeAmountByUnitId[unitId] ?? ""),
              requested > 0
        else { return }

        var unit = setupVariants[indices.variant].stockUnits[indices.unit]
        guard unit.status != .consumed, unit.status != .scrapped else { return }
        let fromStatus = unit.status
        var quantityDelta: Double?
        var remainingLengthDelta: Double?

        if let remainingLength = unit.remainingLengthValue {
            let consumed = min(requested, max(0, remainingLength))
            guard consumed > 0 else { return }
            let nextRemaining = max(0, remainingLength - consumed)
            unit.remainingLengthValue = nextRemaining
            unit.status = nextRemaining <= 0 ? .consumed : .partial
            remainingLengthDelta = -consumed
        } else {
            let consumed = min(requested, max(0, unit.quantityValue))
            guard consumed > 0 else { return }
            let nextQuantity = max(0, unit.quantityValue - consumed)
            unit.quantityValue = nextQuantity
            unit.status = nextQuantity <= 0 ? .consumed : .partial
            quantityDelta = -consumed
        }

        unit.lifecycleEvents.append(CatalogSetupStockUnitEventDraft(
            eventType: .consume,
            fromStatus: fromStatus,
            toStatus: unit.status,
            quantityDelta: quantityDelta,
            remainingLengthDelta: remainingLengthDelta,
            notes: lifecycleNote(for: unitId),
            metadata: lifecycleMetadata(action: "consume", variantId: variantId)
        ))
        setupVariants[indices.variant].stockUnits[indices.unit] = unit
        stockConsumeAmountByUnitId[unitId] = ""
        stockLifecycleNoteByUnitId[unitId] = ""
        persistDraft()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func scrapStockUnit(_ unitId: String, from variantId: String) {
        guard let indices = stockUnitIndices(unitId: unitId, variantId: variantId) else { return }
        var unit = setupVariants[indices.variant].stockUnits[indices.unit]
        guard unit.status != .scrapped else { return }

        let fromStatus = unit.status
        let remainingLengthDelta = unit.status.countsAsAvailable ? unit.remainingLengthValue.map { -max(0, $0) } : nil
        let quantityDelta = unit.status.countsAsAvailable && unit.remainingLengthValue == nil ? -max(0, unit.quantityValue) : nil
        unit.status = .scrapped
        unit.lifecycleEvents.append(CatalogSetupStockUnitEventDraft(
            eventType: .scrap,
            fromStatus: fromStatus,
            toStatus: .scrapped,
            quantityDelta: quantityDelta,
            remainingLengthDelta: remainingLengthDelta,
            notes: lifecycleNote(for: unitId),
            metadata: lifecycleMetadata(action: "scrap", variantId: variantId)
        ))

        setupVariants[indices.variant].stockUnits[indices.unit] = unit
        stockLifecycleNoteByUnitId[unitId] = ""
        persistDraft()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func createOffcut(from unitId: String, variantId: String) {
        guard let indices = stockUnitIndices(unitId: unitId, variantId: variantId),
              let requestedLength = parsedDouble(stockOffcutLengthByUnitId[unitId] ?? ""),
              requestedLength > 0
        else { return }

        var sourceUnit = setupVariants[indices.variant].stockUnits[indices.unit]
        guard sourceUnit.status != .consumed,
              sourceUnit.status != .scrapped,
              let sourceRemaining = sourceUnit.remainingLengthValue,
              sourceRemaining > 0
        else { return }

        let offcutLength = min(requestedLength, sourceRemaining)
        guard offcutLength > 0 else { return }

        let offcutId = UUID().uuidString
        let note = lifecycleNote(for: unitId)
        let sourceFromStatus = sourceUnit.status
        let nextSourceRemaining = max(0, sourceRemaining - offcutLength)
        sourceUnit.remainingLengthValue = nextSourceRemaining
        sourceUnit.status = nextSourceRemaining <= 0 ? .consumed : .partial
        sourceUnit.lifecycleEvents.append(CatalogSetupStockUnitEventDraft(
            eventType: .adjust,
            relatedStockUnitClientId: offcutId,
            relatedStockUnitServerId: nil,
            fromStatus: sourceFromStatus,
            toStatus: sourceUnit.status,
            quantityDelta: nil,
            remainingLengthDelta: -offcutLength,
            notes: note,
            metadata: lifecycleMetadata(action: "offcut_source", variantId: variantId)
        ))

        let offcutCount = setupVariants[indices.variant].stockUnits.filter { $0.unitKind == .offcut }.count + 1
        let offcut = CatalogSetupStockUnitDraft(
            id: offcutId,
            relatedStockUnitClientId: sourceUnit.id,
            relatedStockUnitServerId: sourceUnit.serverId,
            unitKind: .offcut,
            label: "OFFCUT \(offcutCount)",
            lotCode: sourceUnit.lotCode,
            widthValue: sourceUnit.widthValue,
            widthUnit: sourceUnit.widthUnit,
            originalLengthValue: offcutLength,
            remainingLengthValue: offcutLength,
            lengthUnit: sourceUnit.lengthUnit,
            quantityValue: 1,
            location: sourceUnit.location,
            status: .partial,
            notes: note,
            lifecycleEvents: [
                CatalogSetupStockUnitEventDraft(
                    eventType: .offcutCreate,
                    relatedStockUnitClientId: sourceUnit.id,
                    relatedStockUnitServerId: sourceUnit.serverId,
                    fromStatus: nil,
                    toStatus: .partial,
                    quantityDelta: 1,
                    remainingLengthDelta: offcutLength,
                    notes: note,
                    metadata: lifecycleMetadata(action: "offcut_create", variantId: variantId)
                )
            ]
        )

        setupVariants[indices.variant].stockUnits[indices.unit] = sourceUnit
        setupVariants[indices.variant].stockUnits.append(offcut)
        stockOffcutLengthByUnitId[unitId] = ""
        stockLifecycleNoteByUnitId[unitId] = ""
        persistDraft()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func stockUnitIndices(unitId: String, variantId: String) -> (variant: Int, unit: Int)? {
        guard let variantIndex = setupVariants.firstIndex(where: { $0.id == variantId }),
              let unitIndex = setupVariants[variantIndex].stockUnits.firstIndex(where: { $0.id == unitId })
        else { return nil }
        return (variantIndex, unitIndex)
    }

    private func lifecycleMetadata(action: String, variantId: String) -> [String: String] {
        [
            "source": "ios_catalog_setup",
            "draft_id": setupDraftId,
            "variant_client_id": variantId,
            "action": action
        ]
    }

    private func lifecycleNote(for unitId: String) -> String {
        trimmedOptional(stockLifecycleNoteByUnitId[unitId] ?? "") ?? ""
    }

    private func markDeletedMappings(catalogOptionIds: Set<String>, catalogOptionValueIds: Set<String>) {
        guard let familyId = editFamilyId else { return }
        for mapping in allCatalogProductOptionMappings where mapping.companyId == companyId && mapping.catalogItemId == familyId && mapping.deletedAt == nil {
            if catalogOptionIds.contains(mapping.catalogOptionId) ||
                mapping.catalogOptionValueId.map({ catalogOptionValueIds.contains($0) }) == true {
                deletedIds.appendUnique(mapping.id, to: \.catalogProductOptionMappings)
            }
        }
    }

    private func markDeletedVariants(containingAnyOptionValueIdIn optionValueIds: Set<String>) {
        guard !optionValueIds.isEmpty else { return }
        for variant in setupVariants where !variant.optionValueIds.isDisjoint(with: optionValueIds) {
            deletedIds.appendUnique(variant.serverId, to: \.catalogVariants)
            for unit in variant.stockUnits {
                deletedIds.appendUnique(unit.serverId, to: \.catalogStockUnits)
            }
        }
    }

    private func autoSelectProductMappings() {
        guard selectedProduct != nil else {
            productOptionSelectionByAttributeId.removeAll()
            productValueSelectionByCatalogValueId.removeAll()
            return
        }
        sanitizeProductMappings()
        for attribute in activeAttributes {
            if productOptionSelectionByAttributeId[attribute.id] == nil,
               let match = selectableProductOptions.first(where: { normalized($0.name) == normalized(attribute.name) }) {
                productOptionSelectionByAttributeId[attribute.id] = match.id
            }
            guard let productOptionId = productOptionSelectionByAttributeId[attribute.id] else { continue }
            let values = productValues(for: productOptionId)
            for value in attribute.values where productValueSelectionByCatalogValueId[value.id] == nil {
                if let match = values.first(where: { normalized($0.value) == normalized(value.value) }) {
                    productValueSelectionByCatalogValueId[value.id] = match.id
                }
            }
        }
    }

    private func sanitizeProductMappings() {
        CatalogSetupWorkflow.sanitizeProductOptionMappingSelections(
            attributes: activeAttributes,
            productOptions: selectedProductOptions,
            productOptionValues: selectedProductOptionValues,
            productOptionSelectionByAttributeId: &productOptionSelectionByAttributeId,
            productValueSelectionByCatalogValueId: &productValueSelectionByCatalogValueId
        )
    }

    private func activeCatalogProductOptionMappings(familyId: String?, productId: String) -> [CatalogProductOptionMapping] {
        guard let familyId else { return [] }
        return allCatalogProductOptionMappings
            .filter {
                $0.companyId == companyId &&
                $0.catalogItemId == familyId &&
                $0.productId == productId &&
                $0.deletedAt == nil
            }
    }

    private func effectiveDeletedIds(for payload: CatalogSetupSavePayload) -> CatalogSetupDeletedIds {
        var effective = deletedIds

        for variant in setupVariants where !variant.isEnabled {
            effective.appendUnique(variant.serverId, to: \.catalogVariants)
            for unit in variant.stockUnits {
                effective.appendUnique(unit.serverId, to: \.catalogStockUnits)
            }
        }

        guard supportsProductOptionMappings,
              let product = selectedProduct,
              let familyId = editFamilyId
        else { return effective }

        let retainedMappingIds = Set(payload.products.flatMap { product in
            product.catalogOptionMappings.compactMap(\.id)
        })
        let managedCatalogOptionIds = Set(activeAttributes.compactMap { $0.serverId ?? $0.id })
        let managedCatalogValueIds = Set(activeAttributes.flatMap { attribute in
            attribute.values.compactMap { $0.serverId ?? $0.id }
        })

        for mapping in activeCatalogProductOptionMappings(familyId: familyId, productId: product.id) {
            let isManagedAxis = managedCatalogOptionIds.contains(mapping.catalogOptionId)
            let isManagedValue = mapping.catalogOptionValueId.map { managedCatalogValueIds.contains($0) } ?? false
            guard isManagedAxis || isManagedValue else { continue }
            if !retainedMappingIds.contains(mapping.id) {
                effective.appendUnique(mapping.id, to: \.catalogProductOptionMappings)
            }
        }

        return effective
    }

    // MARK: - Persistence

    @MainActor
    private func commitSetup() async {
        guard canCommit else { return }
        isSaving = true
        errorMessage = nil
        qaCommitMessage = nil
        rpcWarnings = []
        rpcBlockers = []
        didClearDraftAfterSuccessfulSave = false
        persistDraft()
        defer { isSaving = false }

        #if DEBUG
        if isQAMode {
            try? await Task.sleep(nanoseconds: 150_000_000)
            qaCommitMessage = "No catalog data saved. Production repositories were not instantiated."
            persistDraft()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        #endif

        do {
            catalogCapabilities = await CatalogSchemaCapabilityGate.refresh(companyId: companyId)
            try CatalogSetupWorkflow.preflightCommit(
                variants: enabledVariants,
                capabilities: catalogCapabilities
            )
            let mappingViolations = productMappingViolations
            if !mappingViolations.isEmpty {
                throw CatalogSetupCommitPreflightError.invalidProductOptionMappings(mappingViolations)
            }

            let catalogRepository = CatalogRepository(companyId: companyId)
            var payload = CatalogSetupWorkflow.makeSavePayload(
                mode: saveMode,
                draftId: setupDraftId,
                existingFamilyId: editFamilyId,
                familyName: familyName,
                familyDescription: familyDescription,
                familyImageUrl: familyImageUrl,
                selectedCategoryId: selectedCategoryId,
                selectedUnitId: selectedUnitId,
                defaultWarningThreshold: parsedDouble(defaultWarningText),
                defaultCriticalThreshold: parsedDouble(defaultCriticalText),
                attributes: activeAttributes,
                variants: enabledVariants,
                selectedProduct: selectedProduct,
                productOptionSelectionByAttributeId: supportsProductOptionMappings ? productOptionSelectionByAttributeId : [:],
                productValueSelectionByCatalogValueId: supportsProductOptionMappings ? productValueSelectionByCatalogValueId : [:],
                productOptions: allProductOptions,
                productOptionValues: allProductOptionValues,
                catalogProductOptionMappings: selectedProduct.map {
                    activeCatalogProductOptionMappings(familyId: editFamilyId, productId: $0.id)
                } ?? [],
                productPricingModifiers: allProductPricingModifiers,
                productMaterials: allProductMaterials,
                productBundleItems: allProductBundleItems,
                capabilities: catalogCapabilities,
                deletedIds: deletedIds
            )
            payload.deletedIds = effectiveDeletedIds(for: payload)
            let saveAttempt = try CatalogSetupSaveAttempt.resolve(
                payload: payload,
                existingAttempt: activeSaveAttempt
            )
            activeSaveAttempt = saveAttempt
            persistDraft()

            let response = try await catalogRepository.saveCatalogSetup(
                idempotencyKey: saveAttempt.idempotencyKey,
                payload: payload
            )
            let resolution = CatalogSetupWorkflow.resolveSaveResponse(response)
            rpcWarnings = resolution.warnings
            rpcBlockers = resolution.blockers
            persistDraft()

            guard response.ok else {
                errorMessage = resolution.userFacingMessage ?? "Server rejected catalog setup save."
                persistDraft()
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }

            let commitService = CatalogSetupCommitService(
                companyId: companyId,
                modelContext: modelContext,
                capabilities: catalogCapabilities,
                requestCatalogResync: { [dataController] in
                    Task { await dataController.syncEngine?.triggerSync() }
                }
            )
            _ = commitService.reconcile(payload: payload, response: response)
            didClearDraftAfterSuccessfulSave = true
            activeSaveAttempt = nil
            clearPersistedDraft()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            refreshMappingNotificationRailIfNeeded()
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
            persistDraft()
        }
    }

    private func refreshMappingNotificationRailIfNeeded() {
        guard initialMissingMappingKey != nil else { return }
        NotificationCenter.default.post(name: .notificationReceived, object: nil)
    }

    @MainActor
    private func refreshCatalogCapabilities() async {
        #if DEBUG
        if isQAMode {
            catalogCapabilities = .catalogSetupQALocalOnly
            return
        }
        #endif

        guard !companyId.isEmpty else {
            catalogCapabilities = CatalogSchemaCapabilityGate.current
            return
        }
        catalogCapabilities = await CatalogSchemaCapabilityGate.refresh(companyId: companyId)
    }

    private func upsertProduct(_ dto: ProductDTO) {
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.name = dto.name
            existing.productDescription = dto.description
            existing.basePrice = dto.basePrice
            existing.unitCost = dto.unitCost
            existing.unit = dto.unit
            existing.category = dto.category
            existing.categoryId = dto.categoryId
            existing.sku = dto.sku
            existing.thumbnailUrl = dto.thumbnailUrl
            existing.pricingUnit = dto.pricingUnit.flatMap { ProductPricingUnit(rawValue: $0) } ?? .each
            existing.type = dto.type.flatMap { LineItemType(rawValue: $0) } ?? .labor
            existing.taxable = dto.isTaxable ?? true
            existing.isActive = dto.isActive
            existing.isFavorite = dto.isFavorite
            existing.minimumCharge = dto.minimumCharge
            existing.minimumQuantity = dto.minimumQuantity
            existing.showBomOnEstimate = dto.showBomOnEstimate
            existing.showInStorefront = dto.showInStorefront
            existing.tieredPricingJSON = dto.tieredPricing?.rawJSONString
            existing.taskTypeId = dto.taskTypeId
            existing.taskTypeRef = dto.taskTypeRef
            existing.unitId = dto.unitId
            existing.linkedCatalogItemId = dto.linkedCatalogItemId
            existing.bundlePricingMode = dto.bundlePricingMode
        } else {
            modelContext.insert(dto.toModel())
        }
    }

    // MARK: - Formatting

    private var commitAccessibilityLabel: String {
        if isQAMode { return "Run QA catalog setup check" }
        return isEditMode ? "Update stock setup" : "Commit stock setup"
    }

    private var commitAccessibilityValue: String {
        if isSaving { return isQAMode ? "Checking" : "Saving" }
        return canCommit ? "Ready" : "Locked"
    }

    private var commitAccessibilityHint: String {
        if canCommit {
            return isQAMode
                ? "Runs the local-only no-write catalog setup check."
                : "Saves the complete catalog setup through one atomic request."
        }
        if companyId.isEmpty { return "Company context is not loaded." }
        if familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a family name first." }
        if enabledVariants.isEmpty { return "Generate and enable at least one variant first." }
        if hasBlockingMatrixConflict { return "Resolve duplicate matrix blockers first." }
        if !productMappingViolations.isEmpty { return "Resolve product option mapping blockers first." }
        if isOffline { return "Device is offline. Draft remains on screen." }
        if hasDraftStockUnits && !catalogCapabilities.catalogStockUnits {
            return "This Supabase target does not support stock units yet."
        }
        return "Setup is not ready to save."
    }

    @ViewBuilder
    private func compactAwarePair<First: View, Second: View>(
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) -> some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                first()
                second()
            }
        } else {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                first()
                    .frame(maxWidth: .infinity, alignment: .leading)
                second()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func compactAwareTriple<First: View, Second: View, Third: View>(
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second,
        @ViewBuilder third: () -> Third
    ) -> some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                first()
                second()
                third()
            }
        } else {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                first()
                    .frame(maxWidth: .infinity, alignment: .leading)
                second()
                    .frame(maxWidth: .infinity, alignment: .leading)
                third()
            }
        }
    }

    private func stockLifecycleAccessibilityHint(for title: String) -> String {
        switch title {
        case "CONSUME":
            return "Queues a consume event for this stock unit."
        case "OFFCUT":
            return "Queues an offcut event and creates the offcut row."
        case "SCRAP":
            return "Queues a scrap event for this stock unit."
        default:
            return "Queues this lifecycle action."
        }
    }

    private func stockLifecycleAccessibilityLabel(for title: String) -> String {
        switch title {
        case "CONSUME":
            return "Consume stock unit"
        case "OFFCUT":
            return "Create stock offcut"
        case "SCRAP":
            return "Scrap stock unit"
        default:
            return title
        }
    }

    private func lifecycleNoteText(for unitId: String) -> Binding<String> {
        Binding<String>(
            get: { stockLifecycleNoteByUnitId[unitId] ?? "" },
            set: { stockLifecycleNoteByUnitId[unitId] = $0 }
        )
    }

    private func consumeAmountText(for unitId: String) -> Binding<String> {
        Binding<String>(
            get: { stockConsumeAmountByUnitId[unitId] ?? "" },
            set: { stockConsumeAmountByUnitId[unitId] = $0 }
        )
    }

    private func offcutLengthText(for unitId: String) -> Binding<String> {
        Binding<String>(
            get: { stockOffcutLengthByUnitId[unitId] ?? "" },
            set: { stockOffcutLengthByUnitId[unitId] = $0 }
        )
    }

    private func consumeFieldLabel(for unit: CatalogSetupStockUnitDraft) -> String {
        unit.remainingLengthValue == nil ? "Use qty" : "Use length"
    }

    private func canConsume(_ unit: CatalogSetupStockUnitDraft) -> Bool {
        guard unit.status != .consumed,
              unit.status != .scrapped,
              let amount = parsedDouble(stockConsumeAmountByUnitId[unit.id] ?? ""),
              amount > 0
        else { return false }

        if let remainingLength = unit.remainingLengthValue {
            return remainingLength > 0
        }
        return unit.quantityValue > 0
    }

    private func canScrap(_ unit: CatalogSetupStockUnitDraft) -> Bool {
        unit.status != .scrapped
    }

    private func canCreateOffcut(from unit: CatalogSetupStockUnitDraft) -> Bool {
        guard unit.status != .consumed,
              unit.status != .scrapped,
              let remainingLength = unit.remainingLengthValue,
              remainingLength > 0,
              let requestedLength = parsedDouble(stockOffcutLengthByUnitId[unit.id] ?? ""),
              requestedLength > 0
        else { return false }
        return true
    }

    private func lifecycleSummary(for unit: CatalogSetupStockUnitDraft) -> String {
        let events = unit.lifecycleEvents.map {
            $0.eventType.rawValue.replacingOccurrences(of: "_", with: " ").uppercased()
        }
        return "EVENTS QUEUED · \(events.joined(separator: " / "))"
    }

    private func pickerContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func setupBanner(title: String, message: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(title)
                .font(OPSStyle.Typography.category)
                .foregroundColor(isError ? OPSStyle.Colors.errorText : OPSStyle.Colors.primaryText)
            Text(message)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isError ? OPSStyle.Colors.errorText : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }

    private func emptyState(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(title)
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(message)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(value)
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private func label(for valueIds: Set<String>) -> String {
        let valuesById = Dictionary(uniqueKeysWithValues: activeAttributes.flatMap(\.values).map { ($0.id, $0.value) })
        let labels = valueIds.sorted().compactMap { valuesById[$0] }
        return labels.isEmpty ? "BASE VARIANT" : labels.joined(separator: " / ")
    }

    private func productValues(for productOptionId: String) -> [ProductOptionValue] {
        guard selectableProductOptions.contains(where: { $0.id == productOptionId }) else { return [] }
        return selectedProductOptionValues
            .filter { $0.optionId == productOptionId }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
    }

    private func skuWarningApplies(to variant: CatalogSetupVariantDraft) -> Bool {
        guard let normalizedSKU = CatalogSetupWorkflow.trimmedOptional(variant.sku)?.lowercased() else { return false }
        return validationResult.warnings.contains {
            if case .duplicateSKU(let sku, _) = $0 {
                return sku == normalizedSKU
            }
            return false
        }
    }

    private func matrixBlockApplies(to variant: CatalogSetupVariantDraft) -> Bool {
        let signature = CatalogSetupWorkflow.signature(for: variant.optionValueIds)
        if duplicateMatrixSignatures.contains(signature) { return true }
        return validationResult.blockingViolations.contains {
            if case .duplicateMatrixSignature(_, let optionValueIds, _) = $0 {
                return optionValueIds == variant.optionValueIds
            }
            return false
        }
    }

    private func optionalDoubleText(_ binding: Binding<Double?>) -> Binding<String> {
        Binding<String>(
            get: { binding.wrappedValue.map { formatted($0) } ?? "" },
            set: { newValue in binding.wrappedValue = parsedDouble(newValue) }
        )
    }

    private func doubleText(_ binding: Binding<Double>) -> Binding<String> {
        Binding<String>(
            get: { formatted(binding.wrappedValue) },
            set: { newValue in binding.wrappedValue = parsedDouble(newValue) ?? 0 }
        )
    }

    private func parsedDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private func trimmedOptional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension View {
    func setupPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
