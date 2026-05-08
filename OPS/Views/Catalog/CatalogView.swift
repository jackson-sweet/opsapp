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
                            CatalogProductsListView()
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCatalogOrders"))) { notif in
            let raw = notif.userInfo?["subSegment"] as? String
            ordersInitialSubSegment = OrdersSubSegment(rawValue: raw ?? "") ?? .suggested
            showOrders = true
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
        let showSetupSection = canManage

        if showStockSection || showOrdersSection || showSetupSection {
            Menu {
                if showStockSection {
                    Section("STOCK") {
                        Button { showSnapshots = true } label: {
                            Label("Snapshots", systemImage: "clock.arrow.circlepath")
                        }
                        if showStockManageRows {
                            Button { showCategoriesManage = true } label: { Label("Categories", systemImage: "folder") }
                            Button { showTagsManage = true }       label: { Label("Tags", systemImage: "tag") }
                            Button { showUnitsManage = true }      label: { Label("Units", systemImage: "ruler") }
                            Button { showThresholdsManage = true } label: { Label("Thresholds", systemImage: "exclamationmark.triangle") }
                        }
                    }
                }
                if showOrdersSection {
                    Section("ORDERS") {
                        Button { showOrders = true } label: { Label("Orders", systemImage: "shippingbox") }
                    }
                }
                if showSetupSection {
                    Section("SETUP") {
                        if canManage {
                            Button { showDefaultsManage = true } label: { Label("Defaults", systemImage: "gearshape") }
                        }
                        // Import lives in the FAB while still a stub — re-add here when real.
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
