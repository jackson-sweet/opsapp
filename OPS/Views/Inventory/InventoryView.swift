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
    @State private var selectedTags: Set<String> = []
    @State private var showingAddItemSheet = false
    @State private var selectedItem: InventoryItem? = nil
    @State private var itemForQuantityAdjustment: InventoryItem? = nil
    @State private var isRefreshing = false
    @State private var showingImportSheet = false

    // Pinch-to-zoom scale
    @AppStorage("inventoryCardScale") private var cardScale: Double = 1.0
    @State private var gestureStartScale: CGFloat = 1.0
    private let minScale: CGFloat = 0.8
    private let maxScale: CGFloat = 1.5

    // Sort options - default will be set based on whether tags exist
    @State private var sortMode: InventorySortMode = .tag

    enum InventorySortMode: String, CaseIterable {
        case tag = "TAG"
        case name = "NAME"
        case quantity = "QUANTITY"
        case threshold = "THRESHOLD"
    }

    // Selection mode
    @State private var isSelectionMode = false
    @State private var selectedItemIds: Set<String> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkAdjustSheet = false
    @State private var showingBulkTagsSheet = false
    @State private var showingManageTagsSheet = false
    @State private var showingSelectionTools = false
    @State private var activeSelectionFilter: SelectionFilter? = nil
    @State private var renamingTag: String? = nil
    @State private var renameTagText: String = ""
    @State private var selectionKeywordText: String = ""

    struct SelectionFilter: Identifiable, Equatable {
        let id = UUID()
        let type: FilterType
        let value: String

        enum FilterType {
            case tag
            case keyword
        }

        var displayText: String {
            value
        }

        var icon: String {
            switch type {
            case .tag:
                return "tag"
            case .keyword:
                return "magnifyingglass"
            }
        }
    }

    @Query private var allItems: [InventoryItem]
    @Query private var allInventoryTags: [InventoryTag]

    private var companyTags: [InventoryTag] {
        let companyId = dataController.currentUser?.companyId ?? ""
        return allInventoryTags.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }

    private var filteredItems: [InventoryItem] {
        let companyId = dataController.currentUser?.companyId ?? ""

        let filtered = allItems.filter { item in
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

            // Multi-tag filtering: item must have ANY of the selected tags (OR logic)
            if !selectedTags.isEmpty {
                let itemTagsLower = Set(item.tagNames.map { $0.lowercased() })
                let selectedTagsLower = Set(selectedTags.map { $0.lowercased() })
                if itemTagsLower.isDisjoint(with: selectedTagsLower) {
                    return false
                }
            }

            return true
        }

        // Sort based on current sort mode
        switch sortMode {
        case .tag:
            // Sort by first tag alphabetically, then by name
            return filtered.sorted { item1, item2 in
                let tag1 = item1.tagNames.sorted().first ?? ""
                let tag2 = item2.tagNames.sorted().first ?? ""
                if tag1 != tag2 {
                    // Items with no tags go last
                    if tag1.isEmpty { return false }
                    if tag2.isEmpty { return true }
                    return tag1.localizedCaseInsensitiveCompare(tag2) == .orderedAscending
                }
                return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .quantity:
            // Sort by quantity descending (highest first), then by name
            return filtered.sorted { item1, item2 in
                if item1.quantity != item2.quantity {
                    return item1.quantity > item2.quantity
                }
                return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
        case .threshold:
            // Sort by threshold status (critical > warning > normal), then by name
            return filtered.sorted { item1, item2 in
                let status1 = item1.effectiveThresholdStatus()
                let status2 = item2.effectiveThresholdStatus()
                if status1 != status2 {
                    return status1 > status2  // Higher status (critical) comes first
                }
                return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            }
        }
    }

    private var allTags: [String] {
        let companyId = dataController.currentUser?.companyId ?? ""
        let tagNames = allItems
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .flatMap { $0.tagNames }
        return Array(Set(tagNames)).sorted()
    }

    private var companyItems: [InventoryItem] {
        let companyId = dataController.currentUser?.companyId ?? ""
        return allItems.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            AppHeader(headerType: .inventory)

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 70)

                // Search and Sort
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    SearchBar(searchText: $searchText, placeholder: "Search inventory...")

                    // Sort toggle
                    sortToggleButton
                }
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
                            isSelectionMode: isSelectionMode,
                            selectedItemIds: $selectedItemIds,
                            scale: CGFloat(cardScale),
                            onItemTap: { item in
                                if isSelectionMode {
                                    toggleItemSelection(item)
                                } else {
                                    itemForQuantityAdjustment = item
                                }
                            },
                            onItemEdit: { item in
                                selectedItem = item
                                showingAddItemSheet = true
                            },
                            onItemDelete: { item in
                                deleteItem(item)
                            },
                            onItemSelect: { item in
                                enterSelectionMode(with: item)
                            }
                        )
                    }

                    Spacer()
                        .frame(height: isSelectionMode ? 160 : 100)
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newScale = gestureStartScale * value
                            cardScale = Double(min(max(newScale, minScale), maxScale))
                        }
                        .onEnded { _ in
                            gestureStartScale = CGFloat(cardScale)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                )
                .onAppear {
                    gestureStartScale = CGFloat(cardScale)
                }
                .refreshable {
                    await refreshInventory()
                }
            }

            // Selection mode footer
            if isSelectionMode {
                selectionFooter
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
        .sheet(isPresented: $showingImportSheet) {
            SpreadsheetImportSheet()
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingBulkAdjustSheet) {
            BulkQuantityAdjustmentSheet(
                items: selectedItems,
                onComplete: {
                    exitSelectionMode()
                }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingBulkTagsSheet) {
            BulkTagsSheet(
                items: selectedItems,
                onComplete: {
                    // BulkTagsSheet handles all syncing internally
                }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingManageTagsSheet) {
            InventoryManageTagsSheet(
                items: companyItems,
                onRenameTag: { oldTag, newTag in
                    renameTagGlobally(from: oldTag, to: newTag)
                },
                onDeleteTag: { tag in
                    deleteTagGlobally(tag)
                }
            )
        }
        .sheet(isPresented: $showingSelectionTools) {
            selectionToolsSheet
        }
        .onAppear {
            AnalyticsManager.shared.trackScreenView(screenName: .inventory)
            // Set default sort mode: by tag if tags exist, otherwise by name
            if allTags.isEmpty && sortMode == .tag {
                sortMode = .name
            }
        }
    }

    // MARK: - Sort Toggle Button

    private var sortIcon: String {
        switch sortMode {
        case .tag: return "tag"
        case .name: return "arrow.up.arrow.down"
        case .quantity: return "number"
        case .threshold: return "exclamationmark.triangle"
        }
    }

    private var sortIconColor: Color {
        switch sortMode {
        case .threshold: return OPSStyle.Colors.warningStatus
        default: return OPSStyle.Colors.secondaryText
        }
    }

    private var sortToggleButton: some View {
        Menu {
            ForEach(InventorySortMode.allCases, id: \.self) { mode in
                Button(action: { sortMode = mode }) {
                    HStack {
                        Text(mode.rawValue)
                        if sortMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: sortIcon)
                    .font(.system(size: 12))
                    .foregroundColor(sortIconColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(sortMode == .threshold ? OPSStyle.Colors.warningStatus.opacity(0.5) : OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Tag Filter Section

    private var tagFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Clear all chip (only shown when tags are selected)
                if !selectedTags.isEmpty {
                    tagChip(title: "Clear", isSelected: false, showClearIcon: true) {
                        selectedTags.removeAll()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                ForEach(allTags, id: \.self) { tag in
                    let isSelected = selectedTags.contains(tag)
                    tagChip(title: tag, isSelected: isSelected) {
                        if isSelected {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private func tagChip(title: String, isSelected: Bool, showClearIcon: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if showClearIcon {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(OPSStyle.Typography.captionBold)
            }
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

                if !searchText.isEmpty || !selectedTags.isEmpty {
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

                    Text("Add items or import from a spreadsheet")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    VStack(spacing: OPSStyle.Layout.spacing3) {
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

                        // Import button
                        Button(action: { showingImportSheet = true }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import from Spreadsheet")
                            }
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
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

    // MARK: - Selection Mode

    private var selectedItems: [InventoryItem] {
        filteredItems.filter { selectedItemIds.contains($0.id) }
    }

    private func enterSelectionMode(with item: InventoryItem) {
        isSelectionMode = true
        appState.isInventorySelectionMode = true
        selectedItemIds = [item.id]
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        appState.isInventorySelectionMode = false
        selectedItemIds = []
    }

    private func toggleItemSelection(_ item: InventoryItem) {
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
            if selectedItemIds.isEmpty {
                exitSelectionMode()
            }
        } else {
            selectedItemIds.insert(item.id)
        }
    }

    private func selectAll() {
        selectedItemIds = Set(filteredItems.map { $0.id })
        activeSelectionFilter = nil
    }

    private func selectNone() {
        selectedItemIds = []
        activeSelectionFilter = nil
    }

    private func invertSelection() {
        let allIds = Set(filteredItems.map { $0.id })
        selectedItemIds = allIds.subtracting(selectedItemIds)
        activeSelectionFilter = nil
    }

    private func syncTagChanges(for items: [InventoryItem]) {
        Task {
            for item in items where item.needsSync {
                do {
                    let updates: [String: Any] = [
                        BubbleFields.InventoryItem.tags: item.tagIds
                    ]
                    try await dataController.apiService.updateInventoryItem(id: item.id, updates: updates)
                    await MainActor.run {
                        item.needsSync = false
                        item.lastSyncedAt = Date()
                    }
                } catch {
                    print("[INVENTORY] Failed to sync tags for \(item.name): \(error)")
                }
            }
            await MainActor.run {
                try? modelContext.save()
            }
        }
    }

    private func selectByTag(_ tag: String) {
        let matchingIds = filteredItems.filter { $0.tagNames.contains(tag) }.map { $0.id }
        selectedItemIds = Set(matchingIds)
        activeSelectionFilter = SelectionFilter(type: .tag, value: tag)
    }

    private func selectByKeyword(_ keyword: String) {
        let searchLower = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard !searchLower.isEmpty else { return }

        let matchingIds = filteredItems.filter { item in
            item.name.lowercased().contains(searchLower) ||
            (item.sku?.lowercased().contains(searchLower) ?? false) ||
            (item.itemDescription?.lowercased().contains(searchLower) ?? false) ||
            item.tagNames.contains { $0.lowercased().contains(searchLower) }
        }.map { $0.id }

        selectedItemIds = Set(matchingIds)
        activeSelectionFilter = SelectionFilter(type: .keyword, value: keyword)
    }

    private func clearSelectionFilter() {
        activeSelectionFilter = nil
        // Reset to select all
        selectedItemIds = Set(filteredItems.map { $0.id })
    }

    private func renameTagGlobally(from oldTag: String, to newTag: String) {
        let trimmedNew = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmedNew.isEmpty, trimmedNew != oldTag else { return }

        // Find the InventoryTag entity with this name
        guard let tag = companyTags.first(where: { $0.name.lowercased() == oldTag.lowercased() }) else { return }

        // Rename the tag itself
        tag.name = trimmedNew
        tag.needsSync = true

        try? modelContext.save()

        // Sync the tag rename to API
        Task {
            do {
                let updates = InventoryTagDTO.dictionaryFrom(tag)
                try await dataController.apiService.updateTag(id: tag.id, updates: updates)
                await MainActor.run {
                    tag.needsSync = false
                    tag.lastSyncedAt = Date()
                    try? modelContext.save()
                }
            } catch {
                print("[INVENTORY] Failed to sync tag rename: \(error)")
            }
        }
    }

    private func deleteTagGlobally(_ tagName: String) {
        // Find the InventoryTag entity with this name
        guard let tag = companyTags.first(where: { $0.name.lowercased() == tagName.lowercased() }) else { return }

        // Remove this tag from all items
        for item in companyItems {
            if item.tags.contains(where: { $0.id == tag.id }) {
                item.removeTag(tag)
            }
        }

        // Soft delete the tag
        tag.deletedAt = Date()
        tag.needsSync = true

        try? modelContext.save()

        // Sync deletion to API
        Task {
            do {
                try await dataController.apiService.deleteTag(id: tag.id)
                await MainActor.run {
                    tag.needsSync = false
                    try? modelContext.save()
                }
            } catch {
                print("[INVENTORY] Failed to sync tag delete: \(error)")
            }

            // Sync item updates
            for item in companyItems where item.needsSync {
                do {
                    let updates = InventoryItemDTO.dictionaryFrom(item)
                    try await dataController.apiService.updateInventoryItem(id: item.id, updates: updates)
                    await MainActor.run {
                        item.needsSync = false
                        item.lastSyncedAt = Date()
                    }
                } catch {
                    print("[INVENTORY] Failed to sync item after tag delete for \(item.name): \(error)")
                }
            }
            await MainActor.run {
                try? modelContext.save()
            }
        }
    }

    private func deleteSelectedItems() {
        let itemsToDelete = selectedItems
        let itemIds = itemsToDelete.map { $0.id }

        // Mark all items as deleted immediately (optimistic update)
        for item in itemsToDelete {
            item.deletedAt = Date()
            item.needsSync = true
        }

        // Save locally and exit selection mode immediately
        try? modelContext.save()
        exitSelectionMode()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Capture apiService for background task
        let apiService = dataController.apiService

        // Sync deletions to Bubble in background (fire and forget)
        Task.detached(priority: .background) {
            print("[INVENTORY] 🗑️ Starting background deletion of \(itemIds.count) items")
            for itemId in itemIds {
                do {
                    try await apiService.deleteInventoryItem(id: itemId)
                } catch {
                    print("[INVENTORY] ❌ Background delete failed for \(itemId): \(error)")
                    // Item stays marked as deleted locally with needsSync = true
                    // Will be retried on next sync
                }
            }
            print("[INVENTORY] ✅ Background deletion complete")
        }
    }

    // MARK: - Selection Footer

    private var selectionFooter: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Active filter pill
                if let filter = activeSelectionFilter {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterPill(filter)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, 10)
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                }

                VStack(spacing: OPSStyle.Layout.spacing4) {
                    // Selection tools button
                    Button(action: { showingSelectionTools = true }) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: "checklist")
                                .font(.system(size: 14))
                            Text("SELECTION TOOLS")
                                .font(OPSStyle.Typography.captionBold)
                            Spacer()
                            Text("\(selectedItemIds.count) selected")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, 12)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Action buttons
                    HStack(spacing: OPSStyle.Layout.spacing3) {
                        // Adjust button
                        Button(action: { showingBulkAdjustSheet = true }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: "plusminus")
                                Text("ADJUST")
                            }
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(selectedItemIds.isEmpty ? OPSStyle.Colors.tertiaryText : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedItemIds.isEmpty ? OPSStyle.Colors.cardBackgroundDark : Color.white)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(selectedItemIds.isEmpty ? OPSStyle.Colors.cardBorder : Color.clear, lineWidth: 1)
                            )
                        }
                        .disabled(selectedItemIds.isEmpty)
                        .buttonStyle(PlainButtonStyle())

                        // Tags button
                        Button(action: { showingBulkTagsSheet = true }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: "tag")
                                Text("TAGS")
                            }
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(selectedItemIds.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(selectedItemIds.isEmpty ? OPSStyle.Colors.cardBorder : OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                            )
                        }
                        .disabled(selectedItemIds.isEmpty)
                        .buttonStyle(PlainButtonStyle())

                        // Delete button
                        Button(action: { showingDeleteConfirmation = true }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: OPSStyle.Icons.trash)
                                Text("DELETE")
                            }
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(selectedItemIds.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.errorStatus)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(selectedItemIds.isEmpty ? OPSStyle.Colors.cardBorder : OPSStyle.Colors.errorStatus.opacity(0.5), lineWidth: 1)
                            )
                        }
                        .disabled(selectedItemIds.isEmpty)
                        .buttonStyle(PlainButtonStyle())

                        // Done button
                        Button(action: { exitSelectionMode() }) {
                            Text("DONE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .padding(.vertical, 14)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.background)
                .overlay(
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1),
                    alignment: .top
                )
            }
            .padding(.bottom, 90) // Account for tab bar
        }
        .alert("Delete \(selectedItemIds.count) Items?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedItems()
            }
        } message: {
            Text("This will permanently delete the selected items. This cannot be undone.")
        }
    }

    private func filterPill(_ filter: SelectionFilter) -> some View {
        Button(action: { clearSelectionFilter() }) {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 10))
                Text(filter.displayText)
                    .font(OPSStyle.Typography.smallCaption)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Selection Tools Sheet

    private var selectionToolsSheet: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Quick actions
                        VStack(spacing: 1) {
                            selectionToolRow(icon: "checkmark.circle", title: "Select All", subtitle: "Select all \(filteredItems.count) items") {
                                selectAll()
                                showingSelectionTools = false
                            }

                            selectionToolRow(icon: "circle", title: "Select None", subtitle: "Clear selection") {
                                selectNone()
                                showingSelectionTools = false
                            }

                            selectionToolRow(icon: "arrow.triangle.2.circlepath", title: "Invert Selection", subtitle: "Toggle all \(filteredItems.count) items") {
                                invertSelection()
                                showingSelectionTools = false
                            }
                        }
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.top, OPSStyle.Layout.spacing3)

                        // Keyword search section
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("BY KEYWORD")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)

                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                TextField("Search name, SKU, description...", text: $selectionKeywordText)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .submitLabel(.search)
                                    .onSubmit {
                                        if !selectionKeywordText.trimmingCharacters(in: .whitespaces).isEmpty {
                                            selectByKeyword(selectionKeywordText)
                                            showingSelectionTools = false
                                        }
                                    }

                                if !selectionKeywordText.isEmpty {
                                    Button(action: { selectionKeywordText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.vertical, 10)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )

                            Button(action: {
                                if !selectionKeywordText.trimmingCharacters(in: .whitespaces).isEmpty {
                                    selectByKeyword(selectionKeywordText)
                                    showingSelectionTools = false
                                }
                            }) {
                                Text("SELECT")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(selectionKeywordText.trimmingCharacters(in: .whitespaces).isEmpty ? OPSStyle.Colors.tertiaryText : .black)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                                    .padding(.vertical, 10)
                                    .background(selectionKeywordText.trimmingCharacters(in: .whitespaces).isEmpty ? OPSStyle.Colors.cardBackgroundDark : Color.white)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(selectionKeywordText.trimmingCharacters(in: .whitespaces).isEmpty ? OPSStyle.Colors.cardBorder : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(selectionKeywordText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                        // Match count preview
                        if !selectionKeywordText.trimmingCharacters(in: .whitespaces).isEmpty {
                            let matchCount = filteredItems.filter { item in
                                let searchLower = selectionKeywordText.lowercased()
                                return item.name.lowercased().contains(searchLower) ||
                                    (item.sku?.lowercased().contains(searchLower) ?? false) ||
                                    (item.itemDescription?.lowercased().contains(searchLower) ?? false) ||
                                    item.tagNames.contains { $0.lowercased().contains(searchLower) }
                            }.count

                            Text("\(matchCount) items match")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(matchCount > 0 ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing4)

                    // Tags section
                    if !allTags.isEmpty {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("BY TAG")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)

                            VStack(spacing: 1) {
                                ForEach(allTags, id: \.self) { tag in
                                    let tagCount = filteredItems.filter { $0.tagNames.contains(tag) }.count
                                    selectionToolRow(icon: "tag", title: tag, subtitle: "\(tagCount) items") {
                                        selectByTag(tag)
                                        showingSelectionTools = false
                                    }
                                }
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }
                        .padding(.top, OPSStyle.Layout.spacing4)
                    }

                        Spacer()
                            .frame(height: OPSStyle.Layout.spacing4)
                    }
                }
            }
            .onDisappear {
                selectionKeywordText = ""
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SELECTION TOOLS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingSelectionTools = false }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func selectionToolRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    InventoryView()
        .environmentObject(DataController())
        .environmentObject(AppState())
}
