//
//  QuantityAdjustmentSheet.swift
//  OPS
//
//  Quick quantity adjustment sheet for inventory items
//  Tactical minimalist design
//

import SwiftUI
import SwiftData

struct QuantityAdjustmentSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: InventoryItem

    // State
    @State private var currentQuantity: Double
    @State private var isEditingQuantity: Bool = false
    @State private var quantityText: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingEditSheet: Bool = false

    // Focus
    @FocusState private var isQuantityFocused: Bool

    // Query for units
    @Query private var allUnits: [InventoryUnit]

    // Settings
    private var adjustmentSettings: AdjustmentSettings {
        AdjustmentSettings.load()
    }

    private var adjustmentValues: [Int] {
        adjustmentSettings.values
    }

    private var unitDisplay: String {
        if let unitId = item.unitId,
           let unit = allUnits.first(where: { $0.id == unitId }) {
            return unit.display
        }
        return ""
    }

    private var hasChanges: Bool {
        currentQuantity != item.quantity
    }

    init(item: InventoryItem) {
        self.item = item
        _currentQuantity = State(initialValue: item.quantity)
        _quantityText = State(initialValue: Self.formatQuantity(item.quantity))
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Main content
                    HStack(alignment: .center) {
                        // LEFT: Quantity with brackets
                        quantityDisplay
                            .frame(maxWidth: .infinity)

                        // RIGHT: Item info
                        itemInfo
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing4)

                    // Change indicator
                    if hasChanges {
                        changeIndicator
                            .padding(.top, OPSStyle.Layout.spacing2)
                    }

                    // Divider
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.top, OPSStyle.Layout.spacing4)

                    // Quick adjust buttons
                    adjustmentButtonsSection
                        .padding(.top, OPSStyle.Layout.spacing3)

                    // Error
                    if let error = errorMessage {
                        Text(error)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .padding(.top, OPSStyle.Layout.spacing2)
                    }

                    Spacer()

                    // Edit item button
                    Button(action: {
                        showingEditSheet = true
                    }) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: OPSStyle.Icons.pencil)
                            Text("Edit Item")
                        }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .padding(.bottom, OPSStyle.Layout.spacing3)
                }
            }
            .standardSheetToolbar(
                title: "Adjust Quantity",
                actionText: "Save",
                isActionEnabled: hasChanges,
                isSaving: isSaving,
                onCancel: { dismiss() },
                onAction: { saveChanges() }
            )
        }
        .presentationDetents([.medium])
        .sheet(isPresented: $showingEditSheet) {
            InventoryFormSheet(item: item)
                .environmentObject(dataController)
        }
    }

    // MARK: - Quantity Display

    private let quantityFont = Font.custom("Mohave-Bold", size: 56)

    private var quantityDisplay: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            if isEditingQuantity {
                // Edit mode
                TextField("0", text: $quantityText)
                    .font(quantityFont)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($isQuantityFocused)
                    .fixedSize(horizontal: true, vertical: false)
                    .onChange(of: quantityText) { _, newValue in
                        if let value = Double(newValue) {
                            currentQuantity = max(0, value)
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(action: {
                                finishEditing()
                            }) {
                                Text("Enter")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                    }

                if !unitDisplay.isEmpty {
                    Text(unitDisplay)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            } else {
                // Display mode
                Button(action: {
                    quantityText = Self.formatQuantity(currentQuantity)
                    isEditingQuantity = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isQuantityFocused = true
                    }
                }) {
                    VStack(spacing: OPSStyle.Layout.spacing1) {
                        Text(Self.formatQuantity(currentQuantity))
                            .font(quantityFont)
                            .foregroundColor(quantityColor)

                        if !unitDisplay.isEmpty {
                            Text(unitDisplay)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func finishEditing() {
        isEditingQuantity = false
        isQuantityFocused = false
    }

    // MARK: - Item Info

    private var itemInfo: some View {
        VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing2) {
            Text(item.name)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)

            if let sku = item.sku, !sku.isEmpty {
                Text(sku)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
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
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Change Indicator

    private var changeIndicator: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(Self.formatQuantity(item.quantity))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Image(systemName: OPSStyle.Icons.chevronRight)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text(Self.formatQuantity(currentQuantity))
                .foregroundColor(changeColor)
        }
        .font(OPSStyle.Typography.caption)
    }

    // MARK: - Adjustment Buttons

    private var adjustmentButtonsSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(adjustmentValues, id: \.self) { value in
                        adjustmentPill(value: value)
                            .id(value)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
            .onAppear {
                // Scroll to center (find middle value, preferring small positive like +1)
                let centerIndex = adjustmentValues.count / 2
                if centerIndex < adjustmentValues.count {
                    let centerValue = adjustmentValues[centerIndex]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(centerValue, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func adjustmentPill(value: Int) -> some View {
        let isPositive = value > 0
        let color = isPositive ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus

        return Button(action: {
            adjustQuantity(by: Double(value))
        }) {
            Text(isPositive ? "+\(value)" : "\(value)")
                .font(Font.custom("Mohave-SemiBold", size: 22))
                .foregroundColor(color)
                .frame(minWidth: 72)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(color.opacity(0.15))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(color, lineWidth: 1.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Computed Properties

    private var quantityColor: Color {
        if currentQuantity <= 0 {
            return OPSStyle.Colors.errorStatus
        } else if currentQuantity < 10 {
            return OPSStyle.Colors.warningStatus
        } else {
            return OPSStyle.Colors.primaryText
        }
    }

    private var changeColor: Color {
        if currentQuantity > item.quantity {
            return OPSStyle.Colors.successStatus
        } else if currentQuantity < item.quantity {
            return OPSStyle.Colors.errorStatus
        } else {
            return OPSStyle.Colors.primaryText
        }
    }

    // MARK: - Functions

    private static func formatQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }

    private func adjustQuantity(by amount: Double) {
        let newValue = max(0, currentQuantity + amount)
        currentQuantity = newValue
        quantityText = Self.formatQuantity(newValue)

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func saveChanges() {
        guard hasChanges else { return }

        isSaving = true
        errorMessage = nil

        item.quantity = currentQuantity
        item.needsSync = true

        Task {
            do {
                let updates: [String: Any] = [
                    BubbleFields.InventoryItem.quantity: currentQuantity
                ]

                try await dataController.apiService.updateInventoryItem(id: item.id, updates: updates)

                await MainActor.run {
                    item.needsSync = false
                    item.lastSyncedAt = Date()
                    try? modelContext.save()

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Adjustment Settings

struct AdjustmentSettings: Codable {
    var values: [Int]

    static let defaultSettings = AdjustmentSettings(
        values: [-100, -50, -10, -1, 1, 10, 50, 100]
    )

    static func load() -> AdjustmentSettings {
        if let data = UserDefaults.standard.data(forKey: "inventoryAdjustmentSettings"),
           let settings = try? JSONDecoder().decode(AdjustmentSettings.self, from: data) {
            return settings
        }
        return defaultSettings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "inventoryAdjustmentSettings")
        }
    }
}

#Preview {
    QuantityAdjustmentSheet(
        item: InventoryItem(
            id: "preview",
            name: "2x4 Lumber 8ft",
            quantity: 50,
            companyId: "company",
            unitId: nil,
            itemDescription: "Standard framing lumber",
            tagsString: "lumber,framing,exterior",
            sku: "LBR-2X4-8",
            notes: nil,
            imageUrl: nil
        )
    )
    .environmentObject(DataController())
}
