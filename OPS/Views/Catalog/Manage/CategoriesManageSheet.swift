//
//  CategoriesManageSheet.swift
//  OPS
//
//  CRUD for catalog_categories. Supports nested (parent_id) layout up to
//  2 levels. Sheet presented from the CatalogView kebab.
//

import SwiftUI
import SwiftData

struct CategoriesManageSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allCategories: [CatalogCategory]
    @State private var showAddSheet = false
    @State private var editingCategory: CatalogCategory? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyCategories: [CatalogCategory] {
        allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var topLevel: [CatalogCategory] {
        companyCategories.filter { $0.parentId == nil }
    }

    private func children(of category: CatalogCategory) -> [CatalogCategory] {
        companyCategories.filter { $0.parentId == category.id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                if topLevel.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(topLevel) { parent in
                                CategoryRow(category: parent, depth: 0, onEdit: { editingCategory = $0 })
                                ForEach(children(of: parent)) { child in
                                    CategoryRow(category: child, depth: 1, onEdit: { editingCategory = $0 })
                                }
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .navigationTitle("CATEGORIES")
            .navigationBarTitleDisplayMode(.inline)
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
                    .accessibilityLabel("Add category")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                CategoryFormSheet(
                    category: nil,
                    companyId: companyId,
                    parentChoices: topLevel
                )
            }
            .sheet(item: $editingCategory) { cat in
                CategoryFormSheet(
                    category: cat,
                    companyId: companyId,
                    parentChoices: topLevel.filter { $0.id != cat.id }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// NO CATEGORIES YET")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Tap + to add the first one.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CategoryRow: View {
    let category: CatalogCategory
    let depth: Int
    let onEdit: (CatalogCategory) -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if depth > 0 {
                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(width: OPSStyle.Layout.spacing3, height: 1)
            }
            Text(depth == 0 ? "// \(category.name.uppercased())" : category.name)
                .font(depth == 0 ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Button { onEdit(category) } label: {
                Image(systemName: "pencil")
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .accessibilityLabel("Edit \(category.name)")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3 * Double(depth + 1))
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

// MARK: - Category Form

struct CategoryFormSheet: View {
    let category: CatalogCategory?
    let companyId: String
    let parentChoices: [CatalogCategory]

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var parentId: String? = nil
    @State private var sortOrder: Int = 0
    @State private var warningText: String = ""
    @State private var criticalText: String = ""
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var errorMessage: String? = nil

    private var isEditing: Bool { category != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        CatalogSectionHeader("DETAILS")
                        CatalogFieldLabel("Name")
                        TextField("", text: $name)
                            .textFieldStyle(CatalogTextFieldStyle())

                        CatalogFieldLabel("Parent category")
                        Picker("Parent", selection: $parentId) {
                            Text("None").tag(String?.none)
                            ForEach(parentChoices) { c in
                                Text(c.name).tag(Optional(c.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )

                        CatalogFieldLabel("Sort order")
                        Stepper(value: $sortOrder, in: 0...999) {
                            Text("\(sortOrder)")
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }

                        CatalogSectionHeader("DEFAULT THRESHOLDS")
                        CatalogFieldLabel("Warning")
                        TextField("", text: $warningText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(CatalogTextFieldStyle())

                        CatalogFieldLabel("Critical")
                        TextField("", text: $criticalText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(CatalogTextFieldStyle())

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
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
                                    .background(OPSStyle.Colors.cardBackgroundDark)
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
            .navigationTitle(isEditing ? "EDIT CATEGORY" : "NEW CATEGORY")
            .navigationBarTitleDisplayMode(.inline)
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
            .confirmationDialog("Delete \(category?.name ?? "")?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("DELETE", role: .destructive) { Task { await softDelete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This category will be removed.")
            }
            .onAppear { loadInitial() }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    private func loadInitial() {
        guard let category = category else { return }
        name = category.name
        parentId = category.parentId
        sortOrder = category.sortOrder
        warningText = category.defaultWarningThreshold.map { String($0) } ?? ""
        criticalText = category.defaultCriticalThreshold.map { String($0) } ?? ""
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let warning = Double(warningText.trimmingCharacters(in: .whitespacesAndNewlines))
        let critical = Double(criticalText.trimmingCharacters(in: .whitespacesAndNewlines))
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let repo = CatalogRepository(companyId: companyId)
        do {
            if let existing = category {
                let update = UpdateCatalogCategoryDTO(
                    name: trimmedName,
                    parentId: parentId,
                    sortOrder: sortOrder,
                    colorHex: existing.colorHex,
                    defaultWarningThreshold: warning,
                    defaultCriticalThreshold: critical
                )
                let dto = try await repo.updateCategory(existing.id, fields: update)
                applyDTOToLocal(dto)
            } else {
                let create = CreateCatalogCategoryDTO(
                    companyId: companyId,
                    name: trimmedName,
                    parentId: parentId,
                    sortOrder: sortOrder,
                    colorHex: nil,
                    defaultWarningThreshold: warning,
                    defaultCriticalThreshold: critical
                )
                let dto = try await repo.createCategory(create)
                applyDTOToLocal(dto)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func softDelete() async {
        guard let category = category else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let repo = CatalogRepository(companyId: companyId)
        do {
            try await repo.softDeleteCategory(category.id)
            category.deletedAt = Date()
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDTOToLocal(_ dto: CatalogCategoryDTO) {
        // Mirror the new state into SwiftData so the list refreshes immediately.
        let descriptor = FetchDescriptor<CatalogCategory>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.name = dto.name
            existing.parentId = dto.parentId
            existing.sortOrder = dto.sortOrder
            existing.colorHex = dto.colorHex
            existing.defaultWarningThreshold = dto.defaultWarningThreshold
            existing.defaultCriticalThreshold = dto.defaultCriticalThreshold
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        try? modelContext.save()
    }
}

