//
//  BulkTagsSheet.swift
//  OPS
//
//  Bulk tag editing sheet for multiple inventory items
//  Allows adding, removing, and creating tags
//

import SwiftUI
import SwiftData

struct BulkTagsSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let items: [InventoryItem]
    let onComplete: () -> Void

    // Query all inventory tags
    @Query private var allInventoryTags: [InventoryTag]

    @State private var newTagText: String = ""
    @State private var tagsToAdd: Set<String> = []
    @State private var tagsToRemove: Set<String> = []
    @State private var showingPreview: Bool = false
    @FocusState private var isNewTagFocused: Bool

    private var hasChanges: Bool {
        !tagsToAdd.isEmpty || !tagsToRemove.isEmpty
    }

    /// All available tags from InventoryTag entities
    private var allTags: [String] {
        let companyId = dataController.currentUser?.companyId ?? ""
        return allInventoryTags
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .map { $0.name }
            .sorted()
    }

    /// Tags currently on any of the selected items
    private var currentTags: [String] {
        let tagNames = items.flatMap { $0.tagNames }
        return Array(Set(tagNames)).sorted()
    }

    /// Tags that exist in the system but aren't on all selected items
    private var availableTagsToAdd: [String] {
        allTags.filter { tag in
            // Available if not already marked to add and at least one item doesn't have it
            !tagsToAdd.contains(tag) && items.contains { !$0.tagNames.contains(where: { $0.lowercased() == tag.lowercased() }) }
        }.sorted()
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Summary
                        summarySection
                            .padding(.top, OPSStyle.Layout.spacing3)

                        // Pending changes
                        if hasChanges {
                            pendingChangesSection
                                .padding(.top, OPSStyle.Layout.spacing4)
                        }

                        // Create new tag
                        createTagSection
                            .padding(.top, OPSStyle.Layout.spacing4)

                        // Add existing tags
                        if !availableTagsToAdd.isEmpty {
                            addTagsSection
                                .padding(.top, OPSStyle.Layout.spacing4)
                        }

                        // Remove tags
                        if !currentTags.isEmpty {
                            removeTagsSection
                                .padding(.top, OPSStyle.Layout.spacing4)
                        }

                        Spacer()
                            .frame(height: OPSStyle.Layout.spacing4)
                    }
                }
            }
            .standardSheetToolbar(
                title: "Edit Tags",
                actionText: "Apply",
                isActionEnabled: hasChanges,
                isSaving: false,
                onCancel: { dismiss() },
                onAction: { applyChanges() }
            )
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("\(items.count) items selected")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Add or remove tags from all selected items")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Pending Changes Section

    private var pendingChangesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("PENDING CHANGES")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                // Tags to add
                if !tagsToAdd.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(tagsToAdd).sorted(), id: \.self) { tag in
                            InventoryPendingTagBadge(tag: tag, isAdding: true, size: .button) {
                                tagsToAdd.remove(tag)
                            }
                        }
                    }
                }

                // Tags to remove
                if !tagsToRemove.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(tagsToRemove).sorted(), id: \.self) { tag in
                            InventoryPendingTagBadge(tag: tag, isAdding: false, size: .button) {
                                tagsToRemove.remove(tag)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Create Tag Section

    private var createTagSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("CREATE NEW TAG")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextField("New tag name", text: $newTagText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .focused($isNewTagFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            createAndAddTag()
                        }

                    if !newTagText.isEmpty {
                        Button(action: { newTagText = "" }) {
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

                Button(action: { createAndAddTag() }) {
                    Text("ADD")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(newTagText.trimmingCharacters(in: .whitespaces).isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Add Tags Section

    private var addTagsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("ADD EXISTING TAGS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            FlowLayout(spacing: 8) {
                ForEach(availableTagsToAdd, id: \.self) { tag in
                    InventoryTagActionBadge(tag: tag, isAdd: true, size: .button) {
                        tagsToAdd.insert(tag)
                        tagsToRemove.remove(tag)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Remove Tags Section

    private var removeTagsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("REMOVE TAGS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            FlowLayout(spacing: 8) {
                ForEach(currentTags.filter { !tagsToRemove.contains($0) }, id: \.self) { tag in
                    let itemsWithTag = items.filter { $0.tagNames.contains(tag) }.count
                    InventoryTagActionBadge(tag: tag, isAdd: false, size: .button, subtitle: "\(itemsWithTag) items") {
                        tagsToRemove.insert(tag)
                        tagsToAdd.remove(tag)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Functions

    private func createAndAddTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }

        tagsToAdd.insert(trimmed)
        tagsToRemove.remove(trimmed)
        newTagText = ""
        isNewTagFocused = false

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func applyChanges() {
        guard hasChanges else { return }

        let companyId = dataController.currentUser?.companyId ?? ""

        // Start async task to handle tag creation and item sync
        Task {
            // Get or create tag objects for tags to add
            var tagObjectsToAdd: [InventoryTag] = []
            var newTagsToCreate: [(tag: InventoryTag, name: String)] = []

            for tagName in tagsToAdd {
                // First check allInventoryTags (from @Query) - this includes tags created in settings
                if let existingTag = allInventoryTags.first(where: {
                    $0.name.lowercased() == tagName.lowercased() &&
                    $0.companyId == companyId &&
                    $0.deletedAt == nil
                }) {
                    print("[BULK_TAGS] ✅ Found existing tag '\(tagName)' with ID: \(existingTag.id)")
                    tagObjectsToAdd.append(existingTag)
                } else {
                    // Tag doesn't exist - create locally first
                    print("[BULK_TAGS] 🆕 Tag '\(tagName)' not found, will create in Bubble...")
                    let newTag = InventoryTag(
                        id: UUID().uuidString,
                        name: tagName,
                        companyId: companyId
                    )
                    newTag.needsSync = true
                    await MainActor.run {
                        modelContext.insert(newTag)
                    }
                    tagObjectsToAdd.append(newTag)
                    newTagsToCreate.append((tag: newTag, name: tagName))
                }
            }

            // Create new tags in Bubble FIRST (before applying to items)
            for (newTag, tagName) in newTagsToCreate {
                do {
                    let dto = InventoryTagDTO(
                        id: newTag.id,
                        name: tagName,
                        warningThreshold: nil,
                        criticalThreshold: nil,
                        company: companyId
                    )
                    let created = try await dataController.apiService.createTag(dto)
                    await MainActor.run {
                        newTag.id = created.id
                        newTag.needsSync = false
                        newTag.lastSyncedAt = Date()
                        print("[BULK_TAGS] ✅ Tag '\(tagName)' created with Bubble ID: \(created.id)")
                    }
                } catch {
                    print("[BULK_TAGS] ❌ Failed to create tag '\(tagName)': \(error)")
                }
            }

            // Apply changes to all items on main thread
            await MainActor.run {
                for item in items {
                    // Add new tags
                    for tag in tagObjectsToAdd {
                        if !item.tags.contains(where: { $0.id == tag.id }) {
                            item.addTag(tag)
                        }
                    }

                    // Remove tags by name
                    for tagName in tagsToRemove {
                        if let tagToRemove = item.tags.first(where: { $0.name.lowercased() == tagName.lowercased() }) {
                            item.removeTag(tagToRemove)
                        }
                    }

                    // Rebuild tagIds from current tags to ensure correct Bubble IDs
                    item.tagIds = item.tags.filter { $0.deletedAt == nil }.map { $0.id }
                    item.needsSync = true
                }

                // Save locally
                try? modelContext.save()
            }

            // Now sync items to Bubble with correct tag IDs
            for item in items {
                do {
                    let updates = InventoryItemDTO.dictionaryFrom(item)
                    print("[BULK_TAGS] Syncing item '\(item.name)' with tags: \(item.tagIds)")
                    try await dataController.apiService.updateInventoryItem(id: item.id, updates: updates)
                    await MainActor.run {
                        item.needsSync = false
                        item.lastSyncedAt = Date()
                    }
                } catch {
                    print("[BULK_TAGS] Failed to sync item '\(item.name)': \(error)")
                }
            }

            await MainActor.run {
                try? modelContext.save()
            }
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        onComplete()
        dismiss()
    }
}

#Preview {
    BulkTagsSheet(
        items: [
            InventoryItem(
                id: "preview1",
                name: "2x4 Lumber 8ft",
                quantity: 50,
                companyId: "company"
            ),
            InventoryItem(
                id: "preview2",
                name: "Drywall 4x8",
                quantity: 25,
                companyId: "company"
            )
        ],
        onComplete: { }
    )
    .environmentObject(DataController())
}
