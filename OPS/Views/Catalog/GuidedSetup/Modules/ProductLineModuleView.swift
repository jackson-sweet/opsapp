//
//  ProductLineModuleView.swift
//  OPS
//
//  The services / goods module: add as many product lines as you like, each
//  with a sell rate, your cost (when tracking margins), unit, and category.
//  Every line saves straight to the catalog. Inline-create for units and
//  categories. Flow navigation (NEXT / FINISH) lives in the container bar.
//

import SwiftUI
import SwiftData

struct ProductLineModuleView: View {
    @ObservedObject var model: GuidedCatalogSetupModel
    let kind: ProductLineKind
    let isOnline: Bool

    @Environment(\.modelContext) private var modelContext
    @Query private var allUnits: [CatalogUnit]
    @Query private var allCategories: [CatalogCategory]

    @State private var draft: ProductLineDraft
    @State private var showingUnitCreate = false
    @State private var showingCategoryCreate = false
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: GuidedCatalogSetupModel, kind: ProductLineKind, isOnline: Bool) {
        self.model = model
        self.kind = kind
        self.isOnline = isOnline
        _draft = State(initialValue: ProductLineDraft(kind: kind))
    }

    private var trackCost: Bool { model.profile?.trackCost ?? true }

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == model.companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private var companyCategories: [CatalogCategory] {
        allCategories
            .filter { $0.companyId == model.companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var addedLines: [SavedProductLine] {
        model.savedLines.filter { $0.kind == kind }
    }

    // MARK: - Validation

    private var sellAmount: Double? { model.parseMoney(draft.sellText) }

    private var sellInvalid: Bool {
        !draft.sellText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sellAmount == nil
    }

    private var costInvalid: Bool {
        guard trackCost else { return false }
        let trimmed = draft.costText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && model.parseMoney(trimmed) == nil
    }

    /// Every tier row has a non-blank, unique label and a positive price. A single
    /// valid row is allowed — the commit degrades it to a flat line.
    private var tiersValid: Bool {
        guard let tiers = draft.tiers else { return true }
        let labels = tiers.rows.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !tiers.rows.isEmpty, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        guard Set(labels.map { $0.lowercased() }).count == labels.count else { return false }
        return tiers.rows.allSatisfy { (model.parseMoney($0.priceText) ?? 0) > 0 }
    }

    private var canAdd: Bool {
        guard isOnline, !model.isSaving else { return false }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !model.isDuplicateName(draft.name) else { return false }
        if draft.tiers == nil {
            guard sellAmount != nil, !costInvalid else { return false }
        } else {
            guard tiersValid else { return false }
        }
        return true
    }

    private var disabledReason: String? {
        if model.isSaving { return nil }
        if !isOnline { return "// OFFLINE — SAVES PAUSED" }
        if model.isDuplicateName(draft.name) { return "// NAME ALREADY USED" }
        let nameEmpty = draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let tiers = draft.tiers {
            if nameEmpty { return "// NAME REQUIRED" }
            let labels = tiers.rows.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }
            if labels.contains(where: { $0.isEmpty }) { return "// EACH OPTION NEEDS A NAME" }
            if Set(labels.map { $0.lowercased() }).count != labels.count { return "// OPTION NAMES MUST BE UNIQUE" }
            if tiers.rows.contains(where: { (model.parseMoney($0.priceText) ?? 0) <= 0 }) { return "// EACH OPTION NEEDS A PRICE" }
            return nil
        }
        if nameEmpty || sellAmount == nil {
            return kind == .service ? "// NAME AND RATE REQUIRED" : "// NAME AND PRICE REQUIRED"
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header
                formCard
                addButton
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
                if !addedLines.isEmpty { addedListCard }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingUnitCreate) {
            InlineCreateUnitSheet(companyId: model.companyId) { newId in draft.unitId = newId }
        }
        .sheet(isPresented: $showingCategoryCreate) {
            InlineCreateCategorySheet(companyId: model.companyId) { newId in draft.categoryId = newId }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { nameFocused = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(kind == .service ? "// SERVICES" : "// GOODS")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(kind == .service ? "ADD YOUR SERVICES" : "ADD YOUR GOODS")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(kind == .service
                 ? "The work customers pay your crew to do. Add as many as you like."
                 : "The products you sell on an estimate. Add as many as you like.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader(kind.displayLabel)

            CatalogFieldLabel("Name")
            TextField(kind == .service ? "e.g. Install labor" : "e.g. Composite deck board", text: $draft.name)
                .textFieldStyle(CatalogTextFieldStyle())
                .focused($nameFocused)
                .submitLabel(.next)

            // Flat pricing (hidden when this line is priced by option/tier).
            if draft.tiers == nil {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        CatalogFieldLabel(kind == .service ? "Sell rate" : "Sell price")
                        TextField("0", text: $draft.sellText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(CatalogTextFieldStyle())
                        if sellInvalid { validationLine("// MUST BE A NUMBER") }
                    }

                    if trackCost {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            CatalogFieldLabel("Your cost")
                            TextField("Optional", text: $draft.costText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(CatalogTextFieldStyle())
                            if costInvalid { validationLine("// MUST BE A NUMBER") }
                        }
                    }
                }

                if trackCost, let margin = model.marginPercent(sellText: draft.sellText, costText: draft.costText) {
                    marginReadout(margin)
                }
            }

            tierSection

            CatalogFieldLabel("Unit")
            UnitPickerField(
                selectedUnitId: $draft.unitId,
                companyUnits: companyUnits,
                canCreateNew: true,
                onCreateRequested: { showingUnitCreate = true },
                allowFlatRate: true
            )

            CatalogFieldLabel("Category")
            CategoryPickerField(
                selectedCategoryId: $draft.categoryId,
                companyCategories: companyCategories,
                canCreateNew: true,
                onCreateRequested: { showingCategoryCreate = true }
            )
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var addButton: some View {
        Button {
            Task { await add() }
        } label: {
            if model.isSaving {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.tertiaryText))
                        .scaleEffect(0.75)
                    Text("SAVING")
                }
            } else {
                Text(kind == .service ? "ADD SERVICE" : "ADD GOOD")
            }
        }
        .opsPrimaryButtonStyle(isDisabled: !canAdd)
        .disabled(!canAdd)
        .accessibilityLabel(kind == .service ? "Add service" : "Add good")
    }

    private var addedListCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                CatalogSectionHeader(kind == .service ? "SERVICES ADDED" : "GOODS ADDED")
                Spacer()
                Text("\(addedLines.count)")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            ForEach(addedLines) { line in
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(line.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if let count = line.tierCount, count > 0 {
                        Text("· \(count) \(tierSuffixWord(line))")
                            .font(OPSStyle.Typography.metadata)
                            .monospacedDigit()
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(model.formatMoney(line.sell))
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(OPSStyle.Layout.spacing2)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private func validationLine(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
    }

    private func marginReadout(_ margin: Double) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// MARGIN")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text("\(Int(margin.rounded()))%")
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(margin >= 0 ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.errorText)
        }
    }

    // MARK: - Tiers (price by option)

    /// The axis name the operator typed, or a sensible fallback for labels/buttons.
    private var axisSingular: String {
        let axis = (draft.tiers?.axisName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return axis.isEmpty ? "Option" : axis
    }

    /// "3 sizes" / "1 size" — the saved-line tier suffix, pluralized off the axis.
    private func tierSuffixWord(_ line: SavedProductLine) -> String {
        let base = (line.tierAxisLabel ?? "option").lowercased()
        return (line.tierCount ?? 0) == 1 ? base : base + "s"
    }

    /// Optional disclosure that turns one line into N priced tiers. Off => the flat
    /// Sell/cost row above shows; on => it hides and price comes from the tier rows.
    @ViewBuilder private var tierSection: some View {
        Button {
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) {
                draft.tiers = (draft.tiers == nil) ? ProductLineTiers() : nil
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: draft.tiers == nil ? "plus.circle" : "minus.circle")
                Text(draft.tiers == nil ? "// PRICE BY OPTION" : "// BACK TO ONE PRICE")
                    .font(OPSStyle.Typography.metadata)
                Spacer()
            }
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.tiers == nil ? "Price by option" : "Back to one price")

        if draft.tiers != nil {
            Text("Same item, different sizes or grades — a price for each.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            tierEditor
        }
    }

    @ViewBuilder private var tierEditor: some View {
        CatalogFieldLabel("Option name")
        TextField("Size", text: Binding(
            get: { draft.tiers?.axisName ?? "" },
            set: { draft.tiers?.axisName = $0 }))
            .textFieldStyle(CatalogTextFieldStyle())

        CatalogFieldLabel(axisSingular.uppercased())
        ForEach(draft.tiers?.rows ?? []) { row in
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                TextField("e.g. Sedan", text: bindingTierLabel(row.id))
                    .textFieldStyle(CatalogTextFieldStyle())
                TextField("0", text: bindingTierPrice(row.id))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(CatalogTextFieldStyle())
                    .frame(width: 96)
                    .monospacedDigit()
                Button { removeTier(row.id) } label: {
                    Image(systemName: "minus.circle.fill")
                        .frame(width: OPSStyle.Layout.touchTargetStandard,
                               height: OPSStyle.Layout.touchTargetStandard)
                }
                .buttonStyle(.plain)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .disabled((draft.tiers?.rows.count ?? 0) <= 1)
                .accessibilityLabel("Remove \(axisSingular.lowercased())")
            }
        }

        Button { addTier() } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "plus.circle")
                Text("ADD \(axisSingular.uppercased())")
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(OPSStyle.Colors.secondaryText)
    }

    private func bindingTierLabel(_ id: String) -> Binding<String> {
        Binding(
            get: { draft.tiers?.rows.first { $0.id == id }?.label ?? "" },
            set: { value in
                if let index = draft.tiers?.rows.firstIndex(where: { $0.id == id }) {
                    draft.tiers?.rows[index].label = value
                }
            })
    }

    private func bindingTierPrice(_ id: String) -> Binding<String> {
        Binding(
            get: { draft.tiers?.rows.first { $0.id == id }?.priceText ?? "" },
            set: { value in
                if let index = draft.tiers?.rows.firstIndex(where: { $0.id == id }) {
                    draft.tiers?.rows[index].priceText = value
                }
            })
    }

    private func addTier() {
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) {
            draft.tiers?.rows.append(ProductTierRow())
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func removeTier(_ id: String) {
        guard (draft.tiers?.rows.count ?? 0) > 1 else { return }
        withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) {
            draft.tiers?.rows.removeAll { $0.id == id }
        }
    }

    @MainActor
    private func add() async {
        await model.saveProductLine(draft, trackCost: trackCost,
                                    units: companyUnits, categories: companyCategories,
                                    modelContext: modelContext)
        if model.errorMessage == nil {
            draft = ProductLineDraft(kind: kind)
            nameFocused = true
        }
    }
}

#Preview {
    let model = GuidedCatalogSetupModel(companyId: "preview", userId: "preview")
    model.profile = BusinessProfile(sells: .services, pricing: .hourly,
                                    materialUse: .none, inventory: nil, trackCost: true)
    return ZStack {
        OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
        ProductLineModuleView(model: model, kind: .service, isOnline: true)
    }
    .modelContainer(for: [CatalogUnit.self, CatalogCategory.self, Product.self], inMemory: true)
}
