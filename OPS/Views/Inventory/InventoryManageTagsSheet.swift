//
//  InventoryManageTagsSheet.swift
//  OPS
//
//  Manage tags for inventory items - rename or delete tags globally
//  Tactical minimalist design
//

import SwiftUI

struct InventoryManageTagsSheet: View {
    let items: [InventoryItem]
    let onRenameTag: (String, String) -> Void
    let onDeleteTag: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renamingTag: String? = nil
    @State private var renameTagText: String = ""
    @State private var showingDeleteConfirmation: String? = nil
    @State private var searchText: String = ""

    private var allTags: [String] {
        Set(items.flatMap { $0.tagNames }).sorted()
    }

    private var filteredTags: [String] {
        if searchText.isEmpty {
            return allTags
        }
        return allTags.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private func itemCount(for tag: String) -> Int {
        items.filter { $0.tagNames.contains(tag) }.count
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Status bar
                    statusBar
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.top, OPSStyle.Layout.spacing2)

                    // Divider
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                        .padding(.top, OPSStyle.Layout.spacing2)

                    if allTags.isEmpty {
                        emptyState
                    } else {
                        // Search field
                        searchField
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.top, OPSStyle.Layout.spacing3)

                        // Tag list
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(filteredTags, id: \.self) { tag in
                                    tagRow(tag)
                                }
                            }
                            .padding(.top, OPSStyle.Layout.spacing2)
                            .padding(.bottom, OPSStyle.Layout.spacing4)
                        }
                    }
                }
            }
            .navigationTitle("MANAGE TAGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Rename Tag", isPresented: Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )) {
            TextField("New tag name", text: $renameTagText)
            Button("Cancel", role: .cancel) {
                renamingTag = nil
                renameTagText = ""
            }
            Button("Rename") {
                if let oldTag = renamingTag, !renameTagText.isEmpty {
                    onRenameTag(oldTag, renameTagText.trimmingCharacters(in: .whitespaces))
                }
                renamingTag = nil
                renameTagText = ""
            }
        } message: {
            if let tag = renamingTag {
                Text("Rename '\(tag)' across all items")
            }
        }
        .alert("Delete Tag?", isPresented: Binding(
            get: { showingDeleteConfirmation != nil },
            set: { if !$0 { showingDeleteConfirmation = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                showingDeleteConfirmation = nil
            }
            Button("Delete", role: .destructive) {
                if let tag = showingDeleteConfirmation {
                    onDeleteTag(tag)
                }
                showingDeleteConfirmation = nil
            }
        } message: {
            if let tag = showingDeleteConfirmation {
                let count = itemCount(for: tag)
                Text("Remove '\(tag)' from \(count) item\(count == 1 ? "" : "s")? This cannot be undone.")
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // Total tags
            HStack(spacing: 4) {
                Text("\(allTags.count)")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("TAGS")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(width: 1, height: 12)

            // Total items with tags
            let itemsWithTags = items.filter { !$0.tagNames.isEmpty }.count
            HStack(spacing: 4) {
                Text("\(itemsWithTags)")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("ITEMS TAGGED")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            TextField("Search tags", text: $searchText)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Spacer()

            Text("NO TAGS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("Add tags to inventory items to organize them")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing4)
    }

    // MARK: - Tag Row

    private func tagRow(_ tag: String) -> some View {
        let count = itemCount(for: tag)

        return HStack(spacing: OPSStyle.Layout.spacing3) {
            // Tag badge with count
            HStack(spacing: OPSStyle.Layout.spacing2) {
                InventoryTagBadge(tag: tag, size: .button)

                Text("\(count) item\(count == 1 ? "" : "s")")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                // Rename button
                actionButton(icon: "pencil") {
                    renameTagText = tag
                    renamingTag = tag
                }

                // Delete button
                actionButton(icon: "trash", isDestructive: true) {
                    showingDeleteConfirmation = tag
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Action Button

    private func actionButton(icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isDestructive ? OPSStyle.Colors.errorStatus.opacity(0.7) : OPSStyle.Colors.secondaryText)
                .frame(width: 40, height: 40)
                .background(OPSStyle.Colors.background)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    InventoryManageTagsSheet(
        items: [],
        onRenameTag: { _, _ in },
        onDeleteTag: { _ in }
    )
}
