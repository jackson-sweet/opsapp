//
//  AddAssemblyMaterialSheet.swift
//  OPS
//
//  Add one material line to an assembly. Two provenances:
//    • Pick existing — choose a stock item → variant; the line references
//      that `CatalogVariant`, so commit reuses it and never duplicates stock.
//    • Create new — type a name + your cost; commit scaffolds a family +
//      variant.
//  Either path sets a quantity-per-job. Returns a draft to the assembly
//  builder; persistence happens on assembly commit (see saveAssembly).
//

import SwiftUI
import SwiftData

struct AddAssemblyMaterialSheet: View {
    let companyId: String
    let trackCost: Bool
    let onAdd: (AssemblyMaterialDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allUnits: [CatalogUnit]
    @Query private var allFamilies: [CatalogItem]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]

    private enum Mode: String, CaseIterable, Identifiable {
        case existing, new
        var id: String { rawValue }
    }

    @State private var mode: Mode = .existing
    @State private var qtyText: String = ""

    // Create-new authoring
    @State private var name: String = ""
    @State private var costText: String = ""
    @State private var unitId: String?
    @State private var showingUnitCreate = false
    @FocusState private var nameFocused: Bool

    // Create-new variant axes (Color → black/white, ± Thickness → the matrix)
    @State private var variantsExpanded = false
    @State private var axes: [AssemblyMaterialAxis] = []

    // Pick-existing selection
    @State private var selectedFamilyId: String?
    @State private var selectedVariantId: String?

    // MARK: - Filtered company data

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private var companyFamilies: [CatalogItem] {
        allFamilies
            .filter { $0.companyId == companyId && $0.deletedAt == nil && $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func variants(for familyId: String) -> [CatalogVariant] {
        allVariants
            .filter { $0.companyId == companyId && $0.catalogItemId == familyId
                && $0.deletedAt == nil && $0.isActive }
            .sorted { ($0.sku ?? $0.id).localizedCaseInsensitiveCompare($1.sku ?? $1.id) == .orderedAscending }
    }

    private var variantsForSelectedFamily: [CatalogVariant] {
        guard let familyId = selectedFamilyId else { return [] }
        return variants(for: familyId)
    }

    private var selectedFamily: CatalogItem? {
        guard let id = selectedFamilyId else { return nil }
        return companyFamilies.first { $0.id == id }
    }

    private var selectedVariant: CatalogVariant? {
        guard let id = selectedVariantId else { return nil }
        return allVariants.first { $0.id == id }
    }

    /// Labels existing variants by their option values ("Top rail · Black"), not
    /// the raw SKU — the fix the cold-start audit asked for. Shared with stock + the
    /// product recipe picker via CatalogVariantLabeler.
    private func variantLabel(_ variant: CatalogVariant) -> String {
        CatalogVariantLabeler.label(for: variant, families: allFamilies,
                                    options: allOptions, optionValues: allOptionValues,
                                    variantOptionValues: allVariantOptionValues)
    }

    // Local mirror of the draft's pure matrix helpers, over the in-progress `axes`.
    private var cleanAxesLocal: [AssemblyMaterialAxis] { AssemblyMaterialDraft(axes: axes).cleanAxes }
    private var localComboCount: Int { AssemblyMaterialDraft(axes: axes).variantComboCount }

    private func isNumber(_ raw: String) -> Bool {
        let cleaned = raw.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) != nil
    }

    private var canAdd: Bool {
        switch mode {
        case .new:
            // Cost is optional (and hidden when not tracking cost); qty is required.
            let costOK = costText.trimmingCharacters(in: .whitespaces).isEmpty || isNumber(costText)
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && isNumber(qtyText) && costOK
                && localComboCount <= AssemblyMaterialDraft.maxVariants
        case .existing:
            return selectedVariantId != nil && isNumber(qtyText)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("// MATERIAL")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("ADD A MATERIAL")
                            .font(OPSStyle.Typography.pageTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    modeToggle

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        if mode == .existing {
                            existingFields
                        } else {
                            newFields
                        }

                        CatalogFieldLabel("Qty per job")
                        TextField("1", text: $qtyText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(CatalogTextFieldStyle())
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nestedCard()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            OPSFloatingButtonBar {
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    Button { dismiss() } label: { Text("CANCEL") }
                        .opsSecondaryButtonStyle()
                    Button {
                        if let draft = buildDraft() { onAdd(draft) }
                        dismiss()
                    } label: { Text("ADD") }
                        .opsPrimaryButtonStyle(isDisabled: !canAdd)
                        .disabled(!canAdd)
                }
            }
        }
        .sheet(isPresented: $showingUnitCreate) {
            InlineCreateUnitSheet(companyId: companyId) { unitId = $0 }
        }
        .onAppear {
            // Default into create-new only when there's no stock to reference.
            if companyFamilies.isEmpty {
                mode = .new
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { nameFocused = true }
            }
        }
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            segmentButton("Pick existing", isOn: mode == .existing) { mode = .existing }
            segmentButton("Create new", isOn: mode == .new) {
                mode = .new
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true }
            }
        }
        .padding(OPSStyle.Layout.spacing1)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func segmentButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(isOn ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(isOn ? OPSStyle.Colors.cardBackgroundDark : Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pick-existing fields

    @ViewBuilder
    private var existingFields: some View {
        if companyFamilies.isEmpty {
            Text("No stock items yet — switch to Create new to add one.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            CatalogFieldLabel("Stock item")
            familyPicker
            CatalogFieldLabel("Variant")
            variantPicker
        }
    }

    private var familyPicker: some View {
        Menu {
            ForEach(companyFamilies) { family in
                Button {
                    if selectedFamilyId != family.id { selectedVariantId = nil }
                    selectedFamilyId = family.id
                    // Auto-pick when the family has exactly one variant.
                    let vs = variants(for: family.id)
                    if vs.count == 1 { selectedVariantId = vs[0].id }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if selectedFamilyId == family.id {
                        Label(family.name, systemImage: "checkmark")
                    } else {
                        Text(family.name)
                    }
                }
            }
        } label: {
            menuLabel(text: selectedFamily?.name ?? "Pick a stock item")
        }
    }

    private var variantPicker: some View {
        Menu {
            if variantsForSelectedFamily.isEmpty {
                Text("No variants")
            } else {
                ForEach(variantsForSelectedFamily) { variant in
                    Button {
                        selectedVariantId = variant.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if selectedVariantId == variant.id {
                            Label(variantLabel(variant), systemImage: "checkmark")
                        } else {
                            Text(variantLabel(variant))
                        }
                    }
                }
            }
        } label: {
            menuLabel(text: selectedVariant.map(variantLabel)
                ?? (selectedFamilyId == nil ? "Pick item first" : "Pick a variant"))
        }
        .disabled(selectedFamilyId == nil || variantsForSelectedFamily.isEmpty)
    }

    // MARK: - Create-new fields

    @ViewBuilder
    private var newFields: some View {
        CatalogFieldLabel("Name")
        TextField("e.g. Top rail", text: $name)
            .textFieldStyle(CatalogTextFieldStyle())
            .focused($nameFocused)

        if trackCost {
            CatalogFieldLabel("Your cost (optional)")
            moneyField($costText, placeholder: "0")
        }

        CatalogFieldLabel("Unit")
        UnitPickerField(
            selectedUnitId: $unitId,
            companyUnits: companyUnits,
            canCreateNew: true,
            onCreateRequested: { showingUnitCreate = true },
            allowFlatRate: true
        )

        variantsDisclosure
    }

    // MARK: - Create-new variant matrix

    @ViewBuilder
    private var variantsDisclosure: some View {
        DisclosureGroup(isExpanded: $variantsExpanded) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                Text("Comes in colors or sizes? List them — you get a variant for each.")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(axes) { axis in axisEditor(axisId: axis.id) }

                if axes.count < 2 {
                    Button {
                        withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) {
                            axes.append(AssemblyMaterialAxis())
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: "plus.circle")
                            Text(axes.isEmpty ? "Add an option" : "Add a second option")
                        }
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                if !cleanAxesLocal.isEmpty { variantCountReadout }
            }
            .padding(.top, OPSStyle.Layout.spacing2)
        } label: {
            Text("// VARIANTS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    @ViewBuilder
    private func axisEditor(axisId: String) -> some View {
        if let axisIndex = axes.firstIndex(where: { $0.id == axisId }) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    TextField("e.g. Color", text: bindingAxisName(axisId))
                        .textFieldStyle(CatalogTextFieldStyle())
                    Button {
                        withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) {
                            axes.removeAll { $0.id == axisId }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .frame(width: OPSStyle.Layout.touchTargetStandard,
                                   height: OPSStyle.Layout.touchTargetStandard)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .accessibilityLabel("Remove option")
                }

                ForEach(axes[axisIndex].values.indices, id: \.self) { valueIndex in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        TextField("e.g. Black", text: bindingAxisValue(axisId, valueIndex))
                            .textFieldStyle(CatalogTextFieldStyle())
                        Button {
                            removeAxisValue(axisId, valueIndex)
                        } label: {
                            Image(systemName: "minus.circle")
                                .frame(width: OPSStyle.Layout.touchTargetStandard,
                                       height: OPSStyle.Layout.touchTargetStandard)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .disabled(axes[axisIndex].values.count <= 1)
                        .accessibilityLabel("Remove value")
                    }
                }

                Button {
                    addAxisValue(axisId)
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "plus.circle")
                        Text("Add value")
                    }
                    .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private func bindingAxisName(_ axisId: String) -> Binding<String> {
        Binding(
            get: { axes.first { $0.id == axisId }?.name ?? "" },
            set: { value in
                if let index = axes.firstIndex(where: { $0.id == axisId }) { axes[index].name = value }
            })
    }

    private func bindingAxisValue(_ axisId: String, _ valueIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard let axis = axes.first(where: { $0.id == axisId }),
                      valueIndex < axis.values.count else { return "" }
                return axis.values[valueIndex]
            },
            set: { value in
                if let index = axes.firstIndex(where: { $0.id == axisId }),
                   valueIndex < axes[index].values.count {
                    axes[index].values[valueIndex] = value
                }
            })
    }

    private func addAxisValue(_ axisId: String) {
        if let index = axes.firstIndex(where: { $0.id == axisId }) { axes[index].values.append("") }
    }

    private func removeAxisValue(_ axisId: String, _ valueIndex: Int) {
        guard let index = axes.firstIndex(where: { $0.id == axisId }),
              axes[index].values.count > 1, valueIndex < axes[index].values.count else { return }
        axes[index].values.remove(at: valueIndex)
    }

    @ViewBuilder
    private var variantCountReadout: some View {
        let counts = cleanAxesLocal.map { $0.values.count }
        let product = counts.reduce(1, *)
        let over = product > AssemblyMaterialDraft.maxVariants
        let expr = counts.count > 1
            ? "\(counts.map(String.init).joined(separator: " × ")) = \(product) variants"
            : "\(product) variant\(product == 1 ? "" : "s")"
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(expr)
                .font(OPSStyle.Typography.bodyBold)
                .monospacedDigit()
                .foregroundColor(over ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
            if over {
                Text("Too many. Keep it under \(AssemblyMaterialDraft.maxVariants) — trim a few values.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Build draft

    private func buildDraft() -> AssemblyMaterialDraft? {
        switch mode {
        case .new:
            return AssemblyMaterialDraft(name: name, costText: costText, qtyText: qtyText,
                                         unitId: unitId, catalogVariantId: nil, axes: axes)
        case .existing:
            guard let variant = selectedVariant else { return nil }
            let cost = variant.unitCostOverride ?? selectedFamily?.defaultUnitCost
            let costStr = cost.map { String(format: "%.2f", $0) } ?? ""
            let resolvedUnit = variant.unitId ?? selectedFamily?.defaultUnitId
            return AssemblyMaterialDraft(name: variantLabel(variant), costText: costStr,
                                         qtyText: qtyText, unitId: resolvedUnit,
                                         catalogVariantId: variant.id)
        }
    }

    // MARK: - Shared field visuals

    /// A money input that matches `CatalogTextFieldStyle` but pins a leading
    /// "$" inside the box.
    private func moneyField(_ text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("$")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField(placeholder, text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(.decimalPad)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    @ViewBuilder
    private func menuLabel(text: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}
