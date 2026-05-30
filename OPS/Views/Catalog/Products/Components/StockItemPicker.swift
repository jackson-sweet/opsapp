//
//  StockItemPicker.swift
//  OPS
//
//  Bottom sheet that resolves the iOS // SHOW IN STOCK link target for a
//  Material-category Product. Two paths:
//    1. Pick an existing `catalog_items` family — the picked id becomes
//       `products.linked_catalog_item_id`.
//    2. Create a new family + a single default variant on the fly — the
//       freshly-created id becomes `products.linked_catalog_item_id`.
//
//  The "create new" path runs `CatalogRepository.createDefaultItemForProduct`
//  using the current Product form values (name, category folder, price,
//  unit) so the operator doesn't have to retype the data they just typed.
//
//  Bug 164e0595 — New Product Sheet redesign.
//

import SwiftUI
import SwiftData

struct StockItemPicker: View {
    /// Snapshot of the in-progress Product form so the "create new" path
    /// can mint a sensible default `catalog_items` row without bouncing
    /// the operator out to the Stock tab.
    struct ProductDraft {
        let name: String
        let categoryId: String?
        let basePrice: Double?
        let unitCost: Double?
        let unitId: String?
    }

    /// Currently linked catalog_items.id, if any. Drives the checkmark.
    let selectedCatalogItemId: String?

    /// Used by the "create new" affordance to mint a sensible default row.
    let productDraft: ProductDraft

    /// Fires with the resolved catalog_items.id once the user picks (or
    /// creates) one. Sheet dismisses immediately after firing.
    let onPicked: (String) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allFamilies: [CatalogItem]

    @State private var searchQuery: String = ""
    @State private var isCreatingNew: Bool = false
    @State private var errorMessage: String? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyFamilies: [CatalogItem] {
        allFamilies
            .filter { $0.companyId == companyId
                && $0.deletedAt == nil
                && $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredFamilies: [CatalogItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return companyFamilies }
        let lower = trimmed.lowercased()
        return companyFamilies.filter { $0.name.lowercased().contains(lower) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchField
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            createNewRow

                            if filteredFamilies.isEmpty {
                                emptyState
                            } else {
                                ForEach(filteredFamilies, id: \.id) { family in
                                    familyRow(family)
                                }
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.errorText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, OPSStyle.Layout.spacing2)
                            }
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                }
            }
            .navigationTitle("LINK STOCK ITEM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image("ops.search")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField("Search stock items", text: $searchQuery)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled()
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image("ops.close")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            Rectangle().fill(OPSStyle.Colors.separator).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Rows

    private var createNewRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await createNew() }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if isCreatingNew {
                    ProgressView()
                        .tint(OPSStyle.Colors.primaryAccent)
                } else {
                    Image("ops.add-circle")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("// + CREATE NEW STOCK ITEM")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    Text("From this product — qty starts at 0")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4),
                            lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCreatingNew || productDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Create new stock item from this product")
    }

    private func familyRow(_ family: CatalogItem) -> some View {
        let isSelected = (family.id == selectedCatalogItemId)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onPicked(family.id)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image("ops.inventory-item")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(family.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image("ops.checkmark")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Link to stock item \(family.name)")
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// NO STOCK ITEMS MATCH")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if !searchQuery.isEmpty {
                Text("Try a different search or create a new stock item above.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
            } else {
                Text("Your stock catalog is empty. Create one from this product above.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(OPSStyle.Layout.spacing4)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Create new

    @MainActor
    private func createNew() async {
        let trimmedName = productDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        isCreatingNew = true
        defer { isCreatingNew = false }
        errorMessage = nil

        let repo = CatalogRepository(companyId: companyId)
        do {
            let createdFamily = try await repo.createDefaultItemForProduct(
                companyId: companyId,
                productName: trimmedName,
                categoryId: productDraft.categoryId,
                defaultPrice: productDraft.basePrice,
                defaultUnitCost: productDraft.unitCost,
                defaultUnitId: productDraft.unitId
            )

            // Best-effort local cache write so the picker reflects the new
            // row immediately on next open. The next sync pass will replace
            // the local copy with the canonical server payload.
            let localFamily = createdFamily.toModel()
            localFamily.lastSyncedAt = Date()
            localFamily.needsSync = false
            modelContext.insert(localFamily)
            try? modelContext.save()

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onPicked(createdFamily.id)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}
