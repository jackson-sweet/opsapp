//
//  LinkedProductsAttachSheet.swift
//  OPS
//
//  Inline picker for "+ ATTACH EXISTING" inside the TaskTypeSheet's LINKED
//  PRODUCTS section. Lists products that aren't already attached to the
//  current task type (either unset or pointing elsewhere). Tapping a
//  product re-pins its `task_type_ref` to the current task type and
//  triggers a re-fetch on the parent sheet. Cross-reassignments surface
//  a confirm dialog to avoid silently moving a product the operator may
//  still expect under its current parent.
//

import SwiftUI
import SwiftData

struct LinkedProductsAttachSheet: View {
    /// The TaskType being authored. Products picked here get their
    /// `task_type_ref` rewritten to this id.
    let targetTaskTypeId: String
    let targetTaskTypeName: String

    /// Fires after a successful attach with the newly-pinned product. Parent
    /// reloads the LINKED PRODUCTS list from the local store.
    let onAttach: (Product) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery: String = ""
    @State private var products: [Product] = []
    @State private var taskTypeLookup: [String: String] = [:]   // taskTypeId → display
    @State private var pendingReassign: Product? = nil
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    /// Products available to attach. Excludes:
    /// - Products already pinned to `targetTaskTypeId` (no-op).
    /// - Soft-deleted products.
    /// - Material/Fee products whose task type field is intentionally unused
    ///   (only Service-category products participate in task generation).
    private var attachableProducts: [Product] {
        let lower = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return products.filter { product in
            let alreadyAttached = (product.taskTypeRef == targetTaskTypeId) || (product.taskTypeId == targetTaskTypeId)
            if alreadyAttached { return false }
            if product.type != .labor { return false }
            if !lower.isEmpty {
                return product.name.lowercased().contains(lower)
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchField
                    if isLoading {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                            .padding(OPSStyle.Layout.spacing4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if attachableProducts.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(spacing: OPSStyle.Layout.spacing2) {
                                ForEach(attachableProducts, id: \.id) { product in
                                    productRow(product)
                                }
                            }
                            .padding(OPSStyle.Layout.spacing3)
                        }
                    }
                }
            }
            .navigationTitle("ATTACH PRODUCT")
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
        .onAppear(perform: load)
        .alert(
            "REASSIGN PRODUCT?",
            isPresented: Binding(
                get: { pendingReassign != nil },
                set: { if !$0 { pendingReassign = nil } }
            ),
            presenting: pendingReassign
        ) { product in
            Button("Cancel", role: .cancel) { pendingReassign = nil }
            Button("Reassign") {
                Task { await attach(product) }
            }
        } message: { product in
            let currentParent = displayName(forTaskTypeId: product.taskTypeRef ?? product.taskTypeId)
            Text("\(product.name) is currently linked to \(currentParent). This will move it to \(targetTaskTypeName).")
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image("ops.search")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField("Search products", text: $searchQuery)
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
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Row

    private func productRow(_ product: Product) -> some View {
        let currentParentId = product.taskTypeRef ?? product.taskTypeId
        let isReassign = (currentParentId != nil) && !(currentParentId?.isEmpty ?? true)
        let currentParentName = isReassign ? displayName(forTaskTypeId: currentParentId) : nil
        let priceText = formatPrice(product.basePrice) + "/" + product.pricingUnit.rawValue

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isReassign {
                pendingReassign = product
            } else {
                Task { await attach(product) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(product.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text("• LABOR")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(priceText.uppercased())
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    if let currentParentName {
                        Text("· LINKED TO \(currentParentName.uppercased())")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    }
                    Spacer()
                }
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isSaving)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// NO SERVICE PRODUCTS AVAILABLE")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Only LABOR-type products can attach to a task type. Quick-add a new product or convert an existing material/fee to a service.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
        }
        .padding(OPSStyle.Layout.spacing4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

    private func load() {
        guard !companyId.isEmpty else { isLoading = false; return }
        let productDescriptor = FetchDescriptor<Product>(
            predicate: #Predicate<Product> { product in
                product.companyId == companyId
            },
            sortBy: [SortDescriptor(\.name)]
        )
        if let allProducts = try? modelContext.fetch(productDescriptor) {
            products = allProducts.filter { $0.isActive }
        }
        let typeDescriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { taskType in
                taskType.companyId == companyId && taskType.deletedAt == nil
            }
        )
        if let allTypes = try? modelContext.fetch(typeDescriptor) {
            taskTypeLookup = Dictionary(uniqueKeysWithValues: allTypes.map { ($0.id, $0.display) })
        }
        isLoading = false
    }

    private func displayName(forTaskTypeId id: String?) -> String {
        guard let id, let name = taskTypeLookup[id] else { return "another task type" }
        return name
    }

    private func formatPrice(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    // MARK: - Attach

    @MainActor
    private func attach(_ product: Product) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let repo = ProductRepository(companyId: companyId)
        var fields = UpdateProductDTO()
        fields.taskTypeRef = targetTaskTypeId
        fields.taskTypeId = targetTaskTypeId  // legacy mirror so old code paths see the new parent too
        do {
            let dto = try await repo.update(product.id, fields: fields)
            product.taskTypeRef = dto.taskTypeRef ?? targetTaskTypeId
            product.taskTypeId = dto.taskTypeId
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            pendingReassign = nil
            onAttach(product)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
            pendingReassign = nil
        }
    }
}
