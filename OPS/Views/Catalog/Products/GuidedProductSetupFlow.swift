//
//  GuidedProductSetupFlow.swift
//  OPS
//
//  Full-screen guided setup for the Catalog PRODUCTS segment.
//  Owns the setup sequence, draft state, validation, product commits, bundle
//  child commits, recipe material commits, completion summary, and the
//  bridge into guided stock setup.
//

import SwiftUI
import SwiftData

struct GuidedProductSetupFlow: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    @Query private var allProducts: [Product]
    @Query private var allMaterials: [ProductMaterial]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]
    @Query private var allTaskTypes: [TaskType]
    @Query private var allFamilies: [CatalogItem]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allCatalogOptions: [CatalogOption]
    @Query private var allCatalogOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]

    @State private var stage: GuidedProductSetupStage = .prime
    @State private var includeService = true
    @State private var includeGood = true
    @State private var includeBundle = true

    @State private var serviceName = ""
    @State private var servicePrice = ""
    @State private var serviceUnitId: String?
    @State private var serviceCategoryId: String?
    @State private var serviceTaskTypeId: String?

    @State private var goodName = ""
    @State private var goodPrice = ""
    @State private var goodUnitCost = ""
    @State private var goodUnitId: String?
    @State private var goodCategoryId: String?

    @State private var bundleName = ""
    @State private var bundlePricingMode: BundlePricingMode = .auto
    @State private var bundleOverridePrice = ""
    @State private var bundleCategoryId: String?
    @State private var bundleTaskTypeId: String?
    @State private var bundleSearch = ""
    @State private var bundleChildren: [BundleChildDraft] = []
    @State private var unflushedBundleProductId: String?
    @State private var unflushedBundleChildren: [BundleChildDraft] = []

    @State private var recipeProductId: String?
    @State private var recipeSearch = ""
    @State private var recipeDrafts: [GuidedProductRecipeDraft] = []
    @State private var savedRecipeRowCount = 0
    @State private var showingRecipeRequirementSheet = false

    @State private var savedProducts: [GuidedProductSetupSavedProduct] = []
    @State private var showingCategoryTarget: GuidedProductSetupCategoryTarget?
    @State private var showingUnitTarget: GuidedProductSetupUnitTarget?
    @State private var showingTaskTypeTarget: GuidedProductSetupTaskTypeTarget?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showExitPrompt = false

    @FocusState private var focusedField: GuidedProductSetupField?

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyProducts: [Product] {
        allProducts
            .filter { $0.companyId == companyId && $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    private var companyTaskTypes: [TaskType] {
        allTaskTypes
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.displayOrder, $0.display) < ($1.displayOrder, $1.display) }
    }

    private var companyFamilies: [CatalogItem] {
        allFamilies
            .filter { $0.companyId == companyId && $0.deletedAt == nil && $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var companyVariants: [CatalogVariant] {
        allVariants
            .filter { $0.companyId == companyId && $0.deletedAt == nil && $0.isActive }
            .sorted { lhs, rhs in
                let leftFamily = familyById[lhs.catalogItemId]?.name ?? ""
                let rightFamily = familyById[rhs.catalogItemId]?.name ?? ""
                if leftFamily != rightFamily {
                    return leftFamily.localizedCaseInsensitiveCompare(rightFamily) == .orderedAscending
                }
                let leftSku = lhs.sku ?? lhs.id
                let rightSku = rhs.sku ?? rhs.id
                return leftSku.localizedCaseInsensitiveCompare(rightSku) == .orderedAscending
            }
    }

    private var familyById: [String: CatalogItem] {
        Dictionary(uniqueKeysWithValues: companyFamilies.map { ($0.id, $0) })
    }

    private var unitById: [String: CatalogUnit] {
        Dictionary(uniqueKeysWithValues: companyUnits.map { ($0.id, $0) })
    }

    private var recipeTargets: [GuidedRecipeProductTarget] {
        var seen = Set<String>()
        var targets: [GuidedRecipeProductTarget] = []

        for product in savedProducts {
            guard seen.insert(product.id).inserted else { continue }
            targets.append(
                GuidedRecipeProductTarget(
                    id: product.id,
                    name: product.name,
                    kind: product.kind,
                    savedThisRun: true
                )
            )
        }

        for product in companyProducts {
            guard seen.insert(product.id).inserted else { continue }
            targets.append(
                GuidedRecipeProductTarget(
                    id: product.id,
                    name: product.name,
                    kind: product.category3Way,
                    savedThisRun: false
                )
            )
        }

        return targets.sorted { lhs, rhs in
            if lhs.savedThisRun != rhs.savedThisRun { return lhs.savedThisRun && !rhs.savedThisRun }
            if lhs.kind != rhs.kind {
                return recipeTargetKindRank(lhs.kind) < recipeTargetKindRank(rhs.kind)
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedRecipeTarget: GuidedRecipeProductTarget? {
        guard let recipeProductId else { return nil }
        return recipeTargets.first(where: { $0.id == recipeProductId })
    }

    private var existingRecipeRowsForTarget: [ProductMaterial] {
        guard let recipeProductId else { return [] }
        return allMaterials.filter { $0.productId == recipeProductId }
    }

    private var existingRecipeVariantIdsForTarget: Set<String> {
        Set(existingRecipeRowsForTarget.compactMap(\.catalogVariantId))
    }

    private var filteredRecipeVariants: [CatalogVariant] {
        let search = recipeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return companyVariants }
        return companyVariants.filter {
            recipeSearchText(for: $0).localizedCaseInsensitiveContains(search)
        }
    }

    private var selectedServiceTaskType: TaskType? {
        selectedTaskType(id: serviceTaskTypeId)
    }

    private var selectedBundleTaskType: TaskType? {
        selectedTaskType(id: bundleTaskTypeId)
    }

    private func selectedTaskType(id: String?) -> TaskType? {
        guard let id else { return nil }
        return companyTaskTypes.first(where: { $0.id == id })
    }

    private var serviceCount: Int {
        companyProducts.filter { $0.category3Way == .service }.count
    }

    private var goodCount: Int {
        companyProducts.filter { $0.category3Way == .material }.count
    }

    private var bundleCount: Int {
        companyProducts.filter { $0.category3Way == .bundle }.count
    }

    private var canManageProducts: Bool {
        permissionStore.can("catalog.products.manage")
    }

    private var canManageStock: Bool {
        permissionStore.can("catalog.manage")
    }

    private var canCreateProducts: Bool {
        canManageProducts && dataController.isConnected && !isSaving
    }

    private var selectedSetupCount: Int {
        [includeService, includeGood, includeBundle].filter { $0 }.count
    }

    private var stageIndex: Int {
        GuidedProductSetupStage.allCases.firstIndex(of: stage) ?? 0
    }

    private var flowAnimation: SwiftUI.Animation {
        reducedMotion ? .linear(duration: 0.15) : OPSStyle.Animation.page
    }

    private var stageTransition: AnyTransition {
        reducedMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            if canManageProducts {
                setupContent
            } else {
                permissionGate
            }
        }
        .sheet(item: $showingCategoryTarget) { target in
            InlineCreateCategorySheet(companyId: companyId) { newId in
                assignCategory(newId, to: target)
            }
            .environmentObject(dataController)
        }
        .sheet(item: $showingUnitTarget) { target in
            InlineCreateUnitSheet(companyId: companyId) { newId in
                assignUnit(newId, to: target)
            }
            .environmentObject(dataController)
        }
        .sheet(item: $showingTaskTypeTarget) { target in
            TaskTypePickerSheet(
                selectedTaskTypeId: selectedTaskTypeId(for: target),
                onSelect: { picked in
                    assignTaskType(picked.id, to: target)
                }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingRecipeRequirementSheet) {
            AddProductMaterialSheet(companyId: companyId) { pending in
                appendRecipeDraft(pending)
            }
            .environmentObject(dataController)
        }
        .confirmationDialog(
            "Exit product setup?",
            isPresented: $showExitPrompt,
            titleVisibility: .visible
        ) {
            Button("EXIT", role: .destructive) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }
            Button("KEEP WORKING", role: .cancel) { }
        } message: {
            Text("Saved products stay in Catalog. Unsaved fields are cleared.")
        }
        .onAppear {
            hydrateDefaultUnits()
        }
        .onChange(of: stage) { _, _ in
            errorMessage = nil
            focusForStage()
        }
        .trackScreen("Catalog.Products.GuidedSetup")
    }

    // MARK: - Shell

    private var setupContent: some View {
        VStack(spacing: 0) {
            topProgress

            if !dataController.isConnected {
                offlineBanner
            }

            ScrollView {
                stageContent
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, bottomClearance)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(stageTransition)
                    .animation(flowAnimation, value: stage)
            }
            .dismissKeyboardOnTap()

            bottomBar
        }
    }

    private var bottomClearance: CGFloat {
        switch stage {
        case .review:
            return 160
        default:
            return errorMessage == nil ? 148 : 180
        }
    }

    private var permissionGate: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            Text("// ACCESS RESTRICTED")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)

            Text("Product setup requires catalog product management access.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)

            Button("CLOSE") {
                dismiss()
            }
            .opsPrimaryButtonStyle()
            .padding(.horizontal, OPSStyle.Layout.spacing4)

            Spacer()
        }
    }

    private var topProgress: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(OPSStyle.Colors.secondaryText.opacity(0.20))
                        .frame(height: 3)
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryText)
                        .frame(
                            width: geometry.size.width *
                                CGFloat(stageIndex + 1) /
                                CGFloat(GuidedProductSetupStage.allCases.count),
                            height: 3
                        )
                        .animation(flowAnimation, value: stage)
                }
            }
            .frame(height: 3)

            HStack {
                Text("STEP \(stageIndex + 1) / \(GuidedProductSetupStage.allCases.count)")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .monospacedDigit()
                Spacer()
                Button {
                    attemptExit()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "xmark")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        Text("EXIT")
                            .font(OPSStyle.Typography.metadata)
                    }
                    .foregroundColor(isSaving ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel("Exit product setup")
                .accessibilityHint("Closes guided product setup.")
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    private var offlineBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("// OFFLINE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("Product setup stays readable. Saving starts when the connection is back.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            Rectangle()
                .frame(height: OPSStyle.Layout.Border.standard)
                .foregroundColor(OPSStyle.Colors.separator),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .prime:
            primeStage
        case .mix:
            mixStage
        case .service:
            serviceStage
        case .good:
            goodStage
        case .bundle:
            bundleStage
        case .recipe:
            recipeStage
        case .review:
            reviewStage
        }
    }

    // MARK: - Prime

    private var primeStage: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            stageHeader(
                eyebrow: "PRODUCT SETUP",
                title: "Build the selling catalog",
                body: "Products are the lines customers buy on estimates. Set up the first service, good, and bundle without digging through every catalog control."
            )

            countStrip

            VStack(spacing: OPSStyle.Layout.spacing2) {
                flowStepRow(number: "01", title: "Pick the mix", body: "Services, goods, bundles, or any combination.")
                flowStepRow(number: "02", title: "Add clean rows", body: "Name, price, unit, category. Nothing extra unless it helps.")
                flowStepRow(number: "03", title: "Assemble the system", body: "Bundle the saved pieces when customers buy them together.")
                flowStepRow(number: "04", title: "Write the recipe", body: "Attach the package to the stock parts the crew needs.")
            }

            guidanceCard(
                title: "TARGET",
                body: "A new company should leave with at least one estimate-ready line. More can be added later from the PRODUCTS menu."
            )
        }
    }

    private var countStrip: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            metricTile(label: "SERVICES", value: serviceCount)
            metricTile(label: "GOODS", value: goodCount)
            metricTile(label: "BUNDLES", value: bundleCount)
        }
    }

    private func metricTile(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("\(value)")
                .font(OPSStyle.Typography.dataValue)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func flowStepRow(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Text(number)
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(body)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    // MARK: - Mix

    private var mixStage: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            stageHeader(
                eyebrow: "PICK THE MIX",
                title: "What do customers buy?",
                body: "Choose the product types this setup should create. Skipped types stay available from the PRODUCTS menu."
            )

            VStack(spacing: OPSStyle.Layout.spacing2) {
                mixCard(
                    kind: .service,
                    title: "SERVICE",
                    body: "Labor, time, or expertise.",
                    count: serviceCount,
                    isSelected: includeService
                ) {
                    includeService.toggle()
                }

                mixCard(
                    kind: .material,
                    title: "GOOD",
                    body: "Physical product sold on an estimate.",
                    count: goodCount,
                    isSelected: includeGood
                ) {
                    includeGood.toggle()
                }

                mixCard(
                    kind: .bundle,
                    title: "BUNDLE",
                    body: "Services and goods sold as one package.",
                    count: bundleCount,
                    isSelected: includeBundle
                ) {
                    includeBundle.toggle()
                }
            }

            if selectedSetupCount == 0 {
                validationLine("// SELECT AT LEAST ONE TYPE")
            }
        }
    }

    private func mixCard(
        kind: ProductCategory,
        title: String,
        body: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(flowAnimation) {
                action()
            }
        } label: {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: kind.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .regular))
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("// \(title)")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        Text(isSelected ? "IN" : "SKIP")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    }
                    Text(body)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(count) EXISTING")
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nestedCard()
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .stroke(isSelected ? OPSStyle.Colors.primaryText.opacity(0.28) : Color.clear,
                            lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title.lowercased()) setup \(isSelected ? "included" : "skipped")")
    }

    // MARK: - Service

    @ViewBuilder
    private var serviceStage: some View {
        if includeService {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                stageHeader(
                    eyebrow: "SERVICE",
                    title: "Add the labor line",
                    body: "Start with the thing customers pay your crew to do. Keep it broad enough to reuse."
                )

                existingCountCard(kind: .service, count: serviceCount)

                guidedFormCard {
                    CatalogSectionHeader("SERVICE")
                    CatalogFieldLabel("Name")
                    TextField("e.g. Install labor", text: $serviceName)
                        .textFieldStyle(CatalogTextFieldStyle())
                        .focused($focusedField, equals: .serviceName)
                        .submitLabel(.next)

                    HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Price")
                            TextField("0", text: $servicePrice)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(CatalogTextFieldStyle())
                                .focused($focusedField, equals: .servicePrice)
                            if servicePriceInvalid {
                                validationLine("// PRICE MUST BE A NUMBER")
                            }
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Unit")
                            UnitPickerField(
                                selectedUnitId: $serviceUnitId,
                                companyUnits: companyUnits,
                                canCreateNew: canManageProducts,
                                onCreateRequested: { showingUnitTarget = .service },
                                allowFlatRate: true
                            )
                        }
                    }

                    CatalogFieldLabel("Category")
                    CategoryPickerField(
                        selectedCategoryId: $serviceCategoryId,
                        companyCategories: companyCategories,
                        canCreateNew: canManageProducts,
                        onCreateRequested: { showingCategoryTarget = .service }
                    )

                    taskTypeLinkCard(
                        title: "TASK LINK",
                        requirement: "REQUIRED",
                        selectedTaskType: selectedServiceTaskType,
                        helper: selectedServiceTaskType == nil
                            ? "Pick the workflow this service creates on the schedule."
                            : "Tasks created from this service use this type.",
                        isRequired: true,
                        action: { showingTaskTypeTarget = .service }
                    )
                }
            }
        } else {
            skippedStage(
                eyebrow: "SERVICE",
                title: "Service skipped",
                body: "This setup will not create a labor line. You can turn it back on from the mix step."
            )
        }
    }

    // MARK: - Good

    @ViewBuilder
    private var goodStage: some View {
        if includeGood {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                stageHeader(
                    eyebrow: "GOOD",
                    title: "Add the physical product",
                    body: "Use this for material, kit, part, or anything a customer buys by count, length, area, or time."
                )

                existingCountCard(kind: .material, count: goodCount)

                guidedFormCard {
                    CatalogSectionHeader("GOOD")
                    CatalogFieldLabel("Name")
                    TextField("e.g. Composite deck board", text: $goodName)
                        .textFieldStyle(CatalogTextFieldStyle())
                        .focused($focusedField, equals: .goodName)
                        .submitLabel(.next)

                    HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Sell price")
                            TextField("0", text: $goodPrice)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(CatalogTextFieldStyle())
                                .focused($focusedField, equals: .goodPrice)
                            if goodPriceInvalid {
                                validationLine("// PRICE MUST BE A NUMBER")
                            }
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Unit cost")
                            TextField("Optional", text: $goodUnitCost)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(CatalogTextFieldStyle())
                                .focused($focusedField, equals: .goodCost)
                            if goodCostInvalid {
                                validationLine("// COST MUST BE A NUMBER")
                            }
                        }
                    }

                    if let margin = goodMarginPercent {
                        marginReadout(margin)
                    }

                    CatalogFieldLabel("Unit")
                    UnitPickerField(
                        selectedUnitId: $goodUnitId,
                        companyUnits: companyUnits,
                        canCreateNew: canManageProducts,
                        onCreateRequested: { showingUnitTarget = .good },
                        allowFlatRate: true
                    )

                    CatalogFieldLabel("Category")
                    CategoryPickerField(
                        selectedCategoryId: $goodCategoryId,
                        companyCategories: companyCategories,
                        canCreateNew: canManageProducts,
                        onCreateRequested: { showingCategoryTarget = .good }
                    )
                }
            }
        } else {
            skippedStage(
                eyebrow: "GOOD",
                title: "Good skipped",
                body: "This setup will not create a physical product. You can turn it back on from the mix step."
            )
        }
    }

    // MARK: - Bundle

    @ViewBuilder
    private var bundleStage: some View {
        if includeBundle {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                stageHeader(
                    eyebrow: "BUNDLE",
                    title: "Package the system",
                    body: "Bundle the rows customers usually buy together. Auto pricing adds the child prices; override sets a package price."
                )

                existingCountCard(kind: .bundle, count: bundleCount)

                guidedFormCard {
                    CatalogSectionHeader("BUNDLE")
                    CatalogFieldLabel("Name")
                    TextField("e.g. Standard deck package", text: $bundleName)
                        .textFieldStyle(CatalogTextFieldStyle())
                        .focused($focusedField, equals: .bundleName)
                        .submitLabel(.next)

                    CatalogFieldLabel("Category")
                    CategoryPickerField(
                        selectedCategoryId: $bundleCategoryId,
                        companyCategories: companyCategories,
                        canCreateNew: canManageProducts,
                        onCreateRequested: { showingCategoryTarget = .bundle }
                    )

                    taskTypeLinkCard(
                        title: "TASK LINK",
                        requirement: "OPTIONAL",
                        selectedTaskType: selectedBundleTaskType,
                        helper: "Set this when the package should create or group scheduled work.",
                        isRequired: false,
                        action: { showingTaskTypeTarget = .bundle }
                    )
                }

                bundleChildrenCard
                bundlePricingCard
            }
        } else {
            skippedStage(
                eyebrow: "BUNDLE",
                title: "Bundle skipped",
                body: "This setup will not create a package product. You can turn it back on from the mix step."
            )
        }
    }

    private var bundleChildrenCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                CatalogSectionHeader("CHILD PRODUCTS")
                Spacer()
                Text("\(bundleChildren.count)")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            if eligibleBundleChildren.isEmpty {
                validationLine("// CREATE A SERVICE OR GOOD BEFORE BUILDING A BUNDLE")
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    TextField("Search products", text: $bundleSearch)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !bundleSearch.isEmpty {
                        Button {
                            bundleSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )

                VStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(filteredBundleChildren.prefix(8)) { product in
                        bundlePickerRow(product)
                    }
                }

                if !bundleChildren.isEmpty {
                    Divider().background(OPSStyle.Colors.separator)
                    VStack(spacing: OPSStyle.Layout.spacing1) {
                        ForEach(bundleChildren) { draft in
                            selectedBundleChildRow(draft)
                        }
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var bundlePricingCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PRICING")

            HStack(spacing: OPSStyle.Layout.spacing2) {
                pricingModeButton(.auto)
                pricingModeButton(.override)
            }

            if bundlePricingMode == .override {
                CatalogFieldLabel("Package price")
                TextField("0", text: $bundleOverridePrice)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(CatalogTextFieldStyle())
                    .focused($focusedField, equals: .bundlePrice)
                if bundleOverridePriceInvalid {
                    validationLine("// PRICE MUST BE A NUMBER")
                }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                priceTile(label: "CHILD TOTAL", value: rolledBundleTotal)
                priceTile(label: "BUNDLE PRICE", value: effectiveBundlePrice)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func pricingModeButton(_ mode: BundlePricingMode) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(flowAnimation) {
                bundlePricingMode = mode
            }
        } label: {
            Text(mode.displayLabel)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(bundlePricingMode == mode ? OPSStyle.Colors.background : OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(bundlePricingMode == mode ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bundle pricing \(mode.displayLabel.lowercased())")
    }

    private func bundlePickerRow(_ product: Product) -> some View {
        let isSelected = bundleChildren.contains { $0.id == product.id }
        return Button {
            toggleBundleChild(product)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: product.category3Way.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Text("\(product.category3Way.displayLabel) · \(formatMoney(product.basePrice))")
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Text(isSelected ? "ADDED" : "ADD")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(isSelected ? OPSStyle.Colors.primaryText.opacity(0.28) : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Remove \(product.name) from bundle" : "Add \(product.name) to bundle")
    }

    private func selectedBundleChildRow(_ draft: BundleChildDraft) -> some View {
        let product = productById[draft.id]
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product?.name ?? "Missing product")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text(formatMoney((product?.basePrice ?? 0) * draft.quantity))
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            quantityControl(for: draft)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func quantityControl(for draft: BundleChildDraft) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Button {
                adjustBundleQuantity(for: draft.id, delta: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .bold))
            }
            .opsIconButtonStyle(size: OPSStyle.Layout.touchTargetMin)
            .accessibilityLabel("Decrease quantity")

            Text(quantityText(draft.quantity))
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(minWidth: 34)

            Button {
                adjustBundleQuantity(for: draft.id, delta: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .bold))
            }
            .opsIconButtonStyle(size: OPSStyle.Layout.touchTargetMin)
            .accessibilityLabel("Increase quantity")
        }
    }

    // MARK: - Recipe

    private var recipeStage: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            stageHeader(
                eyebrow: "RECIPE",
                title: "Tell OPS what the crew needs",
                body: "A recipe is the material list behind the product. For a rail install bundle, add the posts, rail, brackets, fasteners, and any other stock consumed by the job."
            )

            guidanceCard(
                title: "RAIL INSTALL EXAMPLE",
                body: "Package: rail install bundle. Task link: rail install. Recipe: posts, top rail, bottom rail, brackets, screws, caps. That is the path from estimate line to scheduled work to material planning."
            )

            recipeTargetCard
            recipeMaterialsCard
        }
    }

    private var recipeTargetCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                CatalogSectionHeader("BUILD RECIPE FOR")
                Spacer()
                if let selectedRecipeTarget {
                    Text(selectedRecipeTarget.kind.displayLabel)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            if recipeTargets.isEmpty {
                validationLine("// SAVE A PRODUCT BEFORE WRITING A RECIPE")
            } else {
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(Array(recipeTargets.prefix(6))) { target in
                        recipeTargetRow(target)
                    }
                }

                if let selectedRecipeTarget,
                   !existingRecipeRowsForTarget.isEmpty {
                    validationLine("// \(selectedRecipeTarget.name.uppercased()) ALREADY HAS \(existingRecipeRowsForTarget.count) RECIPE ROW(S)")
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func recipeTargetRow(_ target: GuidedRecipeProductTarget) -> some View {
        let isSelected = target.id == recipeProductId
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(flowAnimation) {
                recipeProductId = target.id
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: target.kind.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Text(target.savedThisRun ? "SAVED THIS RUN" : target.kind.displayLabel)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Text(isSelected ? "TARGET" : "USE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(isSelected ? OPSStyle.Colors.primaryText.opacity(0.28) : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Build recipe for \(target.name)")
    }

    private var recipeMaterialsCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                CatalogSectionHeader("REQUIRED STOCK")
                Spacer()
                Text("\(recipeDrafts.count)")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            addRecipeRequirementButton

            if companyVariants.isEmpty {
                noStockForRecipeState
            } else {
                recipeSearchField

                VStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(Array(filteredRecipeVariants.prefix(10))) { variant in
                        recipeVariantPickerRow(variant)
                    }
                }

                if filteredRecipeVariants.isEmpty {
                    validationLine("// NO STOCK MATCHES SEARCH")
                }
            }

            if !recipeDrafts.isEmpty {
                Divider().background(OPSStyle.Colors.separator)
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    CatalogSectionHeader("RECIPE ROWS")
                    ForEach(recipeDrafts) { draft in
                        selectedRecipeDraftRow(draft)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var noStockForRecipeState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            validationLine("// STOCK REQUIRED")
            Text("Recipe rows attach to stock variants. Tap ADD REQUIREMENT to create the first stock-backed part, then enter the quantity used per product.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var addRecipeRequirementButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingRecipeRequirementSheet = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "plus")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                Text("ADD REQUIREMENT")
                    .font(OPSStyle.Typography.buttonLabel)
                Spacer()
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add recipe requirement")
    }

    private var recipeSearchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField("Search stock", text: $recipeSearch)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !recipeSearch.isEmpty {
                Button {
                    recipeSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear stock search")
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

    private func recipeVariantPickerRow(_ variant: CatalogVariant) -> some View {
        let alreadySelected = recipeDrafts.contains { $0.catalogVariantId == variant.id }
        let alreadyExists = existingRecipeVariantIdsForTarget.contains(variant.id)

        return Button {
            toggleRecipeVariant(variant)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "shippingbox")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recipeVariantTitle(for: variant))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Text(recipeVariantMetadata(for: variant))
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }

                Spacer()

                Text(alreadyExists ? "EXISTS" : (alreadySelected ? "ADDED" : "ADD"))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(alreadySelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alreadySelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(alreadySelected ? OPSStyle.Colors.primaryText.opacity(0.28) : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .disabled(alreadyExists || recipeProductId == nil)
        .accessibilityLabel(alreadySelected ? "Remove \(recipeVariantTitle(for: variant)) from recipe" : "Add \(recipeVariantTitle(for: variant)) to recipe")
    }

    private func selectedRecipeDraftRow(_ draft: GuidedProductRecipeDraft) -> some View {
        let variant = allVariants.first(where: { $0.id == draft.catalogVariantId })
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipeDraftTitle(draft, variant: variant))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Text("PER \(selectedRecipeTarget?.kind.displayLabel ?? "PRODUCT")")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                TextField("Qty", text: recipeQuantityBinding(for: draft.id))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(CatalogTextFieldStyle())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 84)

                Text(recipeUnitDisplay(for: variant, fallback: draft.unitDisplay))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 42, alignment: .leading)

                Button {
                    removeRecipeDraft(id: draft.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .bold))
                }
                .opsIconButtonStyle(size: OPSStyle.Layout.touchTargetMin)
                .accessibilityLabel("Remove recipe row")
            }

            if !recipeQuantityIsValid(draft.quantityText) {
                validationLine("// QUANTITY MUST BE GREATER THAN 0")
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

    // MARK: - Review

    private var reviewStage: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            stageHeader(
                eyebrow: "REVIEW",
                title: savedProducts.isEmpty ? "No products saved yet" : "Product setup ready",
                body: savedProducts.isEmpty
                    ? "Nothing was created in this run. Use BACK to add rows, or finish and build products later."
                    : "These rows are now in Catalog and ready for estimates."
            )

            countStrip

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack {
                    CatalogSectionHeader("THIS RUN")
                    Spacer()
                    Text("\(savedProducts.count)")
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                if savedProducts.isEmpty {
                    validationLine("// NO PRODUCT ROWS SAVED")
                } else {
                    ForEach(savedProducts) { product in
                        savedProductRow(product)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nestedCard()

            recipeReviewCard

            VStack(spacing: OPSStyle.Layout.spacing2) {
                quickAddButton(kind: .service, label: "ADD SERVICE") {
                    includeService = true
                    go(to: .service)
                }
                quickAddButton(kind: .material, label: "ADD GOOD") {
                    includeGood = true
                    go(to: .good)
                }
                quickAddButton(kind: .bundle, label: "ADD BUNDLE") {
                    includeBundle = true
                    go(to: .bundle)
                }
                quickActionButton(icon: "list.bullet.rectangle", label: "ADD RECIPE") {
                    go(to: .recipe)
                }
            }
        }
    }

    private var recipeReviewCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                CatalogSectionHeader("RECIPE")
                Spacer()
                Text("\(savedRecipeRowCount)")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            if savedRecipeRowCount > 0 {
                validationLine("// \(savedRecipeRowCount) MATERIAL REQUIREMENT\(savedRecipeRowCount == 1 ? "" : "S") SAVED")
            } else if companyVariants.isEmpty {
                validationLine("// STOCK REQUIRED BEFORE RECIPE")
                Text("Use ADD RECIPE to create the first stock requirements here, or SET UP STOCK for the full stock catalog.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                validationLine("// NO RECIPE ROWS SAVED")
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func savedProductRow(_ product: GuidedProductSetupSavedProduct) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: product.kind.iconName)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text(product.kind.displayLabel)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            Text(formatMoney(product.basePrice))
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func quickAddButton(kind: ProductCategory, label: String, action: @escaping () -> Void) -> some View {
        quickActionButton(icon: kind.iconName, label: label, action: action)
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .regular))
                Text(label)
                    .font(OPSStyle.Typography.bodyBold)
                Spacer()
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            }
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nestedCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.capitalized)
    }

    // MARK: - Shared stage UI

    private func stageHeader(eyebrow: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(eyebrow)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text(title.uppercased())
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(body)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guidanceCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("// \(title)")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(body)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func existingCountCard(kind: ProductCategory, count: Int) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: kind.iconName)
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .regular))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 28)

            Text("\(count) \(kind.displayLabel) \(count == 1 ? "ROW" : "ROWS") ALREADY IN CATALOG")
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func skippedStage(eyebrow: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            stageHeader(eyebrow: eyebrow, title: title, body: body)
            guidanceCard(title: "SKIPPED", body: "Back up to PICK THE MIX if this should be part of the first setup.")
        }
    }

    private func guidedFormCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func validationLine(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marginReadout(_ margin: Double) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// MARGIN")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text("\(Int(margin.rounded()))%")
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(margin >= 0 ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.errorText)
        }
    }

    private func taskTypeLinkCard(
        title: String,
        requirement: String,
        selectedTaskType: TaskType?,
        helper: String,
        isRequired: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                CatalogSectionHeader(title)
                Text("· \(requirement)")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(isRequired && selectedTaskType == nil
                                     ? OPSStyle.Colors.errorText
                                     : OPSStyle.Colors.tertiaryText)
                Spacer()
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                taskTypePickerLabel(selectedTaskType: selectedTaskType, isRequired: isRequired)
            }
            .buttonStyle(.plain)

            Text(helper)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(isRequired && selectedTaskType == nil
                                 ? OPSStyle.Colors.errorText
                                 : OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func taskTypePickerLabel(selectedTaskType: TaskType?, isRequired: Bool) -> some View {
        let swatch: Color? = {
            guard let hex = selectedTaskType?.color else { return nil }
            return Color(hex: hex)
        }()

        return HStack(spacing: OPSStyle.Layout.spacing2) {
            if let swatch {
                Circle()
                    .fill(swatch)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(swatch.opacity(0.6), lineWidth: 1))
            }

            Text(selectedTaskType?.display ?? "Pick task type")
                .font(OPSStyle.Typography.body)
                .foregroundColor(selectedTaskType == nil
                                 ? OPSStyle.Colors.tertiaryText
                                 : OPSStyle.Colors.primaryText)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.down")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    isRequired && selectedTaskType == nil
                        ? OPSStyle.Colors.errorText
                        : OPSStyle.Colors.cardBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }

    private func priceTile(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(formatMoney(value))
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        OPSFloatingButtonBar {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.errorText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let reason = disabledReason {
                    Text(reason)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                switch stage {
                case .prime:
                    Button {
                        advance()
                    } label: {
                        Text("START")
                    }
                    .opsPrimaryButtonStyle()

                case .mix:
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        backButton
                        Button {
                            advance()
                        } label: {
                            Text("CONTINUE")
                        }
                        .opsPrimaryButtonStyle(isDisabled: !mixCanContinue)
                        .disabled(!mixCanContinue)
                    }

                case .service:
                    stageActionRow(
                        skipLabel: includeService ? "SKIP" : "BACK",
                        primaryLabel: includeService ? "SAVE SERVICE" : "CONTINUE",
                        primaryEnabled: includeService ? serviceCanSave : true,
                        primaryAction: {
                            if includeService {
                                Task { await saveService() }
                            } else {
                                advance()
                            }
                        },
                        secondaryAction: {
                            includeService ? advance() : back()
                        }
                    )

                case .good:
                    stageActionRow(
                        skipLabel: includeGood ? "SKIP" : "BACK",
                        primaryLabel: includeGood ? "SAVE GOOD" : "CONTINUE",
                        primaryEnabled: includeGood ? goodCanSave : true,
                        primaryAction: {
                            if includeGood {
                                Task { await saveGood() }
                            } else {
                                advance()
                            }
                        },
                        secondaryAction: {
                            includeGood ? advance() : back()
                        }
                    )

                case .bundle:
                    stageActionRow(
                        skipLabel: includeBundle ? "SKIP" : "BACK",
                        primaryLabel: bundlePrimaryLabel,
                        primaryEnabled: includeBundle ? bundleCanSave : true,
                        primaryAction: {
                            if includeBundle {
                                if unflushedBundleProductId != nil {
                                    Task { await retryBundleChildren() }
                                } else {
                                    Task { await saveBundle() }
                                }
                            } else {
                                advance()
                            }
                        },
                        secondaryAction: {
                            includeBundle ? advance() : back()
                        }
                    )

                case .recipe:
                    if recipeDrafts.isEmpty {
                        HStack(spacing: OPSStyle.Layout.spacing3) {
                            backButton
                            Button {
                                advance()
                            } label: {
                                Text("CONTINUE")
                            }
                            .opsPrimaryButtonStyle()
                        }
                    } else {
                        stageActionRow(
                            skipLabel: "SKIP",
                            primaryLabel: "SAVE RECIPE",
                            primaryEnabled: recipeCanSave,
                            primaryAction: {
                                Task { await saveRecipe() }
                            },
                            secondaryAction: {
                                advance()
                            }
                        )
                    }

                case .review:
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        if canManageStock {
                            Button {
                                openStockSetup()
                            } label: {
                                Text("SET UP STOCK")
                            }
                            .opsSecondaryButtonStyle()
                        }

                        Button {
                            finishSetup()
                        } label: {
                            Text("DONE")
                        }
                        .opsPrimaryButtonStyle()
                    }
                }
            }
        }
    }

    private var backButton: some View {
        Button {
            back()
        } label: {
            Text("BACK")
        }
        .opsSecondaryButtonStyle()
        .accessibilityLabel("Go back")
    }

    private func stageActionRow(
        skipLabel: String,
        primaryLabel: String,
        primaryEnabled: Bool,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            Button {
                secondaryAction()
            } label: {
                Text(skipLabel)
            }
            .opsSecondaryButtonStyle()

            Button {
                primaryAction()
            } label: {
                if isSaving {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.tertiaryText))
                            .scaleEffect(0.75)
                        Text("SAVING")
                    }
                } else {
                    Text(primaryLabel)
                }
            }
            .opsPrimaryButtonStyle(isDisabled: !primaryEnabled)
            .disabled(!primaryEnabled)
        }
    }

    // MARK: - Validation

    private var mixCanContinue: Bool {
        selectedSetupCount > 0
    }

    private var serviceAmount: Double? {
        parseMoney(servicePrice)
    }

    private var goodAmount: Double? {
        parseMoney(goodPrice)
    }

    private var goodCostAmount: Double? {
        let trimmed = goodUnitCost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parseMoney(trimmed)
    }

    private var bundleOverrideAmount: Double? {
        parseMoney(bundleOverridePrice)
    }

    private var servicePriceInvalid: Bool {
        !servicePrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && serviceAmount == nil
    }

    private var goodPriceInvalid: Bool {
        !goodPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && goodAmount == nil
    }

    private var goodCostInvalid: Bool {
        !goodUnitCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && goodCostAmount == nil
    }

    private var bundleOverridePriceInvalid: Bool {
        bundlePricingMode == .override &&
            !bundleOverridePrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            bundleOverrideAmount == nil
    }

    private var serviceCanSave: Bool {
        guard canCreateProducts else { return false }
        guard !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard serviceAmount != nil else { return false }
        guard serviceTaskTypeId != nil else { return false }
        guard !duplicateExists(named: serviceName) else { return false }
        return true
    }

    private var goodCanSave: Bool {
        guard canCreateProducts else { return false }
        guard !goodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard goodAmount != nil else { return false }
        guard goodCostAmount != nil || goodUnitCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !duplicateExists(named: goodName) else { return false }
        return true
    }

    private var bundleCanSave: Bool {
        if unflushedBundleProductId != nil { return canCreateProducts && !unflushedBundleChildren.isEmpty }
        guard canCreateProducts else { return false }
        guard !bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !bundleChildren.isEmpty else { return false }
        guard !duplicateExists(named: bundleName) else { return false }
        if bundlePricingMode == .override {
            guard let price = bundleOverrideAmount, price >= 0 else { return false }
        }
        return true
    }

    private var recipeCanSave: Bool {
        guard canCreateProducts else { return false }
        guard recipeProductId != nil else { return false }
        guard !recipeDrafts.isEmpty else { return false }
        return recipeDrafts.allSatisfy { recipeQuantityIsValid($0.quantityText) }
    }

    private var disabledReason: String? {
        if isSaving { return nil }
        if canManageProducts && !dataController.isConnected { return "SYS :: OFFLINE - SAVE BLOCKED" }
        switch stage {
        case .mix:
            return mixCanContinue ? nil : "// SELECT AT LEAST ONE TYPE"
        case .service where includeService:
            if duplicateExists(named: serviceName) { return "// NAME ALREADY USED" }
            if serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                serviceAmount == nil {
                return "// NAME, PRICE, TASK TYPE REQUIRED"
            }
            if serviceTaskTypeId == nil { return "// TASK TYPE REQUIRED" }
            return serviceCanSave ? nil : "// NAME AND PRICE REQUIRED"
        case .good where includeGood:
            if duplicateExists(named: goodName) { return "// NAME ALREADY USED" }
            return goodCanSave ? nil : "// NAME AND SELL PRICE REQUIRED"
        case .bundle where includeBundle:
            if duplicateExists(named: bundleName) { return "// NAME ALREADY USED" }
            if eligibleBundleChildren.isEmpty { return "// CREATE A SERVICE OR GOOD FIRST" }
            if bundleChildren.isEmpty { return "// ADD AT LEAST ONE CHILD" }
            if bundlePricingMode == .override && bundleOverrideAmount == nil { return "// PACKAGE PRICE REQUIRED" }
            return bundleCanSave ? nil : "// BUNDLE NOT READY"
        case .recipe where !recipeDrafts.isEmpty:
            if recipeProductId == nil { return "// SELECT THE PRODUCT THIS RECIPE BELONGS TO" }
            if !recipeDrafts.allSatisfy({ recipeQuantityIsValid($0.quantityText) }) {
                return "// QUANTITIES MUST BE GREATER THAN 0"
            }
            return recipeCanSave ? nil : "// RECIPE NOT READY"
        default:
            return nil
        }
    }

    private var bundlePrimaryLabel: String {
        if !includeBundle { return "CONTINUE" }
        if unflushedBundleProductId != nil { return "RETRY CHILDREN" }
        return "SAVE BUNDLE"
    }

    private var eligibleBundleChildren: [Product] {
        companyProducts.filter { $0.category3Way != .bundle }
    }

    private var filteredBundleChildren: [Product] {
        let search = bundleSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return eligibleBundleChildren }
        return eligibleBundleChildren.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
                ($0.productDescription ?? "").localizedCaseInsensitiveContains(search) ||
                ($0.sku ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    private var productById: [String: Product] {
        Dictionary(uniqueKeysWithValues: companyProducts.map { ($0.id, $0) })
    }

    private var rolledBundleTotal: Double {
        bundleChildren.reduce(0) { total, draft in
            total + ((productById[draft.id]?.basePrice ?? 0) * draft.quantity)
        }
    }

    private var effectiveBundlePrice: Double {
        switch bundlePricingMode {
        case .auto:
            return rolledBundleTotal
        case .override:
            return bundleOverrideAmount ?? 0
        }
    }

    private var goodMarginPercent: Double? {
        guard let price = goodAmount, price > 0, let cost = goodCostAmount else { return nil }
        return ((price - cost) / price) * 100
    }

    // MARK: - Navigation

    private func advance() {
        guard let next = stage.next else { return }
        go(to: next)
    }

    private func back() {
        guard let previous = stage.previous else { return }
        go(to: previous)
    }

    private func go(to nextStage: GuidedProductSetupStage) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(flowAnimation) {
            stage = nextStage
        }
    }

    private func attemptExit() {
        if hasUnsavedDraft {
            showExitPrompt = true
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        }
    }

    private var hasUnsavedDraft: Bool {
        [
            serviceName, servicePrice, goodName, goodPrice, goodUnitCost,
            bundleName, bundleOverridePrice, recipeSearch
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
            !bundleChildren.isEmpty ||
            !recipeDrafts.isEmpty
    }

    private func focusForStage() {
        guard canManageProducts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            switch stage {
            case .service where includeService:
                focusedField = .serviceName
            case .good where includeGood:
                focusedField = .goodName
            case .bundle where includeBundle:
                focusedField = .bundleName
            default:
                focusedField = nil
            }
        }
    }

    // MARK: - Save actions

    @MainActor
    private func saveService() async {
        guard serviceCanSave, let amount = serviceAmount else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let selectedUnit = companyUnits.first(where: { $0.id == serviceUnitId })
        let selectedCategory = companyCategories.first(where: { $0.id == serviceCategoryId })

        var dto = CreateProductDTO(
            companyId: companyId,
            name: serviceName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: nil,
            basePrice: amount,
            unitCost: nil,
            unit: selectedUnit?.display,
            pricingUnit: pricingUnit(for: selectedUnit).rawValue,
            unitId: selectedUnit?.id,
            category: selectedCategory?.name,
            categoryId: selectedCategory?.id,
            sku: nil,
            thumbnailUrl: nil,
            kind: ProductCategory.service.derivedKindRaw,
            type: ProductCategory.service.derivedType.rawValue,
            isTaxable: ProductCategory.service.defaultTaxable,
            taskTypeId: serviceTaskTypeId,
            taskTypeRef: serviceTaskTypeId,
            linkedCatalogItemId: nil
        )
        dto.bundlePricingMode = nil

        await createProduct(dto, kind: .service, reset: resetServiceDraft)
    }

    @MainActor
    private func saveGood() async {
        guard goodCanSave, let amount = goodAmount else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let selectedUnit = companyUnits.first(where: { $0.id == goodUnitId })
        let selectedCategory = companyCategories.first(where: { $0.id == goodCategoryId })

        var dto = CreateProductDTO(
            companyId: companyId,
            name: goodName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: nil,
            basePrice: amount,
            unitCost: goodCostAmount,
            unit: selectedUnit?.display,
            pricingUnit: pricingUnit(for: selectedUnit).rawValue,
            unitId: selectedUnit?.id,
            category: selectedCategory?.name,
            categoryId: selectedCategory?.id,
            sku: nil,
            thumbnailUrl: nil,
            kind: ProductCategory.material.derivedKindRaw,
            type: ProductCategory.material.derivedType.rawValue,
            isTaxable: ProductCategory.material.defaultTaxable,
            taskTypeId: nil,
            taskTypeRef: nil,
            linkedCatalogItemId: nil
        )
        dto.bundlePricingMode = nil

        await createProduct(dto, kind: .material, reset: resetGoodDraft)
    }

    @MainActor
    private func createProduct(
        _ dto: CreateProductDTO,
        kind: ProductCategory,
        reset: () -> Void
    ) async {
        let repo = ProductRepository(companyId: companyId)
        do {
            let createdDTO = try await repo.create(dto)
            let model = createdDTO.toModel()
            modelContext.insert(model)
            try? modelContext.save()
            appendSavedProduct(createdDTO, kind: kind)
            reset()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            advance()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveBundle() async {
        guard bundleCanSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let selectedCategory = companyCategories.first(where: { $0.id == bundleCategoryId })

        var dto = CreateProductDTO(
            companyId: companyId,
            name: bundleName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: nil,
            basePrice: effectiveBundlePrice,
            unitCost: nil,
            unit: nil,
            pricingUnit: ProductPricingUnit.flatRate.rawValue,
            unitId: nil,
            category: selectedCategory?.name,
            categoryId: selectedCategory?.id,
            sku: nil,
            thumbnailUrl: nil,
            kind: ProductCategory.bundle.derivedKindRaw,
            type: ProductCategory.bundle.derivedType.rawValue,
            isTaxable: ProductCategory.bundle.defaultTaxable,
            taskTypeId: bundleTaskTypeId,
            taskTypeRef: bundleTaskTypeId,
            linkedCatalogItemId: nil
        )
        dto.bundlePricingMode = bundlePricingMode.rawValue

        let productRepo = ProductRepository(companyId: companyId)
        do {
            let createdDTO = try await productRepo.create(dto)
            let model = createdDTO.toModel()
            modelContext.insert(model)
            try? modelContext.save()
            appendSavedProduct(createdDTO, kind: .bundle)

            let failedChildren = await flushBundleChildren(bundleChildren, bundleProductId: createdDTO.id)
            if !failedChildren.isEmpty {
                unflushedBundleProductId = createdDTO.id
                unflushedBundleChildren = failedChildren
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = "// \(failedChildren.count) CHILD ROW(S) FAILED - TAP RETRY"
                return
            }

            resetBundleDraft()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            advance()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func retryBundleChildren() async {
        guard let bundleId = unflushedBundleProductId, !unflushedBundleChildren.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let failedChildren = await flushBundleChildren(unflushedBundleChildren, bundleProductId: bundleId)
        if failedChildren.isEmpty {
            unflushedBundleProductId = nil
            unflushedBundleChildren = []
            resetBundleDraft()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            advance()
        } else {
            unflushedBundleChildren = failedChildren
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = "// \(failedChildren.count) CHILD ROW(S) STILL FAILING - TAP RETRY"
        }
    }

    @MainActor
    private func flushBundleChildren(
        _ children: [BundleChildDraft],
        bundleProductId: String
    ) async -> [BundleChildDraft] {
        let repo = ProductBundleItemRepository(companyId: companyId)
        var failed: [BundleChildDraft] = []

        for draft in children {
            let dto = CreateProductBundleItemDTO(
                id: UUID().uuidString,
                companyId: companyId,
                bundleProductId: bundleProductId,
                childProductId: draft.id,
                quantity: draft.quantity,
                displayOrder: draft.displayOrder
            )
            do {
                let created = try await repo.create(dto)
                modelContext.insert(created.toModel())
            } catch {
                failed.append(draft)
                print("[GuidedProductSetupFlow] Bundle child insert failed for \(draft.id): \(error)")
            }
        }

        try? modelContext.save()
        return failed
    }

    @MainActor
    private func saveRecipe() async {
        guard recipeCanSave, let productId = recipeProductId else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let repo = ProductRichnessRepository(companyId: companyId)
        var failed: [GuidedProductRecipeDraft] = []
        var successCount = 0

        for draft in recipeDrafts {
            guard let quantity = parseQuantity(draft.quantityText) else {
                failed.append(draft)
                continue
            }

            let dto = CreateProductMaterialDTO(
                productId: productId,
                catalogVariantId: draft.catalogVariantId,
                catalogItemId: nil,
                variantSelector: nil,
                quantityPerUnit: quantity,
                scaledByOptionId: nil,
                unitId: nil,
                notes: draft.notes
            )

            do {
                let created = try await repo.createMaterial(dto)
                let model = created.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
                successCount += 1
            } catch {
                failed.append(draft)
                print("[GuidedProductSetupFlow] Recipe row insert failed for \(draft.catalogVariantId): \(error)")
            }
        }

        try? modelContext.save()
        savedRecipeRowCount += successCount

        if failed.isEmpty {
            resetRecipeDraft()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            advance()
        } else {
            recipeDrafts = failed
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            let savedClause = successCount > 0 ? "\(successCount) SAVED, " : ""
            errorMessage = "// \(savedClause)\(failed.count) RECIPE ROW(S) FAILED - TAP SAVE RECIPE TO RETRY"
        }
    }

    private func appendSavedProduct(_ dto: ProductDTO, kind: ProductCategory) {
        guard !savedProducts.contains(where: { $0.id == dto.id }) else { return }
        savedProducts.append(
            GuidedProductSetupSavedProduct(
                id: dto.id,
                name: dto.name,
                kind: kind,
                basePrice: dto.basePrice
            )
        )
        if kind == .bundle || recipeProductId == nil {
            recipeProductId = dto.id
        }
    }

    // MARK: - Completion

    private func finishSetup() {
        postCompletionNotificationIfNeeded()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }

    private func openStockSetup() {
        postCompletionNotificationIfNeeded()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + (reducedMotion ? 0.05 : 0.25)) {
            NotificationCenter.default.post(name: Notification.Name("OpenGuidedStockSetup"), object: nil)
        }
    }

    private func postCompletionNotificationIfNeeded() {
        guard !savedProducts.isEmpty else { return }
        let userId = dataController.currentUser?.id ?? ""
        let companyId = self.companyId
        guard !userId.isEmpty, !companyId.isEmpty else { return }

        let productClause = "\(savedProducts.count) product \(savedProducts.count == 1 ? "row" : "rows")"
        let recipeClause = savedRecipeRowCount > 0
            ? " and \(savedRecipeRowCount) recipe \(savedRecipeRowCount == 1 ? "row" : "rows")"
            : ""
        let body = "\(productClause)\(recipeClause) saved for estimating."
        Task {
            try? await NotificationRepository.shared.createNotification(.init(
                userId: userId,
                companyId: companyId,
                type: "standard",
                title: "PRODUCT SETUP COMPLETE",
                body: body,
                deepLinkType: "catalog_products",
                persistent: false,
                actionUrl: "/catalog?segment=products",
                actionLabel: "VIEW PRODUCTS"
            ))
            NotificationCenter.default.post(name: .notificationReceived, object: nil)
        }
    }

    // MARK: - Draft helpers

    private func hydrateDefaultUnits() {
        guard serviceUnitId == nil || goodUnitId == nil else { return }

        if serviceUnitId == nil {
            serviceUnitId = companyUnits.first { unit in
                let lower = unit.display.lowercased()
                return lower == "hour" || lower == "hours" || lower == "hr" || lower == "hrs"
            }?.id
        }

        if goodUnitId == nil {
            goodUnitId = companyUnits.first { unit in
                let lower = unit.display.lowercased()
                return lower == "each" || lower == "ea" || lower == "unit" || lower == "pc" || lower == "piece"
            }?.id
        }
    }

    private func assignCategory(_ id: String, to target: GuidedProductSetupCategoryTarget) {
        switch target {
        case .service:
            serviceCategoryId = id
        case .good:
            goodCategoryId = id
        case .bundle:
            bundleCategoryId = id
        }
    }

    private func assignUnit(_ id: String, to target: GuidedProductSetupUnitTarget) {
        switch target {
        case .service:
            serviceUnitId = id
        case .good:
            goodUnitId = id
        }
    }

    private func selectedTaskTypeId(for target: GuidedProductSetupTaskTypeTarget) -> String? {
        switch target {
        case .service:
            return serviceTaskTypeId
        case .bundle:
            return bundleTaskTypeId
        }
    }

    private func assignTaskType(_ id: String, to target: GuidedProductSetupTaskTypeTarget) {
        switch target {
        case .service:
            serviceTaskTypeId = id
        case .bundle:
            bundleTaskTypeId = id
        }
    }

    private func resetServiceDraft() {
        serviceName = ""
        servicePrice = ""
    }

    private func resetGoodDraft() {
        goodName = ""
        goodPrice = ""
        goodUnitCost = ""
    }

    private func resetBundleDraft() {
        bundleName = ""
        bundleOverridePrice = ""
        bundlePricingMode = .auto
        bundleTaskTypeId = nil
        bundleChildren = []
        bundleSearch = ""
        unflushedBundleProductId = nil
        unflushedBundleChildren = []
    }

    private func resetRecipeDraft() {
        recipeSearch = ""
        recipeDrafts = []
    }

    private func toggleBundleChild(_ product: Product) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let index = bundleChildren.firstIndex(where: { $0.id == product.id }) {
            bundleChildren.remove(at: index)
        } else {
            bundleChildren.append(
                BundleChildDraft(
                    id: product.id,
                    quantity: 1,
                    displayOrder: bundleChildren.count
                )
            )
        }
        normalizeBundleDisplayOrder()
    }

    private func adjustBundleQuantity(for id: String, delta: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let index = bundleChildren.firstIndex(where: { $0.id == id }) else { return }
        let nextQuantity = max(1, bundleChildren[index].quantity + delta)
        bundleChildren[index].quantity = nextQuantity
    }

    private func normalizeBundleDisplayOrder() {
        for index in bundleChildren.indices {
            bundleChildren[index].displayOrder = index
        }
    }

    private func toggleRecipeVariant(_ variant: CatalogVariant) {
        guard recipeProductId != nil else { return }
        guard !existingRecipeVariantIdsForTarget.contains(variant.id) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let index = recipeDrafts.firstIndex(where: { $0.catalogVariantId == variant.id }) {
            recipeDrafts.remove(at: index)
        } else {
            recipeDrafts.append(
                GuidedProductRecipeDraft(
                    id: UUID().uuidString,
                    catalogVariantId: variant.id,
                    quantityText: "1",
                    familyName: familyById[variant.catalogItemId]?.name,
                    variantLabel: recipeVariantSuffix(for: variant),
                    unitDisplay: recipeUnitDisplay(for: variant),
                    notes: nil,
                    displayOrder: recipeDrafts.count
                )
            )
        }
        normalizeRecipeDisplayOrder()
    }

    private func appendRecipeDraft(_ pending: PendingProductMaterial) {
        guard !existingRecipeVariantIdsForTarget.contains(pending.catalogVariantId) else { return }
        if let index = recipeDrafts.firstIndex(where: { $0.catalogVariantId == pending.catalogVariantId }) {
            recipeDrafts[index].quantityText = quantityText(pending.quantityPerUnit)
            recipeDrafts[index].familyName = pending.familyName
            recipeDrafts[index].variantLabel = pending.variantLabel
            recipeDrafts[index].unitDisplay = pending.unitDisplay
            recipeDrafts[index].notes = pending.notes
        } else {
            recipeDrafts.append(
                GuidedProductRecipeDraft(
                    id: pending.id,
                    catalogVariantId: pending.catalogVariantId,
                    quantityText: quantityText(pending.quantityPerUnit),
                    familyName: pending.familyName,
                    variantLabel: pending.variantLabel,
                    unitDisplay: pending.unitDisplay,
                    notes: pending.notes,
                    displayOrder: recipeDrafts.count
                )
            )
        }
        normalizeRecipeDisplayOrder()
    }

    private func removeRecipeDraft(id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        recipeDrafts.removeAll { $0.id == id }
        normalizeRecipeDisplayOrder()
    }

    private func normalizeRecipeDisplayOrder() {
        for index in recipeDrafts.indices {
            recipeDrafts[index].displayOrder = index
        }
    }

    private func recipeQuantityBinding(for id: String) -> Binding<String> {
        Binding(
            get: {
                recipeDrafts.first(where: { $0.id == id })?.quantityText ?? ""
            },
            set: { newValue in
                guard let index = recipeDrafts.firstIndex(where: { $0.id == id }) else { return }
                recipeDrafts[index].quantityText = newValue
            }
        )
    }

    private func recipeQuantityIsValid(_ raw: String) -> Bool {
        parseQuantity(raw) != nil
    }

    private func parseQuantity(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quantity = Double(cleaned), quantity > 0 else { return nil }
        return quantity
    }

    private func recipeTargetKindRank(_ kind: ProductCategory) -> Int {
        switch kind {
        case .bundle: return 0
        case .service: return 1
        case .material: return 2
        case .fee: return 3
        }
    }

    private func recipeSearchText(for variant: CatalogVariant) -> String {
        [
            recipeVariantTitle(for: variant),
            recipeVariantMetadata(for: variant),
            variant.sku ?? ""
        ]
        .joined(separator: " ")
    }

    private func recipeVariantTitle(for variant: CatalogVariant) -> String {
        recipeVariantTitle(for: Optional(variant))
    }

    private func recipeVariantTitle(for variant: CatalogVariant?) -> String {
        guard let variant,
              let family = familyById[variant.catalogItemId]
        else { return "Missing stock" }

        let suffix = recipeVariantSuffix(for: variant)
        return suffix.isEmpty ? family.name : "\(family.name) · \(suffix)"
    }

    private func recipeDraftTitle(_ draft: GuidedProductRecipeDraft, variant: CatalogVariant?) -> String {
        if let variant {
            return recipeVariantTitle(for: variant)
        }
        let family = draft.familyName ?? "Stock"
        guard let variantLabel = draft.variantLabel, !variantLabel.isEmpty else { return family }
        return "\(family) · \(variantLabel)"
    }

    private func recipeVariantMetadata(for variant: CatalogVariant) -> String {
        let unit = recipeUnitDisplay(for: variant)
        let quantity = unit.isEmpty ? quantityText(variant.quantity) : "\(quantityText(variant.quantity)) \(unit)"
        if let sku = variant.sku, !sku.isEmpty {
            return "STOCK \(quantity) · \(sku)"
        }
        return "STOCK \(quantity)"
    }

    private func recipeUnitDisplay(for variant: CatalogVariant?) -> String {
        recipeUnitDisplay(for: variant, fallback: nil)
    }

    private func recipeUnitDisplay(for variant: CatalogVariant?, fallback: String?) -> String {
        guard let variant else { return fallback ?? "" }
        if let unitId = variant.unitId,
           let unit = unitById[unitId] {
            return unit.abbreviation ?? unit.display
        }
        if let family = familyById[variant.catalogItemId],
           let unitId = family.defaultUnitId,
           let unit = unitById[unitId] {
            return unit.abbreviation ?? unit.display
        }
        return fallback ?? ""
    }

    private func recipeVariantSuffix(for variant: CatalogVariant) -> String {
        let familyOptions = allCatalogOptions
            .filter { $0.catalogItemId == variant.catalogItemId }
            .sorted { $0.sortOrder < $1.sortOrder }
        let variantValueIds = Set(allVariantOptionValues
            .filter { $0.variantId == variant.id }
            .map(\.optionValueId))
        let valuesById = Dictionary(uniqueKeysWithValues: allCatalogOptionValues.map { ($0.id, $0) })

        var parts: [String] = []
        for option in familyOptions {
            if let value = variantValueIds
                .compactMap({ valuesById[$0] })
                .first(where: { $0.optionId == option.id }) {
                parts.append(value.value)
            }
        }

        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return variant.sku ?? ""
    }

    private func duplicateExists(named rawName: String) -> Bool {
        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return companyProducts.contains {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    private func parseMoney(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func quantityText(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private enum GuidedProductSetupStage: Int, CaseIterable {
    case prime
    case mix
    case service
    case good
    case bundle
    case recipe
    case review

    var next: GuidedProductSetupStage? {
        GuidedProductSetupStage(rawValue: rawValue + 1)
    }

    var previous: GuidedProductSetupStage? {
        GuidedProductSetupStage(rawValue: rawValue - 1)
    }
}

private enum GuidedProductSetupCategoryTarget: String, Identifiable {
    case service
    case good
    case bundle

    var id: String { rawValue }
}

private enum GuidedProductSetupUnitTarget: String, Identifiable {
    case service
    case good

    var id: String { rawValue }
}

private enum GuidedProductSetupTaskTypeTarget: String, Identifiable {
    case service
    case bundle

    var id: String { rawValue }
}

private enum GuidedProductSetupField: Hashable {
    case serviceName
    case servicePrice
    case goodName
    case goodPrice
    case goodCost
    case bundleName
    case bundlePrice
}

private struct GuidedProductSetupSavedProduct: Identifiable {
    let id: String
    let name: String
    let kind: ProductCategory
    let basePrice: Double
}

private struct GuidedRecipeProductTarget: Identifiable {
    let id: String
    let name: String
    let kind: ProductCategory
    let savedThisRun: Bool
}

private struct GuidedProductRecipeDraft: Identifiable, Hashable {
    let id: String
    let catalogVariantId: String
    var quantityText: String
    var familyName: String?
    var variantLabel: String?
    var unitDisplay: String?
    var notes: String?
    var displayOrder: Int
}
