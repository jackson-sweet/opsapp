//
//  InventoryListView.swift
//  OPS
//
//  List view for displaying inventory items
//  Tactical minimalist design with pinch-to-zoom
//

import SwiftUI
import SwiftData

struct InventoryListView: View {
    let items: [InventoryItem]
    let isSelectionMode: Bool
    @Binding var selectedItemIds: Set<String>
    let scale: CGFloat
    let onItemTap: (InventoryItem) -> Void
    let onItemEdit: (InventoryItem) -> Void
    let onItemDelete: (InventoryItem) -> Void
    let onItemSelect: (InventoryItem) -> Void

    // Progressive disclosure thresholds
    private var showTags: Bool { scale >= 0.9 }
    private var showMetadata: Bool { scale >= 1.0 }

    var body: some View {
        LazyVStack(spacing: 12 * scale) {
            ForEach(items) { item in
                InventoryItemCard(
                    item: item,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedItemIds.contains(item.id),
                    scale: scale,
                    showTags: showTags,
                    showMetadata: showMetadata,
                    onTap: { onItemTap(item) },
                    onEdit: { onItemEdit(item) },
                    onDelete: { onItemDelete(item) },
                    onSelect: { onItemSelect(item) }
                )
            }

            // Item count footer
            HStack {
                Spacer()
                Text("[ \(items.count) ITEM\(items.count == 1 ? "" : "S") ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .padding(.top, 8 * scale)
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
    let scale: CGFloat
    let showTags: Bool
    let showMetadata: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @Query private var units: [InventoryUnit]
    @State private var showingActions = false
    @State private var showingDeleteConfirmation = false
    @State private var isLongPressing = false

    // Dynamic card height based on content shown
    private var cardHeight: CGFloat {
        let baseHeight: CGFloat = showMetadata ? 80 : (showTags ? 60 : 50)
        return baseHeight * scale
    }

    private var unitDisplay: String {
        if let unitId = item.unitId,
           let unit = units.first(where: { $0.id == unitId }) {
            return unit.display.uppercased()
        }
        return ""
    }

    private var thresholdStatus: ThresholdStatus {
        item.effectiveThresholdStatus()
    }

    // Scaled fonts
    private var titleFont: Font {
        Font.custom("Mohave-Medium", size: 16 * scale)
    }

    private var captionFont: Font {
        Font.custom("Kosugi-Regular", size: 14 * scale)
    }

    private var smallCaptionFont: Font {
        Font.custom("Kosugi-Regular", size: 12 * scale)
    }

    private var quantityFont: Font {
        Font.custom("Mohave-Regular", size: 28 * scale)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Selection stripe (replaces checkbox)
            if isSelectionMode && isSelected {
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: 4 * scale)
            }

            // Main content
            HStack(alignment: .center, spacing: 12 * scale) {
                // Left: Name, tags, metadata
                VStack(alignment: .leading, spacing: 4 * scale) {
                    // Title row with optional badge (badge shown here when not full size)
                    HStack(spacing: 8 * scale) {
                        Text(item.name.uppercased())
                            .font(titleFont)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        // Show badge next to name when not full size
                        if !showMetadata, let badgeLabel = thresholdStatus.label {
                            thresholdBadgeView(badgeLabel)
                        }
                    }

                    // Tags (shown at scale >= 0.9)
                    if showTags {
                        if item.tagNames.isEmpty {
                            Text("NO TAGS")
                                .font(smallCaptionFont)
                                .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.5))
                        } else {
                            HStack(spacing: OPSStyle.Inventory.TagBadge.spacing * scale) {
                                ForEach(item.tagNames.prefix(4), id: \.self) { tag in
                                    InventoryTagBadge(tag: tag, scale: scale)
                                }
                                if item.tagNames.count > 4 {
                                    Text("+\(item.tagNames.count - 4)")
                                        .font(smallCaptionFont)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                            }
                        }
                    }

                    // Metadata row (shown at scale >= 1.0)
                    if showMetadata {
                        HStack(spacing: 12 * scale) {
                            // SKU
                            if let sku = item.sku, !sku.isEmpty {
                                metadataItem(icon: "barcode", text: sku)
                            } else {
                                metadataItem(icon: "barcode", text: "NO SKU", isEmpty: true)
                            }
                        }
                        .frame(height: 16 * scale)
                    }
                }

                Spacer()

                // Right: Quantity area with status badge
                if showMetadata {
                    // Full size (scale >= 1.0): Status on top, Quantity center, Unit bottom
                    VStack(alignment: .center, spacing: 0) {
                        // Threshold badge (top)
                        if let badgeLabel = thresholdStatus.label {
                            thresholdBadgeView(badgeLabel)
                        }

                        Spacer()

                        // Quantity (center)
                        Text(formatQuantity(item.quantity))
                            .font(quantityFont)
                            .foregroundColor(thresholdStatus.color)

                        // Unit (below quantity)
                        Text(unitDisplay.isEmpty ? "QTY" : unitDisplay)
                            .font(smallCaptionFont)
                            .foregroundColor(unitDisplay.isEmpty ? OPSStyle.Colors.tertiaryText.opacity(0.5) : OPSStyle.Colors.tertiaryText)

                        Spacer()
                    }
                    .frame(minWidth: 50 * scale)
                } else {
                    // Not full size: Just quantity (badge shown next to name)
                    Text(formatQuantity(item.quantity))
                        .font(quantityFont)
                        .foregroundColor(thresholdStatus.color)
                }
            }
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 8 * scale)
        }
        .frame(height: cardHeight)
        .background(isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.15) : OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            if !isSelectionMode {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showingActions = true
            }
        } onPressingChanged: { pressing in
            isLongPressing = pressing
        }
        .confirmationDialog(item.name, isPresented: $showingActions, titleVisibility: .visible) {
            Button("Select") { onSelect() }
            Button("Edit") { onEdit() }
            Button("Delete", role: .destructive) { showingDeleteConfirmation = true }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Item", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Delete \"\(item.name)\"? This cannot be undone.")
        }
    }

    // MARK: - Threshold Badge

    private func thresholdBadgeView(_ label: String) -> some View {
        Text(label)
            .font(OPSStyle.Inventory.ThresholdBadge.font)
            .foregroundColor(thresholdStatus.color)
            .padding(.horizontal, OPSStyle.Inventory.ThresholdBadge.paddingHorizontal)
            .padding(.vertical, OPSStyle.Inventory.ThresholdBadge.paddingVertical)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Inventory.ThresholdBadge.cornerRadius)
                    .fill(thresholdStatus.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Inventory.ThresholdBadge.cornerRadius)
                    .stroke(thresholdStatus.color, lineWidth: 1)
            )
    }

    // MARK: - Metadata Item

    private func metadataItem(icon: String, text: String, isEmpty: Bool = false) -> some View {
        HStack(spacing: 4 * scale) {
            Image(systemName: icon)
                .font(.system(size: 11 * scale))
                .foregroundColor(isEmpty ? OPSStyle.Colors.tertiaryText.opacity(0.5) : OPSStyle.Colors.tertiaryText)
            Text(text)
                .font(smallCaptionFont)
                .foregroundColor(isEmpty ? OPSStyle.Colors.tertiaryText.opacity(0.5) : OPSStyle.Colors.tertiaryText)
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    private func formatQuantity(_ quantity: Double) -> String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(quantity))
        } else {
            return String(format: "%.1f", quantity)
        }
    }
}

// MARK: - Inventory Tag Badge

/// Reusable monochromatic tag badge for inventory views
struct InventoryTagBadge: View {
    let tag: String
    var size: OPSStyle.Inventory.TagSize = .standard
    var scale: CGFloat = 1.0
    var showRemoveButton: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.uppercased())
                .font(size.font)
                .foregroundColor(OPSStyle.Inventory.TagBadge.textColor)

            if showRemoveButton {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: size == .button ? 10 : 8, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, size.paddingHorizontal * scale)
        .padding(.vertical, size.paddingVertical * scale)
        .background(OPSStyle.Inventory.TagBadge.backgroundColor)
        .cornerRadius(size.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(OPSStyle.Inventory.TagBadge.borderColor, lineWidth: 1)
        )
    }
}

/// Tag badge with add/remove action indicator
struct InventoryTagActionBadge: View {
    let tag: String
    let isAdd: Bool
    var size: OPSStyle.Inventory.TagSize = .standard
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isAdd ? "plus" : "minus")
                    .font(.system(size: size == .button ? 12 : 10, weight: .bold))
                Text(tag.uppercased())
                    .font(size.font)
                if let subtitle = subtitle {
                    Text("(\(subtitle))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .foregroundColor(OPSStyle.Inventory.TagBadge.textColor)
            .padding(.horizontal, size.paddingHorizontal)
            .padding(.vertical, size.paddingVertical)
            .background(OPSStyle.Inventory.TagBadge.backgroundColor)
            .cornerRadius(size.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(OPSStyle.Inventory.TagBadge.borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Tag badge showing pending change (add/remove)
struct InventoryPendingTagBadge: View {
    let tag: String
    let isAdding: Bool
    var size: OPSStyle.Inventory.TagSize = .standard
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Text(isAdding ? "+" : "−")
                    .font(size == .button ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.captionBold)
                Text(tag.uppercased())
                    .font(size.font)
                Image(systemName: "xmark")
                    .font(.system(size: size == .button ? 10 : 8, weight: .bold))
            }
            .foregroundColor(OPSStyle.Inventory.TagBadge.textColor)
            .padding(.horizontal, size.paddingHorizontal)
            .padding(.vertical, size.paddingVertical)
            .background(OPSStyle.Inventory.TagBadge.backgroundColor)
            .cornerRadius(size.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(OPSStyle.Inventory.TagBadge.borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    InventoryListView(
        items: [],
        isSelectionMode: false,
        selectedItemIds: .constant([]),
        scale: 1.0,
        onItemTap: { _ in },
        onItemEdit: { _ in },
        onItemDelete: { _ in },
        onItemSelect: { _ in }
    )
    .environmentObject(DataController())
}
