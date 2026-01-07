//
//  InventorySettingsView.swift
//  OPS
//
//  Settings view for managing inventory units and adjustment settings
//  Tactical minimalist design
//

import SwiftUI
import SwiftData

struct InventorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    @State private var showingAddUnit = false
    @State private var newUnitName = ""
    @State private var isAdding = false
    @State private var errorMessage: String? = nil

    // Adjustment settings
    @State private var adjustmentValues: [Int] = []
    @State private var newValueInput: String = ""

    // Snapshot settings
    @State private var showingSnapshots = false
    @State private var snapshotFrequency: SnapshotFrequency = .monthly
    @State private var isCreatingSnapshot = false
    @State private var snapshotSuccess = false

    @Query private var allUnits: [InventoryUnit]

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyUnits: [InventoryUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var defaultUnits: [InventoryUnit] {
        companyUnits.filter { $0.isDefault }
    }

    private var customUnits: [InventoryUnit] {
        companyUnits.filter { !$0.isDefault }
    }

    @Query private var allItems: [InventoryItem]

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Inventory",
                    onBackTapped: { dismiss() }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing5) {
                        // SNAPSHOTS SECTION
                        snapshotsSection

                        // UNITS SECTION
                        unitsSection

                        // QUICK ADJUST SECTION
                        adjustmentSettingsSection

                        // Error
                        if let error = errorMessage {
                            Text(error)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                        }

                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.top, OPSStyle.Layout.spacing3)
                }
            }
        }
        .onAppear {
            loadAdjustmentSettings()
            loadSnapshotSettings()
        }
        .sheet(isPresented: $showingSnapshots) {
            SnapshotListView()
                .environmentObject(dataController)
        }
        .alert("Add Unit", isPresented: $showingAddUnit) {
            TextField("Unit name", text: $newUnitName)
            Button("Cancel", role: .cancel) {
                newUnitName = ""
            }
            Button("Add") {
                addUnit()
            }
            .disabled(newUnitName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for the unit (e.g. carton, pallet)")
        }
    }

    // MARK: - Snapshots Section

    private var snapshotsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section header
            Text("SNAPSHOTS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Snapshots card
            VStack(spacing: 0) {
                // View Snapshots row
                Button(action: { showingSnapshots = true }) {
                    HStack {
                        Image(systemName: "folder")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(width: 24)

                        Text("View Snapshots")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        Image(systemName: OPSStyle.Icons.chevronRight)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                Divider()
                    .background(OPSStyle.Colors.cardBorder)
                    .padding(.leading, OPSStyle.Layout.spacing3)

                // Frequency picker row
                HStack {
                    Image(systemName: "clock")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 24)

                    Text("Auto Snapshot")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Picker("", selection: $snapshotFrequency) {
                        ForEach(SnapshotFrequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(OPSStyle.Colors.primaryAccent)
                    .onChange(of: snapshotFrequency) { _, newValue in
                        saveSnapshotSettings()
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

                Divider()
                    .background(OPSStyle.Colors.cardBorder)
                    .padding(.leading, OPSStyle.Layout.spacing3)

                // Last snapshot info
                if let lastDate = SnapshotSettings.load().lastSnapshotDate {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                            .frame(width: 24)

                        Text("Last Snapshot")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        Text(formatDate(lastDate))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)

                    Divider()
                        .background(OPSStyle.Colors.cardBorder)
                        .padding(.leading, OPSStyle.Layout.spacing3)
                }

                // Create snapshot button
                Button(action: { createManualSnapshot() }) {
                    HStack {
                        if isCreatingSnapshot {
                            ProgressView()
                                .tint(OPSStyle.Colors.primaryAccent)
                                .frame(width: 24)
                        } else {
                            Image(systemName: snapshotSuccess ? "checkmark.circle.fill" : "camera")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(snapshotSuccess ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                                .frame(width: 24)
                        }

                        Text(snapshotSuccess ? "Snapshot Created" : "Create Snapshot Now")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(snapshotSuccess ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)

                        Spacer()
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isCreatingSnapshot)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Units Section

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section header
            HStack {
                Text("UNITS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Button(action: { showingAddUnit = true }) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.plus)
                        Text("Add")
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Units card
            VStack(spacing: 0) {
                // Default units
                if !defaultUnits.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Default")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.top, OPSStyle.Layout.spacing2)
                            .padding(.bottom, OPSStyle.Layout.spacing1)

                        ForEach(defaultUnits) { unit in
                            unitRow(unit: unit, canDelete: false)

                            if unit.id != defaultUnits.last?.id {
                                Divider()
                                    .background(OPSStyle.Colors.cardBorder)
                                    .padding(.leading, OPSStyle.Layout.spacing3)
                            }
                        }
                    }
                }

                // Divider between default and custom
                if !defaultUnits.isEmpty && !customUnits.isEmpty {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                }

                // Custom units
                if !customUnits.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Custom")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.top, OPSStyle.Layout.spacing2)
                            .padding(.bottom, OPSStyle.Layout.spacing1)

                        ForEach(customUnits) { unit in
                            unitRow(unit: unit, canDelete: true)

                            if unit.id != customUnits.last?.id {
                                Divider()
                                    .background(OPSStyle.Colors.cardBorder)
                                    .padding(.leading, OPSStyle.Layout.spacing3)
                            }
                        }
                    }
                }

                // Empty state for custom units
                if customUnits.isEmpty {
                    if !defaultUnits.isEmpty {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorder)
                            .frame(height: 1)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                    }

                    Text("No custom units")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                }
            }
            .padding(.bottom, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func unitRow(unit: InventoryUnit, canDelete: Bool) -> some View {
        HStack {
            Text(unit.display)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            if canDelete {
                Button(action: { deleteUnit(unit) }) {
                    Image(systemName: OPSStyle.Icons.trash)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Adjustment Settings Section

    private var adjustmentSettingsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section header
            HStack {
                Text("QUICK ADJUST")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Button(action: resetAdjustmentSettings) {
                    Text("Reset")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Values card
            VStack(spacing: OPSStyle.Layout.spacing4) {
                // Current preset values
                FlowLayout(spacing: OPSStyle.Layout.spacing3) {
                    ForEach(adjustmentValues, id: \.self) { value in
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Text(value > 0 ? "+\(value)" : "\(value)")
                                .font(Font.custom("Mohave-SemiBold", size: 18))
                                .foregroundColor(value > 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)

                            Button(action: { removeValue(value) }) {
                                Image(systemName: OPSStyle.Icons.xmark)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                }

                // Divider
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: 1)

                // Add value input
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("Add Value")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        TextField("e.g. -25 or 25", text: $newValueInput)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .keyboardType(.numbersAndPunctuation)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                            .onSubmit { addValue() }

                        Button(action: { addValue() }) {
                            Image(systemName: OPSStyle.Icons.plus)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                )
                        }
                        .disabled(newValueInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Functions

    private func loadAdjustmentSettings() {
        let settings = AdjustmentSettings.load()
        adjustmentValues = settings.values
    }

    private func addValue() {
        guard let value = Int(newValueInput.trimmingCharacters(in: .whitespaces)),
              value != 0,
              !adjustmentValues.contains(value) else {
            newValueInput = ""
            return
        }

        adjustmentValues.append(value)
        adjustmentValues.sort()
        saveAdjustmentSettings()
        newValueInput = ""
    }

    private func removeValue(_ value: Int) {
        adjustmentValues.removeAll { $0 == value }
        saveAdjustmentSettings()
    }

    private func saveAdjustmentSettings() {
        let settings = AdjustmentSettings(values: adjustmentValues)
        settings.save()
    }

    private func resetAdjustmentSettings() {
        adjustmentValues = AdjustmentSettings.defaultSettings.values
        saveAdjustmentSettings()
    }

    private func addUnit() {
        let trimmedName = newUnitName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isAdding = true
        errorMessage = nil

        let newUnit = InventoryUnit(
            id: UUID().uuidString,
            display: trimmedName,
            companyId: companyId,
            isDefault: false,
            sortOrder: (companyUnits.map { $0.sortOrder }.max() ?? 0) + 1
        )
        newUnit.needsSync = true
        modelContext.insert(newUnit)

        Task {
            do {
                let dto = InventoryUnitDTO(
                    id: newUnit.id,
                    display: trimmedName,
                    company: companyId,
                    isDefault: false,
                    sortOrder: newUnit.sortOrder,
                    createdDate: nil,
                    modifiedDate: nil
                )

                let createdDTO = try await dataController.apiService.createInventoryUnit(dto)

                await MainActor.run {
                    newUnit.id = createdDTO.id
                    newUnit.needsSync = false
                    newUnit.lastSyncedAt = Date()
                    try? modelContext.save()

                    newUnitName = ""
                    isAdding = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create unit: \(error.localizedDescription)"
                    isAdding = false
                }
            }
        }
    }

    private func deleteUnit(_ unit: InventoryUnit) {
        let itemsUsingUnit = allItems.filter { $0.unitId == unit.id && $0.deletedAt == nil }
        if !itemsUsingUnit.isEmpty {
            errorMessage = "Cannot delete '\(unit.display)' - used by \(itemsUsingUnit.count) item(s)"
            return
        }

        unit.deletedAt = Date()
        unit.needsSync = true

        Task {
            do {
                try await dataController.apiService.deleteInventoryUnit(id: unit.id)
                await MainActor.run {
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    unit.deletedAt = nil
                    unit.needsSync = false
                    errorMessage = "Failed to delete: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Snapshot Functions

    private func loadSnapshotSettings() {
        let settings = SnapshotSettings.load()
        snapshotFrequency = settings.frequency
    }

    private func saveSnapshotSettings() {
        var settings = SnapshotSettings.load()
        settings.frequency = snapshotFrequency
        settings.save()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func createManualSnapshot() {
        guard !isCreatingSnapshot else { return }

        isCreatingSnapshot = true
        snapshotSuccess = false
        errorMessage = nil

        // Get current inventory items
        let items = allItems.filter { $0.companyId == companyId && $0.deletedAt == nil }

        Task {
            do {
                _ = try await dataController.apiService.createFullSnapshot(
                    companyId: companyId,
                    userId: dataController.currentUser?.id,
                    isAutomatic: false,
                    items: items
                )

                // Update last snapshot date
                var settings = SnapshotSettings.load()
                settings.lastSnapshotDate = Date()
                settings.save()

                await MainActor.run {
                    isCreatingSnapshot = false
                    snapshotSuccess = true

                    // Reset success state after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        snapshotSuccess = false
                    }

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isCreatingSnapshot = false
                    errorMessage = "Failed to create snapshot: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Snapshot Settings

enum SnapshotFrequency: String, CaseIterable, Codable {
    case off = "off"
    case weekly = "weekly"
    case monthly = "monthly"
    case quarterly = "quarterly"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        }
    }

    var intervalDays: Int? {
        switch self {
        case .off: return nil
        case .weekly: return 7
        case .monthly: return 30
        case .quarterly: return 90
        }
    }
}

struct SnapshotSettings: Codable {
    var frequency: SnapshotFrequency = .monthly
    var lastSnapshotDate: Date?

    private static let key = "inventorySnapshotSettings"

    static func load() -> SnapshotSettings {
        if let data = UserDefaults.standard.data(forKey: key),
           let settings = try? JSONDecoder().decode(SnapshotSettings.self, from: data) {
            return settings
        }
        return SnapshotSettings()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: SnapshotSettings.key)
        }
    }

    /// Check if a snapshot is due based on frequency and last snapshot date
    func isSnapshotDue() -> Bool {
        guard let intervalDays = frequency.intervalDays else { return false }
        guard let lastDate = lastSnapshotDate else { return true }  // Never taken a snapshot

        let daysSinceLastSnapshot = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return daysSinceLastSnapshot >= intervalDays
    }
}

#Preview {
    InventorySettingsView()
        .environmentObject(DataController())
}
