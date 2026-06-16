//
//  UnitsManageSheet.swift
//  OPS
//
//  CRUD for catalog_units (units of measure for catalog variants).
//  Sheet presented from the CatalogView kebab.
//

import SwiftUI
import SwiftData

private let CATALOG_UNIT_DIMENSIONS: [(value: String, label: String)] = [
    ("count",  "Count"),
    ("length", "Length"),
    ("area",   "Area"),
    ("volume", "Volume"),
    ("mass",   "Mass"),
    ("time",   "Time"),
]

struct UnitsManageSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allUnits: [CatalogUnit]
    @State private var showAddSheet = false
    @State private var editingUnit: CatalogUnit? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                if companyUnits.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(companyUnits) { unit in
                                UnitRow(unit: unit, onEdit: { editingUnit = $0 })
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .catalogNavigationTitle("UNITS")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    }
                    .accessibilityLabel("Add unit")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                UnitFormSheet(unit: nil, companyId: companyId)
            }
            .sheet(item: $editingUnit) { unit in
                UnitFormSheet(unit: unit, companyId: companyId)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// NO UNITS YET")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Tap + to add the first one.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct UnitRow: View {
    let unit: CatalogUnit
    let onEdit: (CatalogUnit) -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.display)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(unit.dimension.uppercased())
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            if let abbrev = unit.abbreviation, !abbrev.isEmpty {
                Text(abbrev)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Button { onEdit(unit) } label: {
                Image(systemName: "pencil")
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .accessibilityLabel("Edit \(unit.display)")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .glassSurface()
    }
}

struct UnitFormSheet: View {
    let unit: CatalogUnit?
    let companyId: String

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var display: String = ""
    @State private var abbreviation: String = ""
    @State private var dimension: String = "count"
    @State private var sortOrder: Int = 0
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var errorMessage: String? = nil

    private var isEditing: Bool { unit != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        CatalogSectionHeader("DETAILS")
                        CatalogFieldLabel("Name")
                        TextField("", text: $display)
                            .textFieldStyle(CatalogTextFieldStyle())

                        CatalogFieldLabel("Abbreviation")
                        TextField("", text: $abbreviation)
                            .textFieldStyle(CatalogTextFieldStyle())

                        CatalogFieldLabel("Dimension")
                        Picker("Dimension", selection: $dimension) {
                            ForEach(CATALOG_UNIT_DIMENSIONS, id: \.value) { entry in
                                Text(entry.label).tag(entry.value)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )

                        CatalogFieldLabel("Sort order")
                        Stepper(value: $sortOrder, in: 0...999) {
                            Text("\(sortOrder)")
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }

                        if isEditing {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Text("DELETE")
                                    .font(OPSStyle.Typography.buttonLabel)
                                    .foregroundColor(OPSStyle.Colors.errorText)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: OPSStyle.Layout.touchTargetMin)
                                    .background(OPSStyle.Colors.surfaceInput)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
                                    )
                            }
                            .padding(.top, OPSStyle.Layout.spacing3)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .catalogNavigationTitle(isEditing ? "EDIT UNIT" : "NEW UNIT")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text("SAVE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .confirmationDialog("Delete \(unit?.display ?? "")?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("DELETE", role: .destructive) { Task { await softDelete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This unit will be removed.")
            }
            .onAppear { loadInitial() }
            .errorToast($errorMessage, label: Feedback.Err.operationFailed)
        }
    }

    private var canSave: Bool {
        !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadInitial() {
        guard let unit = unit else { return }
        display = unit.display
        abbreviation = unit.abbreviation ?? ""
        dimension = unit.dimension
        sortOrder = unit.sortOrder
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedDisplay = display.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbrev = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbrev = trimmedAbbrev.isEmpty ? nil : trimmedAbbrev

        let repo = CatalogRepository(companyId: companyId)
        do {
            if let existing = unit {
                let update = UpdateCatalogUnitDTO(
                    display: trimmedDisplay,
                    abbreviation: abbrev,
                    dimension: dimension,
                    isDefault: existing.isDefault,
                    sortOrder: sortOrder
                )
                let dto = try await repo.updateUnit(existing.id, fields: update)
                applyDTOToLocal(dto)
            } else {
                let create = CreateCatalogUnitDTO(
                    companyId: companyId,
                    display: trimmedDisplay,
                    abbreviation: abbrev,
                    dimension: dimension,
                    isDefault: false,
                    sortOrder: sortOrder
                )
                let dto = try await repo.createUnit(create)
                applyDTOToLocal(dto)
            }
            ToastCenter.shared.present(Feedback.Catalog.unitSaved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func softDelete() async {
        guard let unit = unit else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let repo = CatalogRepository(companyId: companyId)
        do {
            try await repo.softDeleteUnit(unit.id)
            unit.deletedAt = Date()
            try? modelContext.save()
            ToastCenter.shared.present(Feedback.Catalog.unitRemoved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDTOToLocal(_ dto: CatalogUnitDTO) {
        let descriptor = FetchDescriptor<CatalogUnit>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.display = dto.display
            existing.abbreviation = dto.abbreviation
            existing.dimension = dto.dimension
            existing.isDefault = dto.isDefault
            existing.sortOrder = dto.sortOrder
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        try? modelContext.save()
    }
}
