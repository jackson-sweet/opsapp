//
//  CatalogView.swift
//  OPS
//
//  Top-level CATALOG tab. Two segments (STOCK, PRODUCTS) + kebab menu.
//  Replaces the prior Inventory tab.
//

import SwiftUI
import SwiftData

enum CatalogSegment: String, CaseIterable, Identifiable {
    case stock = "STOCK"
    case products = "PRODUCTS"
    var id: String { rawValue }
}

struct CatalogView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.modelContext) private var modelContext

    // Segment selection persisted via AppStorage so the FAB can read the same
    // source of truth and adapt its action set without an explicit parameter.
    @AppStorage("catalog.selectedSegment") private var selectedSegmentRaw: String = CatalogSegment.stock.rawValue

    private var canViewProducts: Bool { permissionStore.can("catalog.products.view") }
    private var canViewOrders:   Bool { permissionStore.can("catalog.orders.view") }
    private var canManage:       Bool { permissionStore.can("catalog.manage") }
    private var canManageProducts: Bool { permissionStore.can("catalog.products.manage") }

    /// Available segments for the current user. Stock is always present
    /// when this view is reachable (catalog.view gates the tab itself);
    /// products is conditional on catalog.products.view.
    private var availableSegments: [CatalogSegment] {
        var result: [CatalogSegment] = [.stock]
        if canViewProducts { result.append(.products) }
        return result
    }

    @State private var showOrders: Bool = false
    @State private var ordersInitialSubSegment: OrdersSubSegment = .suggested
    @State private var showSnapshots: Bool = false
    @State private var showCategoriesManage: Bool = false
    @State private var showTagsManage: Bool = false
    @State private var showUnitsManage: Bool = false
    @State private var showThresholdsManage: Bool = false
    @State private var showDefaultsManage: Bool = false
    @State private var showSetupFlow: Bool = false
    @State private var setupMissingMappingKey: String?
    @State private var showGuidedSetup: Bool = false
    @State private var showGuidedProductSetup: Bool = false
    @State private var showGuidedCatalogSetup: Bool = false
    @State private var showImport: Bool = false
    @State private var showAddVariant: Bool = false
    @State private var showAddFamily: Bool = false
    @State private var showNewService: Bool = false
    @State private var showNewGood: Bool = false
    @State private var showNewBundle: Bool = false

    private var selectedSegment: CatalogSegment {
        let raw = CatalogSegment(rawValue: selectedSegmentRaw) ?? .stock
        // Don't return a segment the user can't access.
        return availableSegments.contains(raw) ? raw : .stock
    }

    private func setSegment(_ segment: CatalogSegment) {
        selectedSegmentRaw = segment.rawValue
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if availableSegments.count > 1 {
                    segmentBar

                    Divider()
                        .background(OPSStyle.Colors.separator)
                }

                Group {
                    switch selectedSegment {
                    case .stock:
                        StockView()
                            .transition(.opacity)
                    case .products:
                        // Local NavigationStack scoped to the products
                        // segment — Stock uses sheet presentation and
                        // doesn't need stack semantics, so wrapping at
                        // the segment level keeps both flows clean.
                        NavigationStack {
                            CatalogProductsListView(onStartSetup: {
                                showGuidedProductSetup = true
                            })
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: selectedSegment)
            }
        }
        .sheet(isPresented: $showOrders) {
            OrdersSheet(initialSubSegment: ordersInitialSubSegment)
                .environmentObject(dataController)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSnapshots)         { SnapshotListView() }
        .sheet(isPresented: $showCategoriesManage)  { CategoriesManageSheet() }
        .sheet(isPresented: $showTagsManage)        { TagsManageSheet() }
        .sheet(isPresented: $showUnitsManage)       { UnitsManageSheet() }
        .sheet(isPresented: $showThresholdsManage)  { ThresholdsManageSheet() }
        .sheet(isPresented: $showDefaultsManage)    { DefaultsManageSheet() }
        .sheet(isPresented: $showSetupFlow, onDismiss: {
            setupMissingMappingKey = nil
        }) {
            CatalogSetupFlowSheet(missingMappingKey: setupMissingMappingKey)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showImport)            {
            CatalogImportSheet()
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showAddVariant) {
            VariantFormSheet()
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showAddFamily) {
            AddFamilySheet()
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showNewService) {
            NewServiceSheet()
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showNewGood) {
            NewGoodSheet()
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showNewBundle) {
            NewBundleSheet()
                .environmentObject(dataController)
        }
        .fullScreenCover(isPresented: $showGuidedSetup) {
            GuidedStockSetupFlow(
                companyId: dataController.currentUser?.companyId ?? "",
                userId: dataController.currentUser?.id ?? ""
            )
            .environmentObject(dataController)
        }
        .fullScreenCover(isPresented: $showGuidedProductSetup) {
            GuidedProductSetupFlow()
                .environmentObject(dataController)
                .environmentObject(permissionStore)
        }
        .fullScreenCover(isPresented: $showGuidedCatalogSetup) {
            GuidedCatalogSetupFlow(
                companyId: dataController.currentUser?.companyId ?? "",
                userId: dataController.currentUser?.id ?? ""
            )
            .environmentObject(dataController)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCatalogOrders"))) { notif in
            let raw = notif.userInfo?["subSegment"] as? String
            ordersInitialSubSegment = OrdersSubSegment(rawValue: raw ?? "") ?? .suggested
            showOrders = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCatalogSetup"))) { notif in
            let key = notif.userInfo?["missingMapping"] as? String
            setupMissingMappingKey = key?.isEmpty == false ? key : nil
            setSegment(.stock)
            showSetupFlow = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenGuidedStockSetup"))) { _ in
            guard permissionStore.can("catalog.manage") else { return }
            setSegment(.stock)
            showGuidedSetup = true
        }
    }

    private var header: some View {
        HStack {
            Text("CATALOG")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            kebabButton
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    private var segmentBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(availableSegments) { segment in
                Button {
                    setSegment(segment)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(segment.rawValue)
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(
                            selectedSegment == segment
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .background(
                            ZStack(alignment: .bottom) {
                                Color.clear
                                if selectedSegment == segment {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.primaryAccent)
                                        .frame(height: 2)
                                }
                            }
                        )
                }
                .accessibilityLabel("\(segment.rawValue) segment")
                .accessibilityAddTraits(selectedSegment == segment ? [.isSelected] : [])
            }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private var kebabButton: some View {
        // The kebab is only useful when at least one of its sections is
        // populated. Snapshots are read-only for anyone with catalog.view.
        let showStockSection: Bool = true  // Snapshots are always visible (read-only).
        let showStockManageRows = canManage
        let showOrdersSection = canViewOrders
        let showProductsSection = canManageProducts
        let showManageSection = canManage

        if showStockSection || showOrdersSection || showProductsSection || showManageSection {
            Menu {
                if showStockSection {
                    Section("STOCK") {
                        if showStockManageRows {
                            Button { showGuidedSetup = true } label: {
                                Label("Guided Setup", systemImage: "wand.and.stars")
                            }
                            Button { showSetupFlow = true } label: {
                                Label("Stock Setup", systemImage: "square.grid.3x3")
                            }
                            Button { showAddVariant = true } label: {
                                Label("Add Variant", systemImage: "plus.app")
                            }
                            Button { showAddFamily = true } label: {
                                Label("Add Family", systemImage: "square.stack.3d.up")
                            }
                        }
                        if permissionStore.can("catalog.import") {
                            Button { showImport = true } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                        }
                        Button { showSnapshots = true } label: {
                            Label("Snapshots", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
                if showProductsSection {
                    Section("PRODUCTS") {
                        Button { showGuidedCatalogSetup = true } label: {
                            Label("Set up your catalog", systemImage: "checklist")
                        }
                        Button { showGuidedProductSetup = true } label: {
                            Label("Guided Setup", systemImage: "wand.and.stars")
                        }
                        Button { showNewService = true } label: {
                            Label("New Service", systemImage: ProductCategory.service.iconName)
                        }
                        Button { showNewGood = true } label: {
                            Label("New Good", systemImage: ProductCategory.material.iconName)
                        }
                        Button { showNewBundle = true } label: {
                            Label("New Bundle", systemImage: ProductCategory.bundle.iconName)
                        }
                    }
                }
                if showManageSection {
                    Section("MANAGE") {
                        if showStockManageRows {
                            Button { showCategoriesManage = true } label: { Label("Categories", systemImage: "folder") }
                            Button { showTagsManage = true }       label: { Label("Tags", systemImage: "tag") }
                            Button { showUnitsManage = true }      label: { Label("Units", systemImage: "ruler") }
                            Button { showThresholdsManage = true } label: { Label("Thresholds", systemImage: "exclamationmark.triangle") }
                            Button { showDefaultsManage = true } label: { Label("Defaults", systemImage: "gearshape") }
                        }
                    }
                }
                if showOrdersSection {
                    Section("ORDERS") {
                        Button { showOrders = true } label: { Label("Orders", systemImage: "shippingbox") }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .accessibilityLabel("Catalog menu")
        }
    }
}
