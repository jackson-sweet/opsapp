import SwiftUI

// MARK: - GuidedStockCaptureView
//
// CAPTURE stage — the brain-dump phase of the guided stock wizard.
// The operator names every thing they stock or sell; the container owns navigation,
// the ORGANIZE CTA, and the progress bar. This view owns the list + ADD button only.
//
// Surface hierarchy:
//   • L1 glass canvas — owned by the flow container (background gradient)
//   • L2 .nestedCard() — each item row (sits directly on the gradient canvas)
//
// Binding pattern: `ForEach($model.capturedItems)` — SwiftUI collection binding
// so field edits mutate the model live (enabling the container's CTA via
// `model.capturableItemCount`).

struct GuidedStockCaptureView: View {

    @ObservedObject var model: GuidedStockSetupModel

    /// Tracks which item's name field is focused. Keyed by item id.
    @FocusState private var focusedId: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    headerSection
                    if model.capturedItems.isEmpty {
                        emptyState
                    } else {
                        itemList
                    }
                    addButton(proxy: proxy)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing5)
            }
        }
        .onDisappear {
            model.persist()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("LIST PARTS + WORK")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("One row per physical part, material, service, or bundle component. Write top rail, post, bracket, screws, gate kit, install labor - not just rail system.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("—")
                .font(.custom("Mohave-Light", size: 48))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("// ADD YOUR FIRST ITEM")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    // MARK: - Item list

    private var itemList: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach($model.capturedItems) { $item in
                CaptureItemRow(
                    item: $item,
                    focusedId: $focusedId,
                    onReturnKey: {
                        handleReturn(afterItemId: item.id)
                    },
                    onKindChange: {
                        model.persist()
                    },
                    onDelete: {
                        deleteItem(id: item.id)
                    }
                )
                .id(item.id)
            }
        }
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    // MARK: - ADD button

    private func addButton(proxy: ScrollViewProxy) -> some View {
        Button {
            addItem(proxy: proxy)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.plus)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("ADD")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetMin)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.separator, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a new item")
    }

    // MARK: - Actions

    private func addItem(proxy: ScrollViewProxy) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let newItem = GuidedCapturedItem(name: "", kind: .stock)
        model.capturedItems.append(newItem)
        model.persist()
        let newId = newItem.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(OPSStyle.Animation.panel) {
                proxy.scrollTo(newId, anchor: .center)
            }
            focusedId = newId
        }
    }

    private func handleReturn(afterItemId id: String) {
        guard let idx = model.capturedItems.firstIndex(where: { $0.id == id }) else { return }
        let current = model.capturedItems[idx]
        // Only append a new row if the current field is non-empty
        if !current.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let newItem = GuidedCapturedItem(name: "", kind: .stock)
            model.capturedItems.insert(newItem, at: idx + 1)
            model.persist()
            let newId = newItem.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedId = newId
            }
        } else {
            // Current field is empty — dismiss keyboard
            focusedId = nil
        }
    }

    private func deleteItem(id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.capturedItems.removeAll { $0.id == id }
        model.persist()
    }
}

// MARK: - CaptureItemRow

/// One item row: name field + STOCK/SELL/BOTH chip group + swipe-to-delete.
/// Rendered as an L2 nested card (.nestedCard) per surface hierarchy.
private struct CaptureItemRow: View {

    @Binding var item: GuidedCapturedItem
    var focusedId: FocusState<String?>.Binding
    let onReturnKey: () -> Void
    let onKindChange: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            // Name field
            TextField("", text: $item.name, prompt: Text("Top rail, post, bracket, install labor")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            )
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .submitLabel(.next)
            .focused(focusedId, equals: item.id)
            .onSubmit {
                onReturnKey()
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .accessibilityLabel("Item name")

            // Separator hairline between field and chip row
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: OPSStyle.Layout.Border.standard)

            // Kind chip group
            KindChipGroup(kind: $item.kind, onChange: onKindChange)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .nestedCard()
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: OPSStyle.Icons.trashFill)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: OPSStyle.Icons.trashFill)
            }
        }
    }
}

// MARK: - KindChipGroup

/// 3-way single-select chip group: STOCK · SELL · BOTH
/// Each chip is 36pt tall per spec §4.3.
/// Selected: subtle fill (`surfaceActive`) + primaryText.
/// Unselected: no fill + tertiaryText.
private struct KindChipGroup: View {

    @Binding var kind: GuidedItemKind
    /// Called when the user selects a different kind. Caller persists the model.
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(GuidedItemKind.allCases, id: \.self) { option in
                chip(for: option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(for option: GuidedItemKind) -> some View {
        let isSelected = kind == option
        return Button {
            guard kind != option else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            kind = option
            onChange()
        } label: {
            Text(option.chipLabel)
                .font(OPSStyle.Typography.category)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                .frame(height: 36)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                        .fill(isSelected ? OPSStyle.Colors.surfaceActive : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? OPSStyle.Colors.line : OPSStyle.Colors.separator,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(OPSStyle.Animation.hover, value: isSelected)
        .accessibilityLabel(option.chipLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - GuidedItemKind display

private extension GuidedItemKind {
    var chipLabel: String {
        switch self {
        case .stock: return "STOCK"
        case .sell:  return "SELL"
        case .both:  return "BOTH"
        }
    }
}
