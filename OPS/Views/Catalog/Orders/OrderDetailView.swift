//
//  OrderDetailView.swift
//  OPS
//
//  Detail surface for a single CatalogOrder. Editable in DRAFT status,
//  read-only-ish in SENT/FULFILLED/CANCELLED with status-specific CTAs.
//
//  Persists changes via CatalogOrderRepository. SwiftData rows are
//  refreshed on next sync — for the immediate UX we mutate the local
//  models in `modelContext` so the view reflects the user's action
//  without waiting for the round-trip.
//

import SwiftUI
import SwiftData

struct OrderDetailView: View {
    let orderId: String

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var orders: [CatalogOrder]
    @Query private var orderItems: [CatalogOrderItem]
    @Query private var variants: [CatalogVariant]
    @Query private var families: [CatalogItem]
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]

    @State private var titleField: String = ""
    @State private var supplierNameField: String = ""
    @State private var supplierContactField: String = ""
    @State private var expectedDeliveryField: Date? = nil
    @State private var notesField: String = ""

    @State private var editingItemId: String? = nil
    @State private var editQuantityText: String = ""
    @State private var editCostText: String = ""

    @State private var isSaving: Bool = false
    @State private var isCommittingTransition: Bool = false
    @State private var pendingDeleteConfirm: Bool = false
    @State private var pendingCancelConfirm: Bool = false
    @State private var errorMessage: String? = nil

    private var order: CatalogOrder? {
        orders.first { $0.id == orderId }
    }

    private var items: [CatalogOrderItem] {
        orderItems
            .filter { $0.orderId == orderId }
            .sorted { $0.id < $1.id }
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var orderRepo: CatalogOrderRepository {
        CatalogOrderRepository(companyId: companyId)
    }

    private var isDraft: Bool { order?.status == .draft }
    private var isSent: Bool { order?.status == .sent }
    private var canEdit: Bool { isDraft }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            if let order = order {
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        statusHeader(order: order)
                        detailsSection
                        itemsSection
                        actionButtons(order: order)
                        if let err = errorMessage {
                            Text(err)
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.errorText)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                }
            } else {
                missingState
            }
        }
        .navigationTitle("ORDER")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canEdit && hasUnsavedChanges {
                    Button("SAVE", action: saveDetails)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .disabled(isSaving)
                }
            }
        }
        .onAppear { hydrateFields(from: order) }
        .onChange(of: order?.id) { _, _ in hydrateFields(from: order) }
        .alert("Delete draft order?", isPresented: $pendingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteDraft() }
        } message: {
            Text("This removes the draft and all of its items. Cannot be undone.")
        }
        .alert("Cancel order?", isPresented: $pendingCancelConfirm) {
            Button("Keep order", role: .cancel) {}
            Button("Cancel order", role: .destructive) { cancelOrder() }
        } message: {
            Text("Marks this order cancelled. The history is preserved.")
        }
    }

    // MARK: - Header

    private func statusHeader(order: CatalogOrder) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("//")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(order.status.rawValue.uppercased())
                .font(OPSStyle.Typography.section)
                .foregroundColor(statusColor(for: order.status))
            Spacer()
            Text("\(items.count) ITEM\(items.count == 1 ? "" : "S")")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func statusColor(for status: CatalogOrderStatus) -> Color {
        switch status {
        case .suggested, .draft: return OPSStyle.Colors.primaryText
        case .sent:              return OPSStyle.Colors.warningText
        case .fulfilled:         return OPSStyle.Colors.successStatus
        case .cancelled:         return OPSStyle.Colors.errorText
        }
    }

    // MARK: - Details section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("DETAILS")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                fieldRow(label: "TITLE", text: $titleField, placeholder: "Optional title")
                fieldRow(label: "SUPPLIER", text: $supplierNameField, placeholder: "e.g. Trex")
                fieldRow(label: "CONTACT", text: $supplierContactField, placeholder: "Phone / email")
                deliveryRow
                notesRow
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    @ViewBuilder
    private func fieldRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField(placeholder, text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .disabled(!canEdit)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    private var deliveryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EXPECTED DELIVERY")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            HStack {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { expectedDeliveryField ?? Date() },
                        set: { expectedDeliveryField = $0 }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .disabled(!canEdit)
                Spacer()
                if expectedDeliveryField != nil && canEdit {
                    Button {
                        expectedDeliveryField = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .accessibilityLabel("Clear expected delivery")
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOTES")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextEditor(text: $notesField)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .disabled(!canEdit)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .frame(minHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    // MARK: - Items section

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("ITEMS")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            if items.isEmpty {
                Text("// NO ITEMS")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(items, id: \.id) { item in
                        itemRow(item)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: CatalogOrderItem) -> some View {
        let variant = variants.first { $0.id == item.catalogVariantId }
        let family = variant.flatMap { v in families.first { $0.id == v.catalogItemId } }
        let label = variantLabel(for: item.catalogVariantId)
        let isEditing = editingItemId == item.id

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((family?.name ?? "Unknown").uppercased())
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if !label.isEmpty {
                        Text(label)
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isEditing {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            editingItemId = nil
                        } label: {
                            Text("CANCEL")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .frame(height: OPSStyle.Layout.touchTargetMin)
                                .padding(.horizontal, OPSStyle.Layout.spacing2)
                        }
                        Button {
                            commitItemEdit(item)
                        } label: {
                            Text("SAVE")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(height: OPSStyle.Layout.touchTargetMin)
                                .padding(.horizontal, OPSStyle.Layout.spacing2)
                        }
                    }
                } else if canEdit {
                    Menu {
                        Button("Edit", systemImage: "pencil") {
                            startEditing(item)
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            removeItem(item)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(
                                width: OPSStyle.Layout.touchTargetMin,
                                height: OPSStyle.Layout.touchTargetMin
                            )
                    }
                    .accessibilityLabel("Item options")
                }
            }

            if isEditing {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    inlineNumericField(label: "QTY", text: $editQuantityText)
                    inlineNumericField(label: "COST", text: $editCostText)
                }
            } else {
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    HStack(spacing: 4) {
                        Text("\(formatNumber(item.quantityRequested))")
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("UNITS")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    if let cost = item.costPerUnit {
                        HStack(spacing: 4) {
                            Text("@")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("$\(String(format: "%.2f", cost))")
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    @ViewBuilder
    private func inlineNumericField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.background.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    // MARK: - Action buttons

    private func actionButtons(order: CatalogOrder) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            switch order.status {
            case .draft:
                primaryActionButton(title: "MARK SENT", color: OPSStyle.Colors.primaryAccent) {
                    transition { try await orderRepo.markSent(order.id) }
                }
                secondaryActionButton(title: "CANCEL ORDER", color: OPSStyle.Colors.errorText) {
                    pendingCancelConfirm = true
                }
                secondaryActionButton(title: "DELETE DRAFT", color: OPSStyle.Colors.errorText) {
                    pendingDeleteConfirm = true
                }
            case .sent:
                primaryActionButton(title: "MARK FULFILLED", color: OPSStyle.Colors.successStatus) {
                    transition { try await orderRepo.markFulfilled(order.id) }
                }
                secondaryActionButton(title: "CANCEL ORDER", color: OPSStyle.Colors.errorText) {
                    pendingCancelConfirm = true
                }
            case .fulfilled, .cancelled, .suggested:
                EmptyView()
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private func primaryActionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.background)
                Spacer()
            }
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .fill(color)
            )
        }
        .disabled(isCommittingTransition)
        .opacity(isCommittingTransition ? 0.5 : 1)
    }

    @ViewBuilder
    private func secondaryActionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(color)
                Spacer()
            }
            .frame(height: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(color.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .disabled(isCommittingTransition)
        .opacity(isCommittingTransition ? 0.5 : 1)
    }

    // MARK: - Empty / missing

    private var missingState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// ORDER NOT FOUND")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("This order may have been deleted.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func hydrateFields(from order: CatalogOrder?) {
        guard let order = order else { return }
        titleField = order.title ?? ""
        supplierNameField = order.supplierName ?? ""
        supplierContactField = order.supplierContact ?? ""
        expectedDeliveryField = order.expectedDeliveryDate
        notesField = order.notes ?? ""
    }

    private var hasUnsavedChanges: Bool {
        guard let order = order else { return false }
        return (order.title ?? "") != titleField
            || (order.supplierName ?? "") != supplierNameField
            || (order.supplierContact ?? "") != supplierContactField
            || order.expectedDeliveryDate != expectedDeliveryField
            || (order.notes ?? "") != notesField
    }

    private func variantLabel(for variantId: String) -> String {
        guard let variant = variants.first(where: { $0.id == variantId }) else { return "" }
        let familyOptions = allOptions
            .filter { $0.catalogItemId == variant.catalogItemId }
            .sorted { $0.sortOrder < $1.sortOrder }
        let variantValueIds = Set(allVariantOptionValues
            .filter { $0.variantId == variant.id }
            .map { $0.optionValueId })
        let valuesById = Dictionary(uniqueKeysWithValues: allOptionValues.map { ($0.id, $0) })

        var parts: [String] = []
        for option in familyOptions {
            if let v = variantValueIds
                .compactMap({ valuesById[$0] })
                .first(where: { $0.optionId == option.id }) {
                parts.append(v.value)
            }
        }
        return parts.joined(separator: " · ")
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    // MARK: - Mutations

    private func saveDetails() {
        guard let order = order, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        var fields = UpdateCatalogOrderDTO()
        fields.title = titleField.isEmpty ? nil : titleField
        fields.supplierName = supplierNameField.isEmpty ? nil : supplierNameField
        fields.supplierContact = supplierContactField.isEmpty ? nil : supplierContactField
        fields.notes = notesField.isEmpty ? nil : notesField
        if let date = expectedDeliveryField {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            f.locale = Locale(identifier: "en_US_POSIX")
            fields.expectedDeliveryDate = f.string(from: date)
        }

        Task {
            do {
                _ = try await orderRepo.updateOrder(order.id, fields: fields)
                await MainActor.run {
                    order.title = fields.title
                    order.supplierName = fields.supplierName
                    order.supplierContact = fields.supplierContact
                    order.expectedDeliveryDate = expectedDeliveryField
                    order.notes = fields.notes
                    order.updatedAt = Date()
                    try? modelContext.save()
                    isSaving = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Save failed: \(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func startEditing(_ item: CatalogOrderItem) {
        editingItemId = item.id
        editQuantityText = formatNumber(item.quantityRequested)
        editCostText = item.costPerUnit.map { String(format: "%.2f", $0) } ?? ""
    }

    private func commitItemEdit(_ item: CatalogOrderItem) {
        guard let qty = Double(editQuantityText.replacingOccurrences(of: ",", with: ".")) else {
            errorMessage = "Quantity must be a number."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let cost = Double(editCostText.replacingOccurrences(of: ",", with: "."))

        var fields = UpdateCatalogOrderItemDTO()
        fields.quantityRequested = qty
        fields.costPerUnit = cost

        Task {
            do {
                _ = try await orderRepo.updateItem(item.id, fields: fields)
                await MainActor.run {
                    item.quantityRequested = qty
                    item.costPerUnit = cost
                    try? modelContext.save()
                    editingItemId = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Update failed: \(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func removeItem(_ item: CatalogOrderItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                try await orderRepo.removeItem(item.id)
                await MainActor.run {
                    modelContext.delete(item)
                    try? modelContext.save()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Remove failed: \(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func transition(_ work: @escaping () async throws -> CatalogOrderDTO) {
        guard let order = order, !isCommittingTransition else { return }
        isCommittingTransition = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                let dto = try await work()
                await MainActor.run {
                    order.status = CatalogOrderStatus(rawValue: dto.status) ?? order.status
                    order.sentAt = dto.sentAt.flatMap { SupabaseDate.parse($0) }
                    order.fulfilledAt = dto.fulfilledAt.flatMap { SupabaseDate.parse($0) }
                    order.cancelledAt = dto.cancelledAt.flatMap { SupabaseDate.parse($0) }
                    order.updatedAt = Date()
                    try? modelContext.save()
                    isCommittingTransition = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isCommittingTransition = false
                    errorMessage = "Transition failed: \(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func cancelOrder() {
        transition { try await orderRepo.markCancelled(self.order!.id) }
    }

    private func deleteDraft() {
        guard let order = order else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                try await orderRepo.softDeleteOrder(order.id)
                await MainActor.run {
                    order.deletedAt = Date()
                    try? modelContext.save()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Delete failed: \(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
