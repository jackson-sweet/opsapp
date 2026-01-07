//
//  InventoryView.swift
//  OPS
//
//  Main inventory view for tracking materials and supplies
//  Tactical minimalist design
//

import SwiftUI
import SwiftData

struct InventoryView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var selectedTag: String? = nil
    @State private var showingAddItemSheet = false
    @State private var selectedItem: InventoryItem? = nil
    @State private var itemForQuantityAdjustment: InventoryItem? = nil
    @State private var isRefreshing = false

    @Query private var allItems: [InventoryItem]

    private var filteredItems: [InventoryItem] {
        let companyId = dataController.currentUser?.companyId ?? ""

        return allItems.filter { item in
            guard item.companyId == companyId else { return false }
            guard item.deletedAt == nil else { return false }

            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                let nameMatch = item.name.lowercased().contains(searchLower)
                let skuMatch = item.sku?.lowercased().contains(searchLower) ?? false
                let descMatch = item.itemDescription?.lowercased().contains(searchLower) ?? false
                if !nameMatch && !skuMatch && !descMatch {
                    return false
                }
            }

            if let tag = selectedTag {
                if !item.tags.contains(tag) {
                    return false
                }
            }

            return true
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var allTags: [String] {
        let companyId = dataController.currentUser?.companyId ?? ""
        let tags = allItems
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .flatMap { $0.tags }
        return Array(Set(tags)).sorted()
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            AppHeader(headerType: .inventory)

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 70)

                // Search
                SearchBar(searchText: $searchText, placeholder: "Search inventory...")
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing2)

                // Tag filters
                if !allTags.isEmpty {
                    tagFilterSection
                }

                // Content
                ScrollView {
                    if filteredItems.isEmpty {
                        emptyStateView
                            .frame(minHeight: 400)
                    } else {
                        InventoryListView(
                            items: filteredItems,
                            onItemTap: { item in
                                itemForQuantityAdjustment = item
                            },
                            onItemEdit: { item in
                                selectedItem = item
                                showingAddItemSheet = true
                            },
                            onItemDelete: { item in
                                deleteItem(item)
                            }
                        )
                    }

                    Spacer()
                        .frame(height: 100)
                }
                .refreshable {
                    await refreshInventory()
                }
            }

            // Floating add button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        selectedItem = nil
                        showingAddItemSheet = true
                    }) {
                        Image(systemName: OPSStyle.Icons.plus)
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
                            .background(OPSStyle.Colors.primaryAccent)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, OPSStyle.Layout.spacing3)
                    .padding(.bottom, 120)
                }
            }
        }
        .sheet(isPresented: $showingAddItemSheet) {
            InventoryFormSheet(item: selectedItem)
                .environmentObject(dataController)
        }
        .sheet(item: $itemForQuantityAdjustment) { item in
            QuantityAdjustmentSheet(item: item)
                .environmentObject(dataController)
        }
        .onAppear {
            AnalyticsManager.shared.trackScreenView(screenName: .inventory)
        }
    }

    // MARK: - Tag Filter Section

    private var tagFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All chip
                tagChip(title: "All", isSelected: selectedTag == nil) {
                    selectedTag = nil
                }

                ForEach(allTags, id: \.self) { tag in
                    tagChip(title: tag, isSelected: selectedTag == tag) {
                        selectedTag = selectedTag == tag ? nil : tag
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private func tagChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.separator, lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            if isRefreshing {
                ProgressView()
                    .tint(OPSStyle.Colors.primaryAccent)

                Text("Syncing...")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            } else {
                Image(systemName: "shippingbox")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                if !searchText.isEmpty || selectedTag != nil {
                    Text("No items found")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Try adjusting your search or filters")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                } else {
                    Text("No inventory items")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Add items to start tracking inventory")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        Button(action: { Task { await refreshInventory() } }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: OPSStyle.Icons.arrowClockwise)
                                Text("Refresh")
                            }
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                            )
                        }

                        Button(action: { showingAddItemSheet = true }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: OPSStyle.Icons.plus)
                                Text("Add Item")
                            }
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing2)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Refresh

    private func refreshInventory() async {
        guard !isRefreshing else { return }

        await MainActor.run {
            isRefreshing = true
        }

        do {
            try await dataController.syncManager?.syncInventory()
        } catch {
            print("[INVENTORY] Refresh failed: \(error)")
        }

        await MainActor.run {
            isRefreshing = false
        }
    }

    // MARK: - Delete

    private func deleteItem(_ item: InventoryItem) {
        item.deletedAt = Date()
        item.needsSync = true

        Task {
            do {
                try await dataController.apiService.deleteInventoryItem(id: item.id)
                await MainActor.run {
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    item.deletedAt = nil
                    item.needsSync = false
                    print("[INVENTORY] Delete failed: \(error)")
                }
            }
        }
    }
}

#Preview {
    InventoryView()
        .environmentObject(DataController())
        .environmentObject(AppState())
}
