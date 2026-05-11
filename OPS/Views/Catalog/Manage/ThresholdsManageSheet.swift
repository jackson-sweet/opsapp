//
//  ThresholdsManageSheet.swift
//  OPS
//
//  Inline-editable list of category-level default warning/critical
//  thresholds. Adding categories is handled by CategoriesManageSheet —
//  this sheet only edits the threshold pair on existing rows.
//

import SwiftUI
import SwiftData

struct ThresholdsManageSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allCategories: [CatalogCategory]
    @State private var editingCategory: CatalogCategory? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyCategories: [CatalogCategory] {
        allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                if companyCategories.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(companyCategories) { cat in
                                ThresholdRow(category: cat, onEdit: { editingCategory = $0 })
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .navigationTitle("THRESHOLDS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .sheet(item: $editingCategory) { cat in
                ThresholdFormSheet(category: cat, companyId: companyId)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// NO CATEGORIES YET")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Add categories first to set thresholds.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ThresholdRow: View {
    let category: CatalogCategory
    let onEdit: (CatalogCategory) -> Void

    private var warningText: String {
        category.defaultWarningThreshold.map { formatNumber($0) } ?? "—"
    }
    private var criticalText: String {
        category.defaultCriticalThreshold.map { formatNumber($0) } ?? "—"
    }

    var body: some View {
        Button { onEdit(category) } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(category.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("WARN")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text(warningText)
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(OPSStyle.Colors.warningText)
                    }
                    HStack(spacing: 4) {
                        Text("CRIT")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text(criticalText)
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(OPSStyle.Colors.errorText)
                    }
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .accessibilityLabel("Edit thresholds for \(category.name)")
    }

    private func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

struct ThresholdFormSheet: View {
    let category: CatalogCategory
    let companyId: String

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var warningText: String = ""
    @State private var criticalText: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        CatalogSectionHeader("DEFAULT THRESHOLDS")
                        Text(category.name)
                            .font(OPSStyle.Typography.section)
                            .foregroundColor(OPSStyle.Colors.primaryText)

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
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("EDIT THRESHOLDS")
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
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear { loadInitial() }
        }
    }

    private func loadInitial() {
        warningText = category.defaultWarningThreshold.map { formatNumber($0) } ?? ""
        criticalText = category.defaultCriticalThreshold.map { formatNumber($0) } ?? ""
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let warning = Double(warningText.trimmingCharacters(in: .whitespacesAndNewlines))
        let critical = Double(criticalText.trimmingCharacters(in: .whitespacesAndNewlines))

        let repo = CatalogRepository(companyId: companyId)
        do {
            let update = UpdateCatalogCategoryDTO(
                name: nil,
                parentId: nil,
                sortOrder: nil,
                colorHex: nil,
                defaultWarningThreshold: warning,
                defaultCriticalThreshold: critical
            )
            let dto = try await repo.updateCategory(category.id, fields: update)
            applyDTOToLocal(dto)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDTOToLocal(_ dto: CatalogCategoryDTO) {
        category.defaultWarningThreshold = dto.defaultWarningThreshold
        category.defaultCriticalThreshold = dto.defaultCriticalThreshold
        category.lastSyncedAt = Date()
        try? modelContext.save()
    }

    private func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
