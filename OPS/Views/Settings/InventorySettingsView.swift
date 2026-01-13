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

    // Import settings
    @State private var showingImportSheet = false

    // Tag settings
    @State private var showingAddTag = false
    @State private var editingTag: InventoryTag? = nil

    @Query private var allUnits: [InventoryUnit]
    @Query private var allTags: [InventoryTag]

    /// Tags for the current company
    private var companyTags: [InventoryTag] {
        allTags
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

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

    /// All tag names from company tags (for display)
    private var existingTagNames: [String] {
        companyTags.map { $0.name }
    }

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

                        // IMPORT SECTION
                        importSection

                        // UNITS SECTION
                        unitsSection

                        // QUICK ADJUST SECTION
                        adjustmentSettingsSection

                        // TAG THRESHOLDS SECTION
                        tagThresholdsSection

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
        .sheet(isPresented: $showingImportSheet) {
            SpreadsheetImportSheet()
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingAddTag) {
            TagEditSheet(
                existingTag: nil,
                onSave: { tagName, warning, critical in
                    createTag(tagName: tagName, warning: warning, critical: critical)
                }
            )
        }
        .sheet(item: $editingTag) { tag in
            TagEditSheet(
                existingTag: tag,
                onSave: { tagName, warning, critical in
                    updateTag(tag, name: tagName, warning: warning, critical: critical)
                }
            )
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

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section header
            Text("IMPORT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Import card
            VStack(spacing: 0) {
                Button(action: { showingImportSheet = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(width: 24)

                        Text("Import from Spreadsheet")
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

                // Info text
                Text("Import inventory items from CSV or Excel files")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing3)
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

    // MARK: - Tag Thresholds Section

    private var tagThresholdsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section header
            HStack {
                Text("TAGS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Button(action: { showingAddTag = true }) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.plus)
                        Text("Add")
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Tags card
            VStack(spacing: 0) {
                if companyTags.isEmpty {
                    // Empty state
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "tag")
                            .font(.system(size: 24))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("No tags configured")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("Create tags to categorize inventory items")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing4)
                } else {
                    // Tag rows
                    ForEach(companyTags) { tag in
                        VStack(spacing: 0) {
                            Button(action: { editingTag = tag }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tag.name)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)

                                        if tag.hasThresholds {
                                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                                if let warning = tag.warningThreshold {
                                                    HStack(spacing: 4) {
                                                        Circle()
                                                            .fill(OPSStyle.Colors.warningStatus)
                                                            .frame(width: 6, height: 6)
                                                        Text("≤\(formatThresholdValue(warning))")
                                                            .font(OPSStyle.Typography.smallCaption)
                                                            .foregroundColor(OPSStyle.Colors.warningStatus)
                                                    }
                                                }
                                                if let critical = tag.criticalThreshold {
                                                    HStack(spacing: 4) {
                                                        Circle()
                                                            .fill(OPSStyle.Colors.errorStatus)
                                                            .frame(width: 6, height: 6)
                                                        Text("≤\(formatThresholdValue(critical))")
                                                            .font(OPSStyle.Typography.smallCaption)
                                                            .foregroundColor(OPSStyle.Colors.errorStatus)
                                                    }
                                                }
                                            }
                                        } else {
                                            Text("No thresholds")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        }
                                    }

                                    Spacer()

                                    Button(action: { deleteTag(tag) }) {
                                        Image(systemName: OPSStyle.Icons.trash)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.errorStatus)
                                    }
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .padding(.vertical, OPSStyle.Layout.spacing3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            if tag.id != companyTags.last?.id {
                                Divider()
                                    .background(OPSStyle.Colors.cardBorder)
                                    .padding(.leading, OPSStyle.Layout.spacing3)
                            }
                        }
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Help text
            Text("Items inherit the stricter threshold when both item and tag thresholds exist")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func formatThresholdValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }

    private func createTag(tagName: String, warning: Double?, critical: Double?) {
        let newId = UUID().uuidString
        let newTag = InventoryTag(
            id: newId,
            name: tagName.trimmingCharacters(in: .whitespaces),
            warningThreshold: warning,
            criticalThreshold: critical,
            companyId: companyId
        )
        newTag.needsSync = true

        modelContext.insert(newTag)

        Task {
            do {
                let dto = InventoryTagDTO(
                    id: newId,
                    name: newTag.name,
                    warningThreshold: warning,
                    criticalThreshold: critical,
                    company: companyId
                )
                let created = try await dataController.apiService.createTag(dto)

                await MainActor.run {
                    newTag.id = created.id
                    newTag.needsSync = false
                    newTag.lastSyncedAt = Date()
                    try? modelContext.save()
                }
            } catch {
                print("[TAG] Failed to create: \(error)")
            }
        }
    }

    private func updateTag(_ tag: InventoryTag, name: String, warning: Double?, critical: Double?) {
        tag.name = name.trimmingCharacters(in: .whitespaces)
        tag.warningThreshold = warning
        tag.criticalThreshold = critical
        tag.needsSync = true

        Task {
            do {
                let updates = InventoryTagDTO.dictionaryFrom(tag)
                try await dataController.apiService.updateTag(id: tag.id, updates: updates)

                await MainActor.run {
                    tag.needsSync = false
                    tag.lastSyncedAt = Date()
                    try? modelContext.save()
                }
            } catch {
                print("[TAG] Failed to update: \(error)")
            }
        }
    }

    private func deleteTag(_ tag: InventoryTag) {
        tag.deletedAt = Date()
        tag.needsSync = true

        Task {
            do {
                try await dataController.apiService.deleteTag(id: tag.id)

                await MainActor.run {
                    tag.needsSync = false
                    try? modelContext.save()
                }
            } catch {
                print("[TAG] Failed to delete: \(error)")
            }
        }
    }

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

// MARK: - Tag Edit Sheet

struct TagEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingTag: InventoryTag?  // nil for new, non-nil for edit
    let onSave: (String, Double?, Double?) -> Void

    @State private var tagName: String = ""
    @State private var warningThresholdText: String = ""
    @State private var criticalThresholdText: String = ""

    private var isEditing: Bool { existingTag != nil }

    private var warningValue: Double? {
        Double(warningThresholdText.trimmingCharacters(in: .whitespaces))
    }

    private var criticalValue: Double? {
        Double(criticalThresholdText.trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool {
        !tagName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                            // TAG NAME
                            tagNameSection

                            // THRESHOLD VALUES (optional)
                            thresholdValuesSection

                            // HELP TEXT
                            helpSection
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                }
            }
            .standardSheetToolbar(
                title: isEditing ? "Edit Tag" : "Add Tag",
                actionText: "Save",
                isActionEnabled: canSave,
                isSaving: false,
                onCancel: { dismiss() },
                onAction: {
                    onSave(tagName, warningValue, criticalValue)
                    dismiss()
                }
            )
        }
        .presentationDetents([.medium])
        .onAppear {
            if let existing = existingTag {
                tagName = existing.name
                if let warning = existing.warningThreshold {
                    warningThresholdText = formatValue(warning)
                }
                if let critical = existing.criticalThreshold {
                    criticalThresholdText = formatValue(critical)
                }
            }
        }
    }

    private var tagNameSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("TAG NAME")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField("e.g. Fasteners, Lumber, Electrical", text: $tagName)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
                .disabled(isEditing)  // Can't change name when editing
                .opacity(isEditing ? 0.6 : 1.0)
        }
    }

    private var thresholdValuesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text("THRESHOLDS (OPTIONAL)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: OPSStyle.Layout.spacing3) {
                // Warning threshold
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Circle()
                            .fill(OPSStyle.Colors.warningStatus)
                            .frame(width: 8, height: 8)
                        Text("Warning Level")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    TextField("e.g. 20", text: $warningThresholdText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                }

                // Critical threshold
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Circle()
                            .fill(OPSStyle.Colors.errorStatus)
                            .frame(width: 8, height: 8)
                        Text("Critical Level")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }

                    TextField("e.g. 5", text: $criticalThresholdText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Items with this tag will show:")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Circle()
                        .fill(OPSStyle.Colors.warningStatus)
                        .frame(width: 6, height: 6)
                    Text("LOW badge when quantity ≤ warning level")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Circle()
                        .fill(OPSStyle.Colors.errorStatus)
                        .frame(width: 6, height: 6)
                    Text("CRITICAL badge when quantity ≤ critical level")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
    }

    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}

#Preview {
    InventorySettingsView()
        .environmentObject(DataController())
}
