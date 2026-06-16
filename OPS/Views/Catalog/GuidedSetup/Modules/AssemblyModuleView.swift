//
//  AssemblyModuleView.swift
//  OPS
//
//  The assembly builder: one fixed all-in price, then what's in it — materials
//  and labor added inline (created on save), with a live margin. Saves a
//  kind=package product with product_materials (materials) + a service child
//  per labor line. Build as many packages as you like.
//

import SwiftUI
import SwiftData

struct AssemblyModuleView: View {
    @ObservedObject var model: GuidedCatalogSetupModel
    let isOnline: Bool

    @Environment(\.modelContext) private var modelContext
    @Query private var allTaskTypes: [TaskType]
    @Query private var allUnits: [CatalogUnit]

    @State private var draft = AssemblyDraft()
    @State private var showingMaterialSheet = false
    @State private var showingLaborSheet = false
    @State private var showingTaskTypePicker = false
    @State private var showingUnitCreate = false
    @FocusState private var nameFocused: Bool

    private var companyTaskTypes: [TaskType] {
        allTaskTypes
            .filter { $0.companyId == model.companyId && $0.deletedAt == nil }
            .sorted { ($0.displayOrder, $0.display) < ($1.displayOrder, $1.display) }
    }

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == model.companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private var trackCost: Bool { model.profile?.trackCost ?? true }
    /// Cost + margin are meaningful only when tracking cost AND the package has contents.
    private var showMarginCard: Bool { trackCost && !isEmptyContents }

    private var selectedTaskType: TaskType? {
        guard let id = draft.taskTypeId else { return nil }
        return companyTaskTypes.first { $0.id == id }
    }

    private var priceAmount: Double? { model.parseMoney(draft.priceText) }
    private var totalCost: Double { model.assemblyCost(materials: draft.materials, labor: draft.labor) }
    private var marginPercent: Double? {
        model.assemblyMarginPercent(priceText: draft.priceText, materials: draft.materials, labor: draft.labor)
    }
    private var isEmptyContents: Bool { draft.materials.isEmpty && draft.labor.isEmpty }

    private var canSave: Bool {
        guard isOnline, !model.isSaving else { return false }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard priceAmount != nil else { return false }
        guard !model.isDuplicateAssemblyName(draft.name) else { return false }
        return true
    }

    private var disabledReason: String? {
        if model.isSaving { return nil }
        if !isOnline { return "// OFFLINE — SAVES PAUSED" }
        if model.isDuplicateAssemblyName(draft.name) { return "// NAME ALREADY USED" }
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || priceAmount == nil {
            return "// NAME AND PRICE REQUIRED"
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header
                identityCard
                priceCard
                contentsCard
                if showMarginCard { marginCard }
                saveButton
                reasonOrError
                if !model.savedAssemblies.isEmpty { savedListCard }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingMaterialSheet) {
            AddAssemblyMaterialSheet(companyId: model.companyId,
                                     trackCost: trackCost) { draft.materials.append($0) }
        }
        .sheet(isPresented: $showingLaborSheet) {
            AddAssemblyLaborSheet(companyId: model.companyId,
                                  trackCost: trackCost) { draft.labor.append($0) }
        }
        .sheet(isPresented: $showingTaskTypePicker) {
            TaskTypePickerSheet(selectedTaskTypeId: draft.taskTypeId, onSelect: { draft.taskTypeId = $0.id })
        }
        .sheet(isPresented: $showingUnitCreate) {
            InlineCreateUnitSheet(companyId: model.companyId) { draft.priceUnitId = $0 }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { nameFocused = true }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// JOB PACKAGES")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("PACKAGE YOUR JOBS")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("One price, everything in it — materials and labor. Build as many as you like.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PACKAGE")
            CatalogFieldLabel("Name")
            TextField("e.g. Rail install", text: $draft.name)
                .textFieldStyle(CatalogTextFieldStyle())
                .focused($nameFocused)

            CatalogFieldLabel("Task type")
            Button {
                showingTaskTypePicker = true
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if let hex = selectedTaskType?.color {
                        Circle().fill(Color(hex: hex) ?? OPSStyle.Colors.primaryAccent).frame(width: 14, height: 14)
                    }
                    Text(selectedTaskType?.display ?? "Link a task type (optional)")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(selectedTaskType == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(OPSStyle.Layout.spacing2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("ALL-IN PRICE")
            CatalogFieldLabel("What the customer pays")
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text("$")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                TextField("0", text: $draft.priceText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.decimalPad)
            }
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )

            CatalogFieldLabel("Unit")
            UnitPickerField(
                selectedUnitId: $draft.priceUnitId,
                companyUnits: companyUnits,
                canCreateNew: true,
                onCreateRequested: { showingUnitCreate = true },
                allowFlatRate: true
            )
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var contentsCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("WHAT'S IN IT")

            if isEmptyContents {
                Text("Add the materials and labor this job uses. They drive your cost and margin.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(draft.materials) { material in
                contentsRow(
                    name: material.name.isEmpty ? "Material" : material.name,
                    detail: "MATERIAL",
                    amount: (model.parseMoney(material.costText) ?? 0) * (model.parseMoney(material.qtyText) ?? 0)
                ) { draft.materials.removeAll { $0.id == material.id } }
            }
            ForEach(draft.labor) { labor in
                contentsRow(
                    name: labor.name.isEmpty ? "Labor" : labor.name,
                    detail: "LABOR",
                    amount: (model.parseMoney(labor.costText) ?? 0) * (model.parseMoney(labor.hoursText) ?? 0)
                ) { draft.labor.removeAll { $0.id == labor.id } }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                addButton(label: "ADD MATERIAL", icon: "plus") { showingMaterialSheet = true }
                addButton(label: "ADD LABOR", icon: "plus") { showingLaborSheet = true }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func contentsRow(name: String, detail: String, amount: Double, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text("\(detail) · \(model.formatMoney(amount)) cost")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .bold))
            }
            .opsIconButtonStyle(size: OPSStyle.Layout.touchTargetMin)
            .accessibilityLabel("Remove \(name)")
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func addButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                Text(label)
                    .font(OPSStyle.Typography.buttonLabel)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var marginCard: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// YOUR COST")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(model.formatMoney(totalCost))
                    .font(OPSStyle.Typography.dataValue)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing1) {
                Text("// MARGIN")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(marginPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(OPSStyle.Typography.dataValue)
                    .monospacedDigit()
                    .foregroundColor((marginPercent ?? 0) >= 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.errorText)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            if model.isSaving {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.tertiaryText))
                        .scaleEffect(0.75)
                    Text("SAVING")
                }
            } else {
                Text("SAVE PACKAGE")
            }
        }
        .opsPrimaryButtonStyle(isDisabled: !canSave)
        .disabled(!canSave)
        .accessibilityLabel("Save package")
    }

    @ViewBuilder
    private var reasonOrError: some View {
        if let reason = disabledReason {
            Text(reason)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = model.errorMessage {
            Text(error)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.errorText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var savedListCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                CatalogSectionHeader("PACKAGES BUILT")
                Spacer()
                Text("\(model.savedAssemblies.count)")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            ForEach(model.savedAssemblies) { assembly in
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(assembly.name)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                        Text(assembly.marginPercent.map { "\(Int($0.rounded()))% margin" } ?? "—")
                            .font(OPSStyle.Typography.metadata)
                            .monospacedDigit()
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    Spacer()
                    Text(model.formatMoney(assembly.sell))
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    @MainActor
    private func save() async {
        await model.saveAssembly(draft, units: companyUnits, modelContext: modelContext)
        if model.errorMessage == nil {
            draft = AssemblyDraft()
            nameFocused = true
        }
    }
}
