//
//  InventoryFormSheet.swift
//  OPS
//
//  Form sheet for creating and editing inventory items
//  Tactical minimalist design
//

import SwiftUI
import SwiftData

struct InventoryFormSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: InventoryItem?

    // Form state
    @State private var name: String = ""
    @State private var itemDescription: String = ""
    @State private var quantity: String = ""
    @State private var selectedUnitId: String? = nil
    @State private var tagsText: String = ""
    @State private var newTagInput: String = ""
    @State private var sku: String = ""
    @State private var notes: String = ""

    // Threshold state
    @State private var warningThresholdText: String = ""
    @State private var criticalThresholdText: String = ""

    // UI state
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String? = nil

    // Section expansion
    @State private var isItemDetailsExpanded = true
    @State private var isAdditionalDetailsExpanded = false

    // Focus
    @FocusState private var focusedField: FormField?

    enum FormField: Hashable {
        case name, quantity, description, sku, notes, tagInput
    }

    @Query private var allUnits: [InventoryUnit]
    @Query private var allItems: [InventoryItem]
    @Query private var allTags: [InventoryTag]

    private var companyUnits: [InventoryUnit] {
        let companyId = dataController.currentUser?.companyId ?? ""
        return allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var companyTags: [InventoryTag] {
        let companyId = dataController.currentUser?.companyId ?? ""
        return allTags.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }

    private var existingTags: [String] {
        companyTags.map { $0.name }.sorted()
    }

    private var currentTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var suggestedTags: [String] {
        existingTags.filter { !currentTags.contains($0) }
    }

    /// Tags that match the current input text (predictive suggestions)
    private var predictiveTags: [String] {
        let input = newTagInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !input.isEmpty else { return [] }
        return suggestedTags.filter { $0.lowercased().contains(input) }
    }

    private var isEditing: Bool { item != nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var selectedUnitName: String {
        if let unitId = selectedUnitId,
           let unit = companyUnits.first(where: { $0.id == unitId }) {
            return unit.display
        }
        return "Select"
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // Item Details
                        ExpandableSection(
                            title: "ITEM DETAILS",
                            icon: OPSStyle.Icons.checklist,
                            isExpanded: $isItemDetailsExpanded,
                            onDelete: nil,
                            collapsible: false
                        ) {
                            itemDetailsContent
                        }

                        // Additional Details
                        ExpandableSection(
                            title: "ADDITIONAL DETAILS",
                            icon: OPSStyle.Icons.description,
                            isExpanded: $isAdditionalDetailsExpanded,
                            onDelete: nil
                        ) {
                            additionalDetailsContent
                        }

                        // Error
                        if let error = errorMessage {
                            Text(error)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }

                        // Delete button
                        if isEditing {
                            Button(action: { showingDeleteConfirmation = true }) {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
                                    Image(systemName: OPSStyle.Icons.trash)
                                    Text("Delete Item")
                                }
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.errorStatus.opacity(OPSStyle.Layout.Opacity.subtle))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            .padding(.top, OPSStyle.Layout.spacing2)
                        }

                        Spacer().frame(height: 100)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing3)
                }
            }
            .standardSheetToolbar(
                title: isEditing ? "Edit Item" : "Add Item",
                actionText: isEditing ? "Save" : "Add",
                isActionEnabled: isValid,
                isSaving: isSaving,
                onCancel: { dismiss() },
                onAction: { saveItem() }
            )
            .alert("Delete Item", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { deleteItem() }
            } message: {
                Text("Are you sure you want to delete \"\(name)\"?")
            }
            .onAppear { loadItemData() }
        }
    }

    // MARK: - Item Details Content

    private var itemDetailsContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            // Name
            inputField(title: "ITEM NAME", placeholder: "Enter item name", text: $name, field: .name)

            // Quantity and Unit
            HStack(spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("QUANTITY")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextField("0", text: $quantity)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .quantity)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(focusedField == .quantity ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("UNIT")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Menu {
                        Button("None") { selectedUnitId = nil }
                        ForEach(companyUnits) { unit in
                            Button(unit.display) { selectedUnitId = unit.id }
                        }
                    } label: {
                        HStack {
                            Text(selectedUnitName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(selectedUnitId == nil ? OPSStyle.Colors.placeholderText : OPSStyle.Colors.primaryText)

                            Spacer()

                            Image(systemName: OPSStyle.Icons.chevronDown)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                        )
                    }
                }
            }

            // Tags
            tagsSection
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("TAGS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Current tags
            if !currentTags.isEmpty {
                FlowLayout(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(currentTags, id: \.self) { tag in
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Text(tag)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Button(action: { removeTag(tag) }) {
                                Image(systemName: OPSStyle.Icons.xmark)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.subtleBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                }
            }

            // Add tag input
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField("Enter tag(s)", text: $newTagInput)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .focused($focusedField, equals: .tagInput)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(focusedField == .tagInput ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )
                    .onSubmit { addTagsFromInput() }

                Button(action: { addTagsFromInput() }) {
                    Image(systemName: OPSStyle.Icons.plus)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        .background(newTagInput.isEmpty ? OPSStyle.Colors.subtleBackground : OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                }
                .disabled(newTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Predictive suggestions (when typing)
            if !predictiveTags.isEmpty {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("MATCHES")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    FlowLayout(spacing: 8) {
                        ForEach(predictiveTags, id: \.self) { tag in
                            tagSuggestionPill(tag: tag)
                        }
                    }
                }
            }

            // All available suggestions (when not typing)
            if predictiveTags.isEmpty && !suggestedTags.isEmpty {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("AVAILABLE TAGS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    FlowLayout(spacing: 8) {
                        ForEach(suggestedTags, id: \.self) { tag in
                            tagSuggestionPill(tag: tag)
                        }
                    }
                }
            } else if existingTags.isEmpty && currentTags.isEmpty && predictiveTags.isEmpty {
                Text("e.g. fastener, steel, exterior")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    /// Prominent pill button for tag suggestions (monochromatic)
    private func tagSuggestionPill(tag: String) -> some View {
        Button(action: {
            addTag(tag)
            newTagInput = "" // Clear input after selecting
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text(tag)
                    .font(OPSStyle.Typography.caption)
            }
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Additional Details Content

    private var additionalDetailsContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            inputField(title: "DESCRIPTION", placeholder: "Enter description (optional)", text: $itemDescription, field: .description, isMultiline: true)
            inputField(title: "SKU / PART NUMBER", placeholder: "Enter SKU (optional)", text: $sku, field: .sku)
            inputField(title: "NOTES", placeholder: "Enter notes (optional)", text: $notes, field: .notes, isMultiline: true)

            // Threshold Settings
            thresholdSettingsSection
        }
    }

    // MARK: - Threshold Settings Section

    private var thresholdSettingsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("QUANTITY THRESHOLDS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Warning threshold
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Circle()
                        .fill(OPSStyle.Colors.warningStatus)
                        .frame(width: 8, height: 8)
                    Text("Warning Level")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                TextField("e.g. 20 (optional)", text: $warningThresholdText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.decimalPad)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )
            }

            // Critical threshold
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Circle()
                        .fill(OPSStyle.Colors.errorStatus)
                        .frame(width: 8, height: 8)
                    Text("Critical Level")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                TextField("e.g. 5 (optional)", text: $criticalThresholdText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.decimalPad)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )
            }

            // Help text
            Text("Leave empty to use tag defaults")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Input Field Helper

    @ViewBuilder
    private func inputField(title: String, placeholder: String, text: Binding<String>, field: FormField, isMultiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if isMultiline {
                TextField(placeholder, text: text, axis: .vertical)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: field)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(focusedField == field ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )
            } else {
                TextField(placeholder, text: text)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: field)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(focusedField == field ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Functions

    private func loadItemData() {
        guard let item = item else { return }

        name = item.name
        itemDescription = item.itemDescription ?? ""
        quantity = item.quantity > 0 ? formatQuantity(item.quantity) : ""
        selectedUnitId = item.unitId
        tagsText = item.tagNames.joined(separator: ", ")
        sku = item.sku ?? ""
        notes = item.notes ?? ""

        // Load threshold values
        if let warning = item.warningThreshold {
            warningThresholdText = formatQuantity(warning)
        }
        if let critical = item.criticalThreshold {
            criticalThresholdText = formatQuantity(critical)
        }

        if !itemDescription.isEmpty || !sku.isEmpty || !notes.isEmpty ||
           item.warningThreshold != nil || item.criticalThreshold != nil {
            isAdditionalDetailsExpanded = true
        }
    }

    private func addTag(_ tag: String) {
        guard !currentTags.contains(tag) else { return }
        tagsText = tagsText.isEmpty ? tag : tagsText + ", " + tag
    }

    private func addTagsFromInput() {
        let newTags = newTagInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !currentTags.contains($0) }

        guard !newTags.isEmpty else {
            newTagInput = ""
            return
        }

        for tag in newTags {
            addTag(tag)
        }
        newTagInput = ""
    }

    private func removeTag(_ tag: String) {
        var tags = currentTags
        tags.removeAll { $0 == tag }
        tagsText = tags.joined(separator: ", ")
    }

    private func formatQuantity(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// Find existing tag or create new one in Bubble (async - waits for Bubble ID)
    private func findOrCreateTag(name: String, companyId: String) async throws -> InventoryTag {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // Look for existing tag with matching name (case-insensitive)
        if let existingTag = companyTags.first(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            // Check if this tag has been synced to Bubble (Bubble IDs are long numeric strings)
            let isBubbleId = existingTag.id.contains("x") || existingTag.id.count > 20

            if isBubbleId && !existingTag.needsSync {
                print("[INVENTORY_FORM] 🏷️ Found existing synced tag: \(existingTag.name) (ID: \(existingTag.id))")
                return existingTag
            } else {
                // Tag exists locally but needs to be created in Bubble
                print("[INVENTORY_FORM] 🏷️ Found local tag '\(existingTag.name)' - syncing to Bubble first...")
                let dto = InventoryTagDTO(
                    id: "",
                    name: existingTag.name,
                    warningThreshold: existingTag.warningThreshold,
                    criticalThreshold: existingTag.criticalThreshold,
                    company: companyId
                )
                let created = try await dataController.apiService.createTag(dto)
                print("[INVENTORY_FORM] ✅ Tag synced with Bubble ID: \(created.id)")

                // Update local tag with Bubble ID
                await MainActor.run {
                    existingTag.id = created.id
                    existingTag.needsSync = false
                    existingTag.lastSyncedAt = Date()
                }
                return existingTag
            }
        }

        // Create new tag in Bubble FIRST to get the real ID
        print("[INVENTORY_FORM] 🏷️ Creating new tag in Bubble: \(trimmedName)")
        let dto = InventoryTagDTO(
            id: "", // Will be assigned by Bubble
            name: trimmedName,
            warningThreshold: nil,
            criticalThreshold: nil,
            company: companyId
        )
        let created = try await dataController.apiService.createTag(dto)
        print("[INVENTORY_FORM] ✅ Tag created with Bubble ID: \(created.id)")

        // Now create local tag with Bubble's ID
        let newTag = InventoryTag(
            id: created.id,
            name: trimmedName,
            companyId: companyId
        )
        newTag.needsSync = false
        newTag.lastSyncedAt = Date()

        await MainActor.run {
            modelContext.insert(newTag)
        }

        return newTag
    }

    /// Apply tags to an item (clears existing and adds new ones) - async to wait for tag creation
    private func applyTagsToItem(_ item: InventoryItem, tagNames: [String], companyId: String) async throws {
        // Clear existing tags
        await MainActor.run {
            item.tags.removeAll()
            item.tagIds.removeAll()
        }

        // Add each tag (creating in Bubble if needed)
        for tagName in tagNames {
            let tag = try await findOrCreateTag(name: tagName, companyId: companyId)
            await MainActor.run {
                item.addTag(tag)
            }
        }
        print("[INVENTORY_FORM] 📋 Applied tags: \(item.tagIds)")
    }

    private func saveItem() {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let parsedQuantity = Double(quantity) ?? 0
        let parsedTags = currentTags
        let companyId = dataController.currentUser?.companyId ?? ""

        // Parse threshold values (nil if empty or invalid)
        let parsedWarningThreshold: Double? = Double(warningThresholdText.trimmingCharacters(in: .whitespaces))
        let parsedCriticalThreshold: Double? = Double(criticalThresholdText.trimmingCharacters(in: .whitespaces))

        if let existingItem = item {
            existingItem.name = trimmedName
            existingItem.itemDescription = itemDescription.isEmpty ? nil : itemDescription
            existingItem.quantity = parsedQuantity
            existingItem.unitId = selectedUnitId
            existingItem.sku = sku.isEmpty ? nil : sku
            existingItem.notes = notes.isEmpty ? nil : notes
            existingItem.warningThreshold = parsedWarningThreshold
            existingItem.criticalThreshold = parsedCriticalThreshold
            existingItem.needsSync = true

            if let unitId = selectedUnitId {
                existingItem.unit = companyUnits.first(where: { $0.id == unitId })
            } else {
                existingItem.unit = nil
            }

            Task {
                do {
                    // Apply tags FIRST (creates any new tags in Bubble and waits for IDs)
                    try await applyTagsToItem(existingItem, tagNames: parsedTags, companyId: companyId)

                    // Now save with valid Bubble tag IDs
                    let updates = InventoryItemDTO.dictionaryFrom(existingItem)
                    print("[INVENTORY_FORM] 📤 Saving item: \(existingItem.id)")
                    print("[INVENTORY_FORM] 📋 Tags: \(existingItem.tagIds)")
                    try await dataController.apiService.updateInventoryItem(id: existingItem.id, updates: updates)
                    await MainActor.run {
                        existingItem.needsSync = false
                        existingItem.lastSyncedAt = Date()
                        try? modelContext.save()
                        print("[INVENTORY_FORM] ✅ Item saved successfully")
                        dismiss()
                    }
                } catch {
                    print("[INVENTORY_FORM] ❌ Failed to save: \(error)")
                    await MainActor.run {
                        errorMessage = "Failed to save: \(error)"
                        isSaving = false
                    }
                }
            }
        } else {
            let newItem = InventoryItem(
                id: UUID().uuidString,
                name: trimmedName,
                quantity: parsedQuantity,
                companyId: companyId,
                unitId: selectedUnitId,
                itemDescription: itemDescription.isEmpty ? nil : itemDescription,
                sku: sku.isEmpty ? nil : sku,
                notes: notes.isEmpty ? nil : notes,
                imageUrl: nil,
                warningThreshold: parsedWarningThreshold,
                criticalThreshold: parsedCriticalThreshold
            )
            newItem.needsSync = true

            if let unitId = selectedUnitId {
                newItem.unit = companyUnits.first(where: { $0.id == unitId })
            }

            modelContext.insert(newItem)

            Task {
                do {
                    // Apply tags FIRST (creates any new tags in Bubble and waits for IDs)
                    try await applyTagsToItem(newItem, tagNames: parsedTags, companyId: companyId)

                    // Now create item with valid Bubble tag IDs
                    let dto = InventoryItemDTO.from(newItem)
                    print("[INVENTORY_FORM] 📤 Creating new item with tags: \(newItem.tagIds)")
                    let createdDTO = try await dataController.apiService.createInventoryItem(dto)

                    await MainActor.run {
                        newItem.id = createdDTO.id
                        newItem.needsSync = false
                        newItem.lastSyncedAt = Date()
                        try? modelContext.save()
                        print("[INVENTORY_FORM] ✅ Item created successfully")
                        dismiss()
                    }
                } catch {
                    print("[INVENTORY_FORM] ❌ Failed to create: \(error)")
                    await MainActor.run {
                        errorMessage = "Failed to create: \(error)"
                        isSaving = false
                    }
                }
            }
        }
    }

    private func deleteItem() {
        guard let item = item else { return }

        item.deletedAt = Date()
        item.needsSync = true

        Task {
            do {
                try await dataController.apiService.deleteInventoryItem(id: item.id)
                await MainActor.run {
                    try? modelContext.save()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    InventoryFormSheet(item: nil)
        .environmentObject(DataController())
}
