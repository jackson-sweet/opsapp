//
//  OrdersSheet.swift
//  OPS
//
//  Three-segment sheet (SUGGESTED / DRAFT / SENT) for catalog orders.
//  Closes Bug e08c63a2 — gives the user a real "create order" path.
//

import SwiftUI
import SwiftData

enum OrdersSubSegment: String, CaseIterable, Identifiable {
    case suggested = "SUGGESTED"
    case draft = "DRAFT"
    case sent = "SENT"
    var id: String { rawValue }
}

struct OrdersSheet: View {
    let initialSubSegment: OrdersSubSegment

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var canManageOrders: Bool { permissionStore.can("catalog.orders.manage") }

    @AppStorage("catalog.orders.subSegment") private var subSegmentRaw: String = OrdersSubSegment.suggested.rawValue

    @Query private var allOrders: [CatalogOrder]
    @Query private var allOrderItems: [CatalogOrderItem]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allFamilies: [CatalogItem]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]

    @State private var addedVariantIds: Set<String> = []
    @State private var workingDraftId: String? = nil
    @State private var isCreatingDraft: Bool = false
    @State private var errorMessage: String? = nil
    @State private var navigateToOrderId: String? = nil

    init(initialSubSegment: OrdersSubSegment = .suggested) {
        self.initialSubSegment = initialSubSegment
    }

    private var subSegment: OrdersSubSegment {
        OrdersSubSegment(rawValue: subSegmentRaw) ?? .suggested
    }

    private func setSubSegment(_ segment: OrdersSubSegment) {
        subSegmentRaw = segment.rawValue
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var orderRepo: CatalogOrderRepository {
        CatalogOrderRepository(companyId: companyId)
    }

    // MARK: - Filtered orders

    private var draftOrders: [CatalogOrder] {
        allOrders
            .filter { $0.companyId == companyId && $0.deletedAt == nil && $0.status == .draft }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var sentOrders: [CatalogOrder] {
        allOrders
            .filter {
                $0.companyId == companyId
                    && $0.deletedAt == nil
                    && ($0.status == .sent || $0.status == .fulfilled)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Suggestions

    private var suggestions: [OrderSuggestionEngine.Suggestion] {
        let companyVariants = allVariants.filter { $0.companyId == companyId }
        let companyFamilies = allFamilies.filter { $0.companyId == companyId }
        let companyCategories = allCategories.filter { $0.companyId == companyId }

        var raw = OrderSuggestionEngine().suggest(
            variants: companyVariants,
            families: companyFamilies,
            categories: companyCategories
        )
        // Hydrate variant labels for the rows.
        let optionsByItemId = Dictionary(grouping: allOptions, by: \.catalogItemId)
        let variantOptionValuesByVariantId = Dictionary(grouping: allVariantOptionValues, by: \.variantId)
        let optionValuesById = Dictionary(uniqueKeysWithValues: allOptionValues.map { ($0.id, $0) })
        let variantsById = Dictionary(uniqueKeysWithValues: companyVariants.map { ($0.id, $0) })

        for i in 0..<raw.count {
            let s = raw[i]
            guard let variant = variantsById[s.variantId] else { continue }
            let familyOptions = (optionsByItemId[variant.catalogItemId] ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
            let variantValueIds = Set((variantOptionValuesByVariantId[variant.id] ?? [])
                .map(\.optionValueId))
            var parts: [String] = []
            for option in familyOptions {
                if let v = variantValueIds
                    .compactMap({ optionValuesById[$0] })
                    .first(where: { $0.optionId == option.id }) {
                    parts.append(v.value)
                }
            }
            raw[i].variantLabel = parts.joined(separator: " · ")
        }
        return raw.sorted { (lhs: OrderSuggestionEngine.Suggestion, rhs: OrderSuggestionEngine.Suggestion) -> Bool in
            // Critical first, then by family name then variant label.
            let lhsCritical: Bool = {
                if let c = lhs.criticalThreshold { return lhs.currentQuantity <= c }
                return false
            }()
            let rhsCritical: Bool = {
                if let c = rhs.criticalThreshold { return rhs.currentQuantity <= c }
                return false
            }()
            if lhsCritical != rhsCritical { return lhsCritical && !rhsCritical }
            if lhs.familyName != rhs.familyName { return lhs.familyName < rhs.familyName }
            return lhs.variantLabel < rhs.variantLabel
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    subSegmentBar

                    Group {
                        switch subSegment {
                        case .suggested: suggestedContent
                        case .draft:     draftContent
                        case .sent:      sentContent
                        }
                    }
                    .animation(OPSStyle.Animation.panel, value: subSegment)
                }
            }
            .catalogNavigationTitle("ORDERS")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .navigationDestination(item: $navigateToOrderId) { orderId in
                OrderDetailView(orderId: orderId)
                    .environmentObject(dataController)
            }
        }
        .onAppear {
            if subSegmentRaw == OrdersSubSegment.suggested.rawValue && initialSubSegment != .suggested {
                // First-launch override only — `initialSubSegment` wins over
                // the persisted choice when explicitly passed.
                setSubSegment(initialSubSegment)
            } else if !OrdersSubSegment.allCases.map(\.rawValue).contains(subSegmentRaw) {
                setSubSegment(initialSubSegment)
            }
            // If the caller explicitly passed an initial sub-segment, honor it
            // every time the sheet opens — the rail deep link must always
            // land on SUGGESTED.
            setSubSegment(initialSubSegment)
        }
    }

    // MARK: - Sub-segment bar

    private var subSegmentBar: some View {
        HStack(spacing: 0) {
            ForEach(OrdersSubSegment.allCases) { segment in
                Button {
                    setSubSegment(segment)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 0) {
                        Text(segment.rawValue)
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(
                                subSegment == segment
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.tertiaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                        Rectangle()
                            .fill(
                                subSegment == segment
                                    ? OPSStyle.Colors.text
                                    : Color.clear
                            )
                            .frame(height: 2)
                    }
                }
                .accessibilityLabel("\(segment.rawValue) sub-segment")
                .accessibilityAddTraits(subSegment == segment ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing1)
    }

    // MARK: - SUGGESTED

    private var suggestedContent: some View {
        Group {
            if suggestions.isEmpty {
                emptyState(
                    title: "// NO SUGGESTED ORDERS — STOCK IS GOOD",
                    body: "When variants drop below their warning threshold, they show up here."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        if canManageOrders {
                            createDraftFromAllButton
                        }
                        if let err = errorMessage {
                            Text(err)
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.errorText)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }
                        Text("\(suggestions.count) ITEM\(suggestions.count == 1 ? "" : "S") BELOW THRESHOLD")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)

                        VStack(spacing: OPSStyle.Layout.spacing1) {
                            ForEach(suggestions) { suggestion in
                                SuggestedOrderRow(
                                    suggestion: suggestion,
                                    isAdded: addedVariantIds.contains(suggestion.variantId),
                                    addAction: canManageOrders ? { addToDraft(suggestion) } : nil
                                )
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                }
            }
        }
    }

    private var createDraftFromAllButton: some View {
        Button(action: createDraftFromAllSuggestions) {
            HStack {
                Spacer()
                if isCreatingDraft {
                    ProgressView()
                        .tint(OPSStyle.Colors.background)
                } else {
                    Text("CREATE DRAFT FROM ALL")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.background)
                }
                Spacer()
            }
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .fill(OPSStyle.Colors.primaryAccent)
            )
        }
        .disabled(isCreatingDraft || suggestions.isEmpty)
        .opacity(isCreatingDraft || suggestions.isEmpty ? 0.5 : 1)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - DRAFT

    private var draftContent: some View {
        Group {
            if draftOrders.isEmpty {
                emptyState(
                    title: "// NO DRAFT ORDERS",
                    body: "Drafts you build from suggestions appear here until they're sent."
                )
            } else {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(draftOrders, id: \.id) { order in
                            orderRow(order, items: itemsFor(order: order))
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
        }
    }

    // MARK: - SENT

    private var sentContent: some View {
        Group {
            if sentOrders.isEmpty {
                emptyState(
                    title: "// NO SENT ORDERS",
                    body: "Orders you've sent or fulfilled appear here."
                )
            } else {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(sentOrders, id: \.id) { order in
                            orderRow(order, items: itemsFor(order: order))
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
        }
    }

    private func itemsFor(order: CatalogOrder) -> [CatalogOrderItem] {
        allOrderItems.filter { $0.orderId == order.id }
    }

    @ViewBuilder
    private func orderRow(_ order: CatalogOrder, items: [CatalogOrderItem]) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            navigateToOrderId = order.id
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text((order.title ?? defaultTitle(for: order)).uppercased())
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(order.status.rawValue.uppercased())
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(statusColor(for: order.status))
                        Text("·")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("\(items.count) ITEM\(items.count == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        if let supplier = order.supplierName, !supplier.isEmpty {
                            Text("·")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(supplier)
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface()
        }
        .buttonStyle(.plain)
    }

    private func statusColor(for status: CatalogOrderStatus) -> Color {
        switch status {
        case .suggested, .draft: return OPSStyle.Colors.primaryText
        case .sent:              return OPSStyle.Colors.warningText
        case .fulfilled:         return OPSStyle.Colors.successStatus
        case .cancelled:         return OPSStyle.Colors.errorText
        }
    }

    private func defaultTitle(for order: CatalogOrder) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "Order \(f.string(from: order.createdAt))"
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyState(title: String, body: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Spacer()
            Text(title)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Text(body)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mutations

    private func unitCost(forVariantId id: String) -> Double {
        guard let variant = allVariants.first(where: { $0.id == id }),
              let family = allFamilies.first(where: { $0.id == variant.catalogItemId }) else {
            return 0
        }
        return variant.unitCostOverride ?? family.defaultUnitCost ?? 0
    }

    /// Create a single draft order populated with every suggestion. Used by
    /// the "Create draft from all" CTA.
    private func createDraftFromAllSuggestions() {
        guard !isCreatingDraft, !suggestions.isEmpty else { return }
        isCreatingDraft = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let userId = SupabaseService.shared.currentUserId
        let snapshot = suggestions

        Task {
            do {
                let createDTO = CreateCatalogOrderDTO(
                    companyId: companyId,
                    status: "draft",
                    title: nil,
                    supplierName: nil,
                    supplierContact: nil,
                    expectedDeliveryDate: nil,
                    notes: nil,
                    createdById: userId
                )
                let orderDTO = try await orderRepo.createOrder(createDTO)
                let orderModel = orderDTO.toModel()

                var itemModels: [CatalogOrderItem] = []
                for s in snapshot {
                    let cost = unitCost(forVariantId: s.variantId)
                    let itemDTO = CreateCatalogOrderItemDTO(
                        orderId: orderModel.id,
                        catalogVariantId: s.variantId,
                        quantityRequested: s.recommendedQuantity,
                        costPerUnit: cost > 0 ? cost : nil,
                        notes: nil
                    )
                    let resp = try await orderRepo.addItem(orderId: orderModel.id, dto: itemDTO)
                    itemModels.append(resp.toModel())
                }

                await MainActor.run {
                    modelContext.insert(orderModel)
                    for it in itemModels { modelContext.insert(it) }
                    try? modelContext.save()
                    addedVariantIds.formUnion(snapshot.map(\.variantId))
                    workingDraftId = orderModel.id
                    isCreatingDraft = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    setSubSegment(.draft)
                    navigateToOrderId = orderModel.id
                }
            } catch {
                await MainActor.run {
                    isCreatingDraft = false
                    errorMessage = "Failed to create draft: \(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    /// Add a single suggestion to the working draft order, creating one on
    /// demand if none exists yet.
    private func addToDraft(_ suggestion: OrderSuggestionEngine.Suggestion) {
        guard !addedVariantIds.contains(suggestion.variantId) else { return }
        errorMessage = nil
        let userId = SupabaseService.shared.currentUserId

        Task {
            do {
                let draftId: String
                let needsLocalInsert: Bool
                if let id = workingDraftId,
                   draftOrders.contains(where: { $0.id == id }) {
                    draftId = id
                    needsLocalInsert = false
                } else {
                    let createDTO = CreateCatalogOrderDTO(
                        companyId: companyId,
                        status: "draft",
                        title: nil,
                        supplierName: nil,
                        supplierContact: nil,
                        expectedDeliveryDate: nil,
                        notes: nil,
                        createdById: userId
                    )
                    let orderDTO = try await orderRepo.createOrder(createDTO)
                    let orderModel = orderDTO.toModel()
                    draftId = orderModel.id
                    needsLocalInsert = true
                    await MainActor.run {
                        modelContext.insert(orderModel)
                        workingDraftId = draftId
                    }
                }

                let cost = unitCost(forVariantId: suggestion.variantId)
                let itemDTO = CreateCatalogOrderItemDTO(
                    orderId: draftId,
                    catalogVariantId: suggestion.variantId,
                    quantityRequested: suggestion.recommendedQuantity,
                    costPerUnit: cost > 0 ? cost : nil,
                    notes: nil
                )
                let resp = try await orderRepo.addItem(orderId: draftId, dto: itemDTO)
                let itemModel = resp.toModel()

                await MainActor.run {
                    modelContext.insert(itemModel)
                    try? modelContext.save()
                    addedVariantIds.insert(suggestion.variantId)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    _ = needsLocalInsert
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Add failed: \(error.localizedDescription)"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
