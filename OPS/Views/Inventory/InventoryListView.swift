//
//  InventoryListView.swift
//  OPS
//
//  List view for displaying inventory items
//  Tactical minimalist design
//

import SwiftUI
import SwiftData

struct InventoryListView: View {
    let items: [InventoryItem]
    let isSelectionMode: Bool
    @Binding var selectedItemIds: Set<String>
    let onItemTap: (InventoryItem) -> Void
    let onItemEdit: (InventoryItem) -> Void
    let onItemDelete: (InventoryItem) -> Void
    let onItemSelect: (InventoryItem) -> Void

    var body: some View {
        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(items) { item in
                InventoryItemCard(
                    item: item,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedItemIds.contains(item.id),
                    onTap: { onItemTap(item) },
                    onEdit: { onItemEdit(item) },
                    onDelete: { onItemDelete(item) },
                    onSelect: { onItemSelect(item) }
                )
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }
}

// MARK: - Inventory Item Card

struct InventoryItemCard: View {
    @EnvironmentObject private var dataController: DataController
    let item: InventoryItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @Query private var units: [InventoryUnit]
    @State private var showingActions = false
    @State private var showingDeleteConfirmation = false

    private var unitDisplay: String {
        if let unitId = item.unitId,
           let unit = units.first(where: { $0.id == unitId }) {
            return unit.display
        }
        return ""
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // Selection checkbox (shown in selection mode)
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .frame(width: 32)
            }

            // Quantity
            VStack(spacing: OPSStyle.Layout.spacing1) {
                Text(formatQuantity(item.quantity))
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(quantityColor)

                if !unitDisplay.isEmpty {
                    Text(unitDisplay)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .frame(width: 56)

            // Divider
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(width: 1)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            // Info
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(item.name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                if let description = item.itemDescription, !description.isEmpty {
                    Text(description)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }

                // Tags
                if !item.tags.isEmpty {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        ForEach(item.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .padding(.horizontal, OPSStyle.Layout.spacing1)
                                .padding(.vertical, 2)
                                .background(OPSStyle.Colors.subtleBackground)
                                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                        }
                        if item.tags.count > 3 {
                            Text("+\(item.tags.count - 3)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                }
            }

            Spacer()

            // Edit button (hidden in selection mode)
            if !isSelectionMode {
                Button(action: onEdit) {
                    Image(systemName: OPSStyle.Icons.pencil)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.15) : OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isSelectionMode {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                showingActions = true
            }
        }
        .confirmationDialog(item.name, isPresented: $showingActions, titleVisibility: .visible) {
            Button("Select") {
                onSelect()
            }
            Button("Edit") {
                onEdit()
            }
            Button("Delete", role: .destructive) {
                showingDeleteConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Item", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Delete \"\(item.name)\"? This cannot be undone.")
        }
    }

    private var quantityColor: Color {
        if item.quantity <= 0 {
            return OPSStyle.Colors.errorStatus
        } else if item.quantity < 10 {
            return OPSStyle.Colors.warningStatus
        } else {
            return OPSStyle.Colors.primaryText
        }
    }

    private func formatQuantity(_ quantity: Double) -> String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(quantity))
        } else {
            return String(format: "%.1f", quantity)
        }
    }
}

#Preview {
    InventoryListView(
        items: [],
        isSelectionMode: false,
        selectedItemIds: .constant([]),
        onItemTap: { _ in },
        onItemEdit: { _ in },
        onItemDelete: { _ in },
        onItemSelect: { _ in }
    )
    .environmentObject(DataController())
}
