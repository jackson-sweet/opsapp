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
    @State private var showingImportSheet = false

    // Selection mode
    @State private var isSelectionMode = false
    @State private var selectedItemIds: Set<String> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkAdjustSheet = false
    @State private var showingManageTagsSheet = false
    @State private var showingSelectionTools = false
    @State private var activeSelectionFilter: SelectionFilter? = nil
    @State private var renamingTag: String? = nil
    @State private var renameTagText: String = ""

    struct SelectionFilter: Identifiable, Equatable {
        let id = UUID()
        let type: FilterType
        let value: String

        enum FilterType {
            case tag
        }

        var displayText: String {
            value
        }
    }

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
                            isSelectionMode: isSelectionMode,
                            selectedItemIds: $selectedItemIds,
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
                .refreshable {
                    await refreshInventory()
                }
            }

            // Selection mode footer
            if isSelectionMode {
                selectionFooter
            }

            // Floating add button (hidden in selection mode)
            if !isSelectionMode {
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
        selectedItemIds = [item.id]
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func exitSelectionMode() {
        isSelectionMode = false
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

    private func selectByTag(_ tag: String) {
        let matchingIds = filteredItems.filter { $0.tags.contains(tag) }.map { $0.id }
        selectedItemIds = Set(matchingIds)
        activeSelectionFilter = SelectionFilter(type: .tag, value: tag)
    }

    private func clearSelectionFilter() {
        activeSelectionFilter = nil
        // Reset to select all
        selectedItemIds = Set(filteredItems.map { $0.id })
    }

    private func renameTagGlobally(from oldTag: String, to newTag: String) {
        let trimmedNew = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmedNew.isEmpty, trimmedNew != oldTag else { return }

        for item in companyItems {
            if item.tags.contains(oldTag) {
                var updatedTags = item.tags
                if let index = updatedTags.firstIndex(of: oldTag) {
                    updatedTags[index] = trimmedNew
                }
                item.tagsString = updatedTags.joined(separator: ",")
                item.needsSync = true
            }
        }

        try? modelContext.save()

        // Sync changes to API
        Task {
            for item in companyItems where item.needsSync {
                do {
                    let updates: [String: Any] = [
                        BubbleFields.InventoryItem.tags: item.tags
                    ]
                    try await dataController.apiService.updateInventoryItem(id: item.id, updates: updates)
                    await MainActor.run {
                        item.needsSync = false
                        item.lastSyncedAt = Date()
                    }
                } catch {
                    print("[INVENTORY] Failed to sync tag rename for \(item.name): \(error)")
                }
            }
            await MainActor.run {
                try? modelContext.save()
            }
        }
    }

    private func deleteTagGlobally(_ tag: String) {
        for item in companyItems {
            if item.tags.contains(tag) {
                var updatedTags = item.tags
                updatedTags.removeAll { $0 == tag }
                item.tagsString = updatedTags.joined(separator: ",")
                item.needsSync = true
            }
        }

        try? modelContext.save()

        // Sync changes to API
        Task {
            for item in companyItems where item.needsSync {
                do {
                    let updates: [String: Any] = [
                        BubbleFields.InventoryItem.tags: item.tags
                    ]
                    try await dataController.apiService.updateInventoryItem(id: item.id, updates: updates)
                    await MainActor.run {
                        item.needsSync = false
                        item.lastSyncedAt = Date()
                    }
                } catch {
                    print("[INVENTORY] Failed to sync tag delete for \(item.name): \(error)")
                }
            }
            await MainActor.run {
                try? modelContext.save()
            }
        }
    }

    private func deleteSelectedItems() {
        let itemsToDelete = selectedItems

        for item in itemsToDelete {
            item.deletedAt = Date()
            item.needsSync = true
        }

        Task {
            for item in itemsToDelete {
                do {
                    try await dataController.apiService.deleteInventoryItem(id: item.id)
                } catch {
                    await MainActor.run {
                        item.deletedAt = nil
                        item.needsSync = false
                        print("[INVENTORY] Delete failed for \(item.name): \(error)")
                    }
                }
            }

            await MainActor.run {
                try? modelContext.save()
                exitSelectionMode()

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
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
                Image(systemName: "tag")
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
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing3)

                    // Tags section
                    if !allTags.isEmpty {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            HStack {
                                Text("BY TAG")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                                Spacer()

                                Button(action: {
                                    showingSelectionTools = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showingManageTagsSheet = true
                                    }
                                }) {
                                    Text("MANAGE")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)

                            VStack(spacing: 1) {
                                ForEach(allTags, id: \.self) { tag in
                                    let tagCount = filteredItems.filter { $0.tags.contains(tag) }.count
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
                }
            }
            .navigationTitle("SELECTION TOOLS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
