//
//  TagsManageSheet.swift
//  OPS
//
//  CRUD for catalog_tags. Tags are free-form labels applied at family
//  level. Sheet presented from the CatalogView kebab.
//

import SwiftUI
import SwiftData

struct TagsManageSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allTags: [CatalogTag]
    @State private var showAddSheet = false
    @State private var editingTag: CatalogTag? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyTags: [CatalogTag] {
        allTags
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                if companyTags.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(companyTags) { tag in
                                TagRow(tag: tag, onEdit: { editingTag = $0 })
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .navigationTitle("TAGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(OPSStyle.Icons.plus)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    }
                    .accessibilityLabel("Add tag")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                TagFormSheet(tag: nil, companyId: companyId)
            }
            .sheet(item: $editingTag) { tag in
                TagFormSheet(tag: tag, companyId: companyId)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// NO TAGS YET")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Tap + to add the first one.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TagRow: View {
    let tag: CatalogTag
    let onEdit: (CatalogTag) -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(tag.name)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Button { onEdit(tag) } label: {
                Image(OPSStyle.Icons.edit)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .accessibilityLabel("Edit \(tag.name)")
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
}

struct TagFormSheet: View {
    let tag: CatalogTag?
    let companyId: String

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var errorMessage: String? = nil

    private var isEditing: Bool { tag != nil }

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
            .navigationTitle(isEditing ? "EDIT TAG" : "NEW TAG")
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
            .confirmationDialog("Delete \(tag?.name ?? "")?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("DELETE", role: .destructive) { Task { await softDelete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This tag will be removed.")
            }
            .onAppear { loadInitial() }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadInitial() {
        guard let tag = tag else { return }
        name = tag.name
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = CatalogRepository(companyId: companyId)
        do {
            if let existing = tag {
                let update = UpdateCatalogTagDTO(name: trimmed)
                let dto = try await repo.updateTag(existing.id, fields: update)
                applyDTOToLocal(dto)
            } else {
                let create = CreateCatalogTagDTO(companyId: companyId, name: trimmed)
                let dto = try await repo.createTag(create)
                applyDTOToLocal(dto)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func softDelete() async {
        guard let tag = tag else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let repo = CatalogRepository(companyId: companyId)
        do {
            try await repo.softDeleteTag(tag.id)
            tag.deletedAt = Date()
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDTOToLocal(_ dto: CatalogTagDTO) {
        let descriptor = FetchDescriptor<CatalogTag>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.name = dto.name
            existing.warningThreshold = dto.warningThreshold
            existing.criticalThreshold = dto.criticalThreshold
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        try? modelContext.save()
    }
}
