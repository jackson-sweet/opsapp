//
//  ImportPreviewView.swift
//  OPS
//
//  Preview parsed inventory items before import
//  Tactical minimalist design
//

import SwiftUI

struct ImportPreviewView: View {
    @Binding var items: [ParsedInventoryItem]
    @Binding var selectedItemIds: Set<UUID>
    let onImport: () -> Void

    @State private var filterMode: FilterMode = .all
    @State private var showingManageTags: Bool = false
    @State private var showingKeywordSearch: Bool = false
    @State private var keywordSearchText: String = ""
    @State private var activeFilters: [ActiveFilter] = []
    @State private var editingItemId: UUID? = nil
    @State private var editName: String = ""
    @State private var editQuantity: String = ""
    @State private var editTags: [String] = []
    @State private var editNewTag: String = ""
    @State private var renamingTag: String? = nil
    @State private var renameTagText: String = ""
    @State private var showingSelectionTools: Bool = false

    enum FilterMode: String, CaseIterable {
        case all = "ALL"
        case valid = "VALID"
        case errors = "ISSUES"
        case duplicates = "DUPES"
    }

    struct ActiveFilter: Identifiable, Equatable {
        let id = UUID()
        let type: FilterType
        let value: String

        enum FilterType {
            case keyword
            case tag
        }

        var displayText: String {
            switch type {
            case .keyword: return "\"\(value)\""
            case .tag: return value
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredItems: [ParsedInventoryItem] {
        switch filterMode {
        case .all: return items
        case .valid: return items.filter { $0.isValid && !$0.isDuplicate }
        case .errors: return items.filter { $0.hasErrors }
        case .duplicates: return items.filter { $0.isDuplicate }
        }
    }

    private var validCount: Int { items.filter { $0.isValid && !$0.isDuplicate }.count }
    private var errorCount: Int { items.filter { $0.hasErrors }.count }
    private var duplicateCount: Int { items.filter { $0.isDuplicate }.count }
    private var selectedValidCount: Int { items.filter { selectedItemIds.contains($0.id) && $0.isValid }.count }
    private var allUniqueTags: [String] { Set(items.flatMap { $0.tags }).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar with spacing
            statusBar
                .padding(.bottom, OPSStyle.Layout.spacing3)

            // Segmented filter picker
            filterPicker
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2)

            // Items list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredItems) { item in
                        itemRow(item)
                    }
                }
                .padding(.bottom, 200) // Space for footer
            }

            // Footer with active filters and import
            importFooter
        }
        .sheet(isPresented: Binding(
            get: { editingItemId != nil },
            set: { if !$0 { editingItemId = nil } }
        )) {
            if let itemId = editingItemId,
               let index = items.firstIndex(where: { $0.id == itemId }) {
                editItemSheet(for: index)
            }
        }
        .sheet(isPresented: $showingManageTags) {
            manageTagsSheet
        }
        .sheet(isPresented: $showingSelectionTools) {
            selectionToolsSheet
        }
        .alert("SELECT BY KEYWORD", isPresented: $showingKeywordSearch) {
            TextField("Keyword", text: $keywordSearchText)
            Button("Cancel", role: .cancel) {
                keywordSearchText = ""
            }
            Button("Select") {
                selectByKeyword(keywordSearchText)
            }
        } message: {
            Text("Select items containing keyword in name")
        }
        .alert("RENAME TAG", isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField("New name", text: $renameTagText)
            Button("Cancel", role: .cancel) {
                renamingTag = nil
                renameTagText = ""
            }
            Button("Rename") {
                if let oldTag = renamingTag {
                    renameTagGlobally(from: oldTag, to: renameTagText)
                }
                renamingTag = nil
                renameTagText = ""
            }
        } message: {
            if let tag = renamingTag {
                Text("Rename '\(tag)' across all items")
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing4) {
            statusCell(value: "\(validCount)", label: "VALID", color: OPSStyle.Colors.successStatus)
            statusCell(value: "\(errorCount)", label: "ISSUES", color: errorCount > 0 ? OPSStyle.Colors.warningStatus : nil)
            statusCell(value: "\(duplicateCount)", label: "DUPES", color: duplicateCount > 0 ? OPSStyle.Colors.errorStatus : nil)
            statusCell(value: "\(selectedItemIds.count)", label: "SELECTED", color: nil)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    private func statusCell(value: String, label: String, color: Color?) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(color ?? OPSStyle.Colors.primaryText)
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(color?.opacity(0.7) ?? OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filter Picker

    private var filterPicker: some View {
        SegmentedControl(
            selection: $filterMode,
            options: [
                (FilterMode.all, "ALL"),
                (FilterMode.valid, "VALID"),
                (FilterMode.errors, "ISSUES"),
                (FilterMode.duplicates, "DUPES")
            ]
        )
    }

    // MARK: - Item Row

    private func itemRow(_ item: ParsedInventoryItem) -> some View {
        let isSelected = selectedItemIds.contains(item.id)
        let hasIssue = item.hasErrors
        let isDupe = item.isDuplicate

        return Button(action: { toggleSelection(item) }) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .frame(width: 20)

                // Quantity
                Text(formatQuantity(item.quantity))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 40, alignment: .trailing)

                // Divider
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(width: 1, height: 24)

                // Name and details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name.isEmpty ? "(no name)" : item.name)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(item.name.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        // Issue indicator with color
                        if hasIssue {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }

                        // Duplicate indicator with color
                        if isDupe {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 10))
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }

                    // Tags (simple text)
                    if !item.tags.isEmpty {
                        Text(item.tags.joined(separator: " / "))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Edit button
                Button(action: { startEditing(item) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.background)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Import Footer

    private var importFooter: some View {
        VStack(spacing: 0) {
            // Active filters as pills
            if !activeFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeFilters) { filter in
                            filterPill(filter)
                        }
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

                // Import button
                Button(action: onImport) {
                    Text("IMPORT \(selectedItemIds.count) ITEMS")
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
    }

    private func filterPill(_ filter: ActiveFilter) -> some View {
        Button(action: { removeFilter(filter) }) {
            HStack(spacing: 4) {
                Image(systemName: filter.type == .keyword ? "magnifyingglass" : "tag")
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
                        selectionToolRow(icon: "checkmark.circle", title: "Select All", subtitle: "Select all \(items.count) items") {
                            selectAll()
                            showingSelectionTools = false
                        }

                        selectionToolRow(icon: "circle", title: "Select None", subtitle: "Clear selection") {
                            selectNone()
                            showingSelectionTools = false
                        }

                        selectionToolRow(icon: "magnifyingglass", title: "By Keyword", subtitle: "Select items matching a keyword") {
                            showingSelectionTools = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                keywordSearchText = ""
                                showingKeywordSearch = true
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
                    .padding(.top, OPSStyle.Layout.spacing3)

                    // Tags section
                    if !allUniqueTags.isEmpty {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            HStack {
                                Text("BY TAG")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                                Spacer()

                                Button(action: {
                                    showingSelectionTools = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showingManageTags = true
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
                                ForEach(allUniqueTags, id: \.self) { tag in
                                    let tagCount = items.filter { $0.tags.contains(tag) }.count
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

    // MARK: - Helper Functions

    private func toggleSelection(_ item: ParsedInventoryItem) {
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            selectedItemIds.insert(item.id)
        }
    }

    private func selectAll() {
        selectedItemIds = Set(items.map { $0.id })
        activeFilters = []
    }

    private func selectNone() {
        selectedItemIds = []
        activeFilters = []
    }

    private func selectByKeyword(_ keyword: String) {
        let searchTerm = keyword.lowercased().trimmingCharacters(in: .whitespaces)
        guard !searchTerm.isEmpty else { return }
        let matchingIds = items.filter { $0.name.lowercased().contains(searchTerm) }.map { $0.id }
        selectedItemIds = Set(matchingIds)
        activeFilters = [ActiveFilter(type: .keyword, value: keyword)]
        keywordSearchText = ""
    }

    private func selectByTag(_ tag: String) {
        let matchingIds = items.filter { $0.tags.contains(tag) }.map { $0.id }
        selectedItemIds = Set(matchingIds)
        activeFilters = [ActiveFilter(type: .tag, value: tag)]
    }

    private func removeFilter(_ filter: ActiveFilter) {
        activeFilters.removeAll { $0.id == filter.id }
        if activeFilters.isEmpty {
            // Reset to select all valid items
            selectedItemIds = Set(items.filter { $0.isValid && !$0.isDuplicate }.map { $0.id })
        }
    }

    private func formatQuantity(_ quantity: Double) -> String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(quantity))
        }
        return String(format: "%.1f", quantity)
    }

    // MARK: - Edit Functions

    private func startEditing(_ item: ParsedInventoryItem) {
        editName = item.name
        editQuantity = formatQuantity(item.quantity)
        editTags = item.tags
        editNewTag = ""
        editingItemId = item.id
    }

    private func saveEdits(for index: Int) {
        items[index].name = editName.trimmingCharacters(in: .whitespaces)
        items[index].quantity = Double(editQuantity.replacingOccurrences(of: ",", with: "")) ?? 0
        items[index].tags = editTags

        var errors: [String] = []
        if items[index].name.isEmpty {
            errors.append("Name is required")
        }
        items[index].validationErrors = errors
        editingItemId = nil
    }

    private func addEditTag() {
        let tag = editNewTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !editTags.contains(tag) else { return }
        editTags.append(tag)
        editNewTag = ""
    }

    private func removeEditTag(_ tag: String) {
        editTags.removeAll { $0 == tag }
    }

    // MARK: - Global Tag Management

    private func renameTagGlobally(from oldTag: String, to newTag: String) {
        let trimmedNew = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmedNew.isEmpty, trimmedNew != oldTag else { return }
        for index in items.indices {
            if let tagIndex = items[index].tags.firstIndex(of: oldTag) {
                items[index].tags[tagIndex] = trimmedNew
            }
        }
    }

    private func deleteTagGlobally(_ tag: String) {
        for index in items.indices {
            items[index].tags.removeAll { $0 == tag }
        }
    }

    // MARK: - Edit Item Sheet

    private func editItemSheet(for index: Int) -> some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        TextField("Item name", text: $editName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(12)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }

                    // Quantity field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("QUANTITY")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        TextField("0", text: $editQuantity)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .keyboardType(.decimalPad)
                            .padding(12)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }

                    // Tags section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TAGS")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        // Existing tags
                        if !editTags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(editTags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        Text(tag)
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)

                                        Button(action: { removeEditTag(tag) }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }

                        // Add new tag
                        HStack(spacing: 8) {
                            TextField("Add tag", text: $editNewTag)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(10)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                )
                                .onSubmit { addEditTag() }

                            Button(action: addEditTag) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(editNewTag.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                                    .frame(width: 36, height: 36)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                    )
                            }
                            .disabled(editNewTag.isEmpty)
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("EDIT ITEM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { editingItemId = nil }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveEdits(for: index) }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(editName.trimmingCharacters(in: .whitespaces).isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Manage Tags Sheet

    private var manageTagsSheet: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                if allUniqueTags.isEmpty {
                    VStack(spacing: 12) {
                        Text("NO TAGS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("Tags will appear here when items have tags")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(allUniqueTags, id: \.self) { tag in
                                tagManagementRow(tag)
                            }
                        }
                    }
                }
            }
            .navigationTitle("MANAGE TAGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingManageTags = false }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tagManagementRow(_ tag: String) -> some View {
        let itemCount = items.filter { $0.tags.contains(tag) }.count

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            // Select by tag
            Button(action: {
                selectByTag(tag)
                showingManageTags = false
            }) {
                Text("SELECT")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            // Rename
            Button(action: {
                renameTagText = tag
                renamingTag = tag
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            // Delete
            Button(action: { deleteTagGlobally(tag) }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.errorStatus.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(OPSStyle.Colors.background)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

#Preview {
    ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        ImportPreviewView(
            items: .constant([
                ParsedInventoryItem(
                    name: "2x4 Lumber",
                    quantity: 100,
                    description: nil,
                    sku: "LUM-2X4",
                    notes: nil,
                    unitName: nil,
                    tags: ["Wood", "Framing"],
                    rowIndex: 2,
                    validationErrors: [],
                    duplicateType: nil
                )
            ]),
            selectedItemIds: .constant([]),
            onImport: { }
        )
    }
}
