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
    @Environment(\.modelContext) private var modelContext

    // Segment selection persisted via AppStorage so the FAB can read the same
    // source of truth and adapt its action set without an explicit parameter.
    @AppStorage("catalog.selectedSegment") private var selectedSegmentRaw: String = CatalogSegment.stock.rawValue

    @State private var showOrders: Bool = false
    @State private var showSnapshots: Bool = false
    @State private var showCategoriesManage: Bool = false
    @State private var showTagsManage: Bool = false
    @State private var showUnitsManage: Bool = false
    @State private var showThresholdsManage: Bool = false
    @State private var showDefaultsManage: Bool = false
    @State private var showImport: Bool = false

    private var selectedSegment: CatalogSegment {
        CatalogSegment(rawValue: selectedSegmentRaw) ?? .stock
    }

    private func setSegment(_ segment: CatalogSegment) {
        selectedSegmentRaw = segment.rawValue
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                segmentBar

                Divider()
                    .background(OPSStyle.Colors.separator)

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
        .sheet(isPresented: $showOrders)            { OrdersSheet() }
        .sheet(isPresented: $showSnapshots)         { SnapshotListView() }
        .sheet(isPresented: $showCategoriesManage)  { CategoriesManageSheet() }
        .sheet(isPresented: $showTagsManage)        { TagsManageSheet() }
        .sheet(isPresented: $showUnitsManage)       { UnitsManageSheet() }
        .sheet(isPresented: $showThresholdsManage)  { ThresholdsManageSheet() }
        .sheet(isPresented: $showDefaultsManage)    { DefaultsManageSheet() }
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
            ForEach(CatalogSegment.allCases) { segment in
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

    private var kebabButton: some View {
        Menu {
            Section("STOCK") {
                Button { showSnapshots = true }        label: { Label("Snapshots", systemImage: "clock.arrow.circlepath") }
                Button { showCategoriesManage = true } label: { Label("Categories", systemImage: "folder") }
                Button { showTagsManage = true }       label: { Label("Tags", systemImage: "tag") }
                Button { showUnitsManage = true }      label: { Label("Units", systemImage: "ruler") }
                Button { showThresholdsManage = true } label: { Label("Thresholds", systemImage: "exclamationmark.triangle") }
            }
            Section("ORDERS") {
                Button { showOrders = true } label: { Label("Orders", systemImage: "shippingbox") }
            }
            Section("SETUP") {
                Button { showDefaultsManage = true } label: { Label("Defaults", systemImage: "gearshape") }
                Button { showImport = true }         label: { Label("Import…", systemImage: "square.and.arrow.down") }
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
