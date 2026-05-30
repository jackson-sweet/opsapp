//
//  CatalogSetupQALocalHost.swift
//  OPS
//
//  DEBUG-only Catalog Setup host backed by in-memory fixture data.
//

#if DEBUG
import SwiftUI
import SwiftData

struct CatalogSetupQALocalHost: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @State private var isReady = false

    private static let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: OPSSchemaV8.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create Catalog Setup QA model container: \(error.localizedDescription)")
        }
    }()

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            if isReady {
                CatalogSetupFlowSheet()
            } else {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("// CATALOG QA")
                        .font(OPSStyle.Typography.pageTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("LOCAL FIXTURE - NO SUPABASE WRITES")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(OPSStyle.Layout.spacing3)
            }
        }
        .modelContainer(Self.modelContainer)
        .onAppear(perform: prepareLocalSession)
    }

    @MainActor
    private func prepareLocalSession() {
        seedModelsIfNeeded(in: Self.modelContainer.mainContext)

        let context = Self.modelContainer.mainContext
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        let user = users.first { $0.id == CatalogSetupQAFixtures.userId } ?? User(
            id: CatalogSetupQAFixtures.userId,
            firstName: "Catalog",
            lastName: "QA",
            role: .owner,
            companyId: CatalogSetupQAFixtures.companyId
        )
        if !users.contains(where: { $0.id == user.id }) {
            context.insert(user)
        }

        dataController.currentUser = user
        dataController.isAuthenticated = true
        dataController.isConnected = true
        dataController.permissionStore = permissionStore

        permissionStore.permissions = [
            "catalog.view": "all",
            "catalog.manage": "all",
            "catalog.products.view": "all",
            "catalog.orders.view": "all",
            "catalog.import": "all"
        ]
        permissionStore.roleName = "Owner"
        permissionStore.roleHierarchy = 100
        permissionStore.roleId = "qa_catalog_setup_owner"
        permissionStore.blockedByFlags = []
        permissionStore.disabledFlags = []
        permissionStore.initialized = true

        try? context.save()
        isReady = true
    }

    @MainActor
    private func seedModelsIfNeeded(in context: ModelContext) {
        let categories = (try? context.fetch(FetchDescriptor<CatalogCategory>())) ?? []
        guard !categories.contains(where: { $0.id == CatalogSetupQAFixtures.categoryId }) else {
            return
        }

        context.insert(CatalogCategory(
            id: CatalogSetupQAFixtures.categoryId,
            companyId: CatalogSetupQAFixtures.companyId,
            name: "QA panel systems",
            sortOrder: 0,
            colorHex: "#4F6F8A",
            defaultWarningThreshold: 40,
            defaultCriticalThreshold: 15
        ))

        context.insert(CatalogUnit(
            id: CatalogSetupQAFixtures.areaUnitId,
            companyId: CatalogSetupQAFixtures.companyId,
            display: "sq ft",
            abbreviation: "sq ft",
            dimension: "area",
            isDefault: true,
            sortOrder: 0
        ))

        context.insert(CatalogUnit(
            id: CatalogSetupQAFixtures.countUnitId,
            companyId: CatalogSetupQAFixtures.companyId,
            display: "ea",
            abbreviation: "ea",
            dimension: "count",
            sortOrder: 1
        ))

        let product = Product(
            id: CatalogSetupQAFixtures.productId,
            companyId: CatalogSetupQAFixtures.companyId,
            name: "QA field panel product",
            type: .material,
            kind: .good,
            basePrice: 18,
            pricingUnit: .sqft
        )
        product.categoryId = CatalogSetupQAFixtures.categoryId
        product.unitId = CatalogSetupQAFixtures.areaUnitId
        context.insert(product)

        seedProductOptions(in: context)
        seedDuplicateMatrixFixture(in: context)
    }

    @MainActor
    private func seedProductOptions(in context: ModelContext) {
        context.insert(ProductOption(
            id: CatalogSetupQAFixtures.finishProductOptionId,
            productId: CatalogSetupQAFixtures.productId,
            name: "Finish",
            kind: .select,
            affectsPrice: true,
            affectsRecipe: true,
            sortOrder: 0
        ))
        context.insert(ProductOption(
            id: CatalogSetupQAFixtures.gaugeProductOptionId,
            productId: CatalogSetupQAFixtures.productId,
            name: "Gauge",
            kind: .select,
            affectsPrice: true,
            affectsRecipe: true,
            sortOrder: 1
        ))

        context.insert(ProductOptionValue(
            id: CatalogSetupQAFixtures.finishProductValueRawId,
            optionId: CatalogSetupQAFixtures.finishProductOptionId,
            value: "Raw",
            sortOrder: 0
        ))
        context.insert(ProductOptionValue(
            id: CatalogSetupQAFixtures.finishProductValueCoatedId,
            optionId: CatalogSetupQAFixtures.finishProductOptionId,
            value: "Coated",
            sortOrder: 1
        ))
        context.insert(ProductOptionValue(
            id: CatalogSetupQAFixtures.gaugeProductValueLightId,
            optionId: CatalogSetupQAFixtures.gaugeProductOptionId,
            value: "Light",
            sortOrder: 0
        ))
        context.insert(ProductOptionValue(
            id: CatalogSetupQAFixtures.gaugeProductValueHeavyId,
            optionId: CatalogSetupQAFixtures.gaugeProductOptionId,
            value: "Heavy",
            sortOrder: 1
        ))
    }

    @MainActor
    private func seedDuplicateMatrixFixture(in context: ModelContext) {
        context.insert(CatalogItem(
            id: CatalogSetupQAFixtures.draftCatalogItemId,
            companyId: CatalogSetupQAFixtures.companyId,
            name: "QA duplicate matrix fixture",
            categoryId: CatalogSetupQAFixtures.categoryId,
            defaultUnitId: CatalogSetupQAFixtures.areaUnitId
        ))

        context.insert(CatalogOption(
            id: CatalogSetupQAFixtures.finishAttributeId,
            catalogItemId: CatalogSetupQAFixtures.draftCatalogItemId,
            name: "Finish",
            sortOrder: 0
        ))
        context.insert(CatalogOption(
            id: CatalogSetupQAFixtures.gaugeAttributeId,
            catalogItemId: CatalogSetupQAFixtures.draftCatalogItemId,
            name: "Gauge",
            sortOrder: 1
        ))

        for value in CatalogSetupQAFixtures.draftAttributes().flatMap(\.values) {
            let optionId = value.id.hasPrefix("qa_catalog_setup_finish")
                ? CatalogSetupQAFixtures.finishAttributeId
                : CatalogSetupQAFixtures.gaugeAttributeId
            context.insert(CatalogOptionValue(
                id: value.id,
                optionId: optionId,
                value: value.value
            ))
        }

        context.insert(CatalogVariant(
            id: CatalogSetupQAFixtures.duplicateVariantId,
            companyId: CatalogSetupQAFixtures.companyId,
            catalogItemId: CatalogSetupQAFixtures.draftCatalogItemId,
            sku: CatalogSetupQAFixtures.duplicateSKU,
            quantity: 8,
            unitId: CatalogSetupQAFixtures.areaUnitId
        ))

        for valueId in CatalogSetupQAFixtures.duplicateMatrixValueIds {
            context.insert(CatalogVariantOptionValue(
                variantId: CatalogSetupQAFixtures.duplicateVariantId,
                optionValueId: valueId
            ))
        }
    }
}
#endif
