//
//  AddFamilySheet.swift
//  OPS
//
//  Create-new-family form. The family is the variant container — by
//  itself it tracks no stock, so the "Create as single-variant family"
//  toggle (default on) tacks on a placeholder variant with quantity 0
//  so the user can immediately track stock without first authoring
//  options.
//

import SwiftUI
import SwiftData

struct AddFamilySheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]
    @Query private var allTags: [CatalogTag]

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedCategoryId: String? = nil
    @State private var selectedUnitId: String? = nil
    @State private var selectedTagIds: Set<String> = []
    @State private var warningText: String = ""
    @State private var criticalText: String = ""
    @State private var createSingleVariant: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyCategories: [CatalogCategory] {
        allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private var companyTags: [CatalogTag] {
        allTags
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        detailsSection
                        if !companyTags.isEmpty {
                            tagsSection
                        }
                        thresholdsSection
                        variantSection
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("NEW FAMILY")
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
                            .foregroundColor(canSave
                                             ? OPSStyle.Colors.primaryAccent
                                             : OPSStyle.Colors.tertiaryText)
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("DETAILS")
            CatalogFieldLabel("Name")
            TextField("", text: $name)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Description")
            TextField("", text: $description)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Category")
            Picker("Category", selection: $selectedCategoryId) {
                Text("None").tag(String?.none)
                ForEach(companyCategories) { category in
                    Text(category.name).tag(Optional(category.id))
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

            CatalogFieldLabel("Default unit")
            Picker("Unit", selection: $selectedUnitId) {
                Text("None").tag(String?.none)
                ForEach(companyUnits) { unit in
                    Text(unit.display).tag(Optional(unit.id))
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
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("TAGS")
            ForEach(companyTags) { tag in
                Button {
                    if selectedTagIds.contains(tag.id) {
                        selectedTagIds.remove(tag.id)
                    } else {
                        selectedTagIds.insert(tag.id)
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: selectedTagIds.contains(tag.id) ? "checkmark.square.fill" : "square")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(selectedTagIds.contains(tag.id)
                                             ? OPSStyle.Colors.primaryAccent
                                             : OPSStyle.Colors.tertiaryText)
                        Text(tag.name.uppercased())
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                    }
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var thresholdsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("DEFAULT THRESHOLDS")
            Text("These apply to every variant unless the variant overrides them.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            CatalogFieldLabel("Warning")
            TextField("", text: $warningText)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Critical")
            TextField("", text: $criticalText)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())
        }
    }

    @ViewBuilder
    private var variantSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("INITIAL VARIANT")
            Toggle(isOn: $createSingleVariant) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create as single-variant family")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("Adds a placeholder variant with quantity 0 so you can start tracking stock immediately. Turn off if you'll author options first.")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .tint(OPSStyle.Colors.primaryAccent)
        }
    }

    // MARK: - Persistence

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedWarning = Double(warningText.trimmingCharacters(in: .whitespacesAndNewlines))
        let parsedCritical = Double(criticalText.trimmingCharacters(in: .whitespacesAndNewlines))

        let repo = CatalogRepository(companyId: companyId)
        do {
            let create = CreateCatalogItemDTO(
                companyId: companyId,
                categoryId: selectedCategoryId,
                name: trimmedName,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                defaultPrice: nil,
                defaultUnitCost: nil,
                defaultWarningThreshold: parsedWarning,
                defaultCriticalThreshold: parsedCritical,
                defaultUnitId: selectedUnitId
            )
            let familyDto = try await repo.createFamily(create)
            applyFamilyDTO(familyDto)

            if !selectedTagIds.isEmpty {
                let itemTags = try await repo.replaceFamilyTags(
                    catalogItemId: familyDto.id,
                    tagIds: selectedTagIds
                )
                applyFamilyTagDTOs(itemTags)
            }

            if createSingleVariant {
                // Single-variant family: add a placeholder variant with no
                // option-value joins, quantity 0. The user can adjust on
                // the detail screen immediately.
                let createVariant = CreateCatalogVariantDTO(
                    companyId: companyId,
                    catalogItemId: familyDto.id,
                    sku: nil,
                    quantity: 0,
                    priceOverride: nil,
                    unitCostOverride: nil,
                    warningThreshold: nil,
                    criticalThreshold: nil,
                    unitId: selectedUnitId
                )
                let variantDto = try await repo.createVariant(createVariant)
                applyVariantDTO(variantDto)
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyFamilyDTO(_ dto: CatalogItemDTO) {
        let descriptor = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.name = dto.name
            existing.itemDescription = dto.description
            existing.categoryId = dto.categoryId
            existing.defaultPrice = dto.defaultPrice
            existing.defaultUnitCost = dto.defaultUnitCost
            existing.defaultWarningThreshold = dto.defaultWarningThreshold
            existing.defaultCriticalThreshold = dto.defaultCriticalThreshold
            existing.defaultUnitId = dto.defaultUnitId
            existing.imageUrl = dto.imageUrl
            existing.notes = dto.notes
            existing.isActive = dto.isActive
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    private func applyFamilyTagDTOs(_ dtos: [CatalogItemTagDTO]) {
        for dto in dtos {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        try? modelContext.save()
    }

    private func applyVariantDTO(_ dto: CatalogVariantDTO) {
        let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.sku = dto.sku
            existing.quantity = dto.quantity
            existing.priceOverride = dto.priceOverride
            existing.unitCostOverride = dto.unitCostOverride
            existing.warningThreshold = dto.warningThreshold
            existing.criticalThreshold = dto.criticalThreshold
            existing.unitId = dto.unitId
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        try? modelContext.save()
    }
}
