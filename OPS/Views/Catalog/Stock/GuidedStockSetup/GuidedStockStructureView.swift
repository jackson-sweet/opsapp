import SwiftUI

// MARK: - GuidedStockStructureView
//
// STRUCTURE stage — the conversational grouping + attributes + measurement + stock + products engine.
// Owns its own sub-flow state, BACK affordance, and CONTINUE/finalize CTA.
// GuidedStockSetupFlow suppresses its generic bottom bar for this stage.
//
// Internal step machine:
//   substep .grouping     — iterates every GuidedStructuredGroup via groupIndex cursor;
//                           resolves multi-member merges and single-item "versions?" splits.
//   substep .attributes   — iterates only the versioned (isSingleItem=false) groups via
//                           attrIndex cursor; collects attribute names + values.
//   substep .measurement  — iterates ALL groups via measurementIndex; captures how stock is counted.
//   substep .stock        — iterates groups × variants via (stockGroupIndex, stockVariantIndex);
//                           captures on-hand quantities for every variant.
//   substep .products     — iterates only selling groups via productsCursor (capability-gated);
//                           captures sell mode, recipe link, and bundle composition.

struct GuidedStockStructureView: View {

    @ObservedObject var model: GuidedStockSetupModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    // MARK: - Internal sub-step state

    private enum Substep: Equatable {
        case grouping
        case attributes
        case measurement
        case stock
        case products
    }

    @State private var substep: Substep = .grouping
    @State private var groupIndex: Int = 0       // cursor through model.groups (grouping phase)
    @State private var attrIndex: Int = 0        // cursor through versioned groups (attributes phase)
    @State private var measurementIndex: Int = 0 // cursor through ALL groups (measurement phase)
    @State private var stockGroupIndex: Int = 0  // cursor through groups (stock phase)
    @State private var stockVariantIndex: Int = 0 // cursor through variants within stockGroupIndex group
    @State private var productsCursor: Int = 0   // cursor through sellingGroupIndices (products phase)

    // MARK: - Computed helpers

    private var currentGroup: GuidedStructuredGroup? {
        guard model.groups.indices.contains(groupIndex) else { return nil }
        return model.groups[groupIndex]
    }

    /// Permission gate for the products substep.
    private var canManageProducts: Bool {
        PermissionStore.shared.can("catalog.products.manage")
    }

    /// Whether any member captured item of a group has a selling kind.
    private func groupSells(_ g: GuidedStructuredGroup) -> Bool {
        model.capturedItems.contains { item in
            g.memberItemIds.contains(item.id) && (item.kind == .sell || item.kind == .both)
        }
    }

    /// Whether any member captured item of a group has a stock kind.
    private func groupStocks(_ g: GuidedStructuredGroup) -> Bool {
        model.capturedItems.contains { item in
            g.memberItemIds.contains(item.id) && (item.kind == .stock || item.kind == .both)
        }
    }

    /// Indices into model.groups where the group sells (used by the products substep).
    private var sellingGroupIndices: [Int] {
        model.groups.indices.filter { groupSells(model.groups[$0]) }
    }

    /// The group currently under review in the products substep.
    private var currentProductsGroup: GuidedStructuredGroup? {
        guard sellingGroupIndices.indices.contains(productsCursor) else { return nil }
        let idx = sellingGroupIndices[productsCursor]
        guard model.groups.indices.contains(idx) else { return nil }
        return model.groups[idx]
    }

    /// The model.groups index for the current products group.
    private var currentProductsGroupModelIndex: Int? {
        guard sellingGroupIndices.indices.contains(productsCursor) else { return nil }
        return sellingGroupIndices[productsCursor]
    }

    /// Indices of groups where isSingleItem == false (need attribute collection).
    private var versionedGroupIndices: [Int] {
        model.groups.indices.filter { model.groups[$0].isSingleItem == false }
    }

    private var currentVersionedGroupIndex: Int? {
        guard versionedGroupIndices.indices.contains(attrIndex) else { return nil }
        return versionedGroupIndices[attrIndex]
    }

    private var currentVersionedGroup: GuidedStructuredGroup? {
        guard let idx = currentVersionedGroupIndex else { return nil }
        return model.groups[idx]
    }

    private var currentMeasurementGroup: GuidedStructuredGroup? {
        guard model.groups.indices.contains(measurementIndex) else { return nil }
        return model.groups[measurementIndex]
    }

    // Stock phase: the group currently being filled
    private var currentStockGroup: GuidedStructuredGroup? {
        guard model.groups.indices.contains(stockGroupIndex) else { return nil }
        return model.groups[stockGroupIndex]
    }

    // Stock phase: variants for the current stock group
    private var currentStockVariants: [CatalogSetupVariantDraft] {
        guard let group = currentStockGroup else { return [] }
        return GuidedStockDraftBuilder.variantDrafts(for: group)
    }

    // Stock phase: the variant currently being filled
    private var currentStockVariant: CatalogSetupVariantDraft? {
        guard currentStockVariants.indices.contains(stockVariantIndex) else { return nil }
        return currentStockVariants[stockVariantIndex]
    }

    private var pageAnimation: Animation {
        reducedMotion ? .linear(duration: 0.15) : OPSStyle.Animation.page
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable question area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    switch substep {
                    case .grouping:
                        if let group = currentGroup {
                            GroupingCard(
                                group: group,
                                capturedItems: model.capturableItems,
                                onYesOneItem: { handleGroupingYes() },
                                onNoKeepSeparate: { handleGroupingNo() }
                            )
                            .id("grouping-\(group.id)")
                            .transition(cardTransition)
                            .animation(pageAnimation, value: groupIndex)
                        }

                    case .attributes:
                        if let group = currentVersionedGroup, let idx = currentVersionedGroupIndex {
                            AttributesCard(
                                group: binding(for: idx),
                                onContinue: { handleAttributesContinue() }
                            )
                            .id("attrs-\(group.id)")
                            .transition(cardTransition)
                            .animation(pageAnimation, value: attrIndex)
                        }

                    case .measurement:
                        if let group = currentMeasurementGroup {
                            MeasurementCard(
                                group: group,
                                onSelect: { measurement in
                                    handleMeasurementSelect(measurement)
                                }
                            )
                            .id("measurement-\(group.id)")
                            .transition(cardTransition)
                            .animation(pageAnimation, value: measurementIndex)
                        }

                    case .stock:
                        if let group = currentStockGroup,
                           let variant = currentStockVariant {
                            let gIdx = stockGroupIndex
                            let vIdx = stockVariantIndex
                            StockCard(
                                group: groupBinding(for: gIdx),
                                variant: variant,
                                entry: stockEntryBinding(groupIndex: gIdx, variant: variant),
                                onContinue: { handleStockContinue() }
                            )
                            .id("stock-\(group.id)-\(variant.id)")
                            .transition(cardTransition)
                            .animation(pageAnimation, value: stockGroupIndex * 1000 + stockVariantIndex)
                        }

                    case .products:
                        if let group = currentProductsGroup,
                           let mIdx = currentProductsGroupModelIndex {
                            ProductsCard(
                                group: productsGroupBinding(for: mIdx),
                                allCapturedItems: model.capturedItems,
                                isStocked: groupStocks(group),
                                onContinue: { handleProductsContinue() }
                            )
                            .id("products-\(group.id)-\(productsCursor)")
                            .transition(cardTransition)
                            .animation(pageAnimation, value: productsCursor)
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom bar — BACK + optional status line
            bottomBar
        }
        .onAppear {
            model.seedGroupsFromCapture()
            substep = .grouping
            groupIndex = 0
            attrIndex = 0
            measurementIndex = 0
            stockGroupIndex = 0
            stockVariantIndex = 0
            productsCursor = 0
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(pageAnimation) { stepBack() }
            } label: {
                Text("BACK")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(minWidth: 72, minHeight: OPSStyle.Layout.touchTargetMin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go back")

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing3)
    }

    // MARK: - Navigation helpers

    private var cardTransition: AnyTransition {
        reducedMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            )
    }

    private func stepBack() {
        switch substep {

        case .grouping:
            if groupIndex > 0 {
                groupIndex -= 1
            } else {
                // First grouping question — return to CAPTURE stage.
                model.back()
            }

        case .attributes:
            if attrIndex > 0 {
                attrIndex -= 1
            } else {
                // First attributes question — go back to last grouping question.
                substep = .grouping
                groupIndex = max(0, model.groups.count - 1)
            }

        case .measurement:
            if measurementIndex > 0 {
                measurementIndex -= 1
            } else {
                // First measurement — go back to last attributes (or last grouping if no versioned groups).
                if !versionedGroupIndices.isEmpty {
                    substep = .attributes
                    attrIndex = max(0, versionedGroupIndices.count - 1)
                } else {
                    substep = .grouping
                    groupIndex = max(0, model.groups.count - 1)
                }
            }

        case .stock:
            if stockVariantIndex > 0 {
                stockVariantIndex -= 1
            } else if stockGroupIndex > 0 {
                stockGroupIndex -= 1
                let prevVariants = GuidedStockDraftBuilder.variantDrafts(for: model.groups[stockGroupIndex])
                stockVariantIndex = max(0, prevVariants.count - 1)
            } else {
                // First stock question — go back to last measurement.
                substep = .measurement
                measurementIndex = max(0, model.groups.count - 1)
            }
            model.persist()

        case .products:
            if productsCursor > 0 {
                productsCursor -= 1
            } else {
                // First products question — back to last stock (last variant of last group).
                substep = .stock
                stockGroupIndex = max(0, model.groups.count - 1)
                let lastVariants = GuidedStockDraftBuilder.variantDrafts(for: model.groups[max(0, model.groups.count - 1)])
                stockVariantIndex = max(0, lastVariants.count - 1)
            }
            model.persist()
        }
    }

    // MARK: - Grouping handlers

    private func handleGroupingYes() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // YES: keep multi-member group as a versioned family (isSingleItem = false).
        // Single-member "one thing?" → mark isSingleItem = true.
        guard model.groups.indices.contains(groupIndex) else { return }
        if model.groups[groupIndex].memberItemIds.count == 1 {
            // Single-member path: "ONE THING" — stays isSingleItem = true (already default for solo).
            model.groups[groupIndex].isSingleItem = true
        }
        // else multi-member YES: isSingleItem is already false from seed — no change needed.
        advanceGrouping()
    }

    private func handleGroupingNo() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard model.groups.indices.contains(groupIndex) else { return }
        let group = model.groups[groupIndex]

        if group.memberItemIds.count > 1 {
            // NO — KEEP SEPARATE: explode into individual single-item groups.
            let replacements: [GuidedStructuredGroup] = group.memberItemIds.compactMap { itemId in
                guard let item = model.capturableItems.first(where: { $0.id == itemId }) else { return nil }
                return GuidedStructuredGroup(
                    id: "group::" + itemId,
                    familyName: item.name,
                    memberItemIds: [itemId],
                    isSingleItem: true,
                    attributes: [],
                    isConfirmed: false
                )
            }
            // Replace the multi-member group with N single-item groups in-place.
            var updated = model.groups
            updated.replaceSubrange(groupIndex...groupIndex, with: replacements)
            model.groups = updated
            // groupIndex now points at the first replacement — advance past all of them.
            withAnimation(pageAnimation) {
                groupIndex = min(groupIndex + replacements.count, model.groups.count)
                checkGroupingComplete()
            }
        } else {
            // Single-member "DIFFERENT VERSIONS": mark isSingleItem = false (will get attributes).
            model.groups[groupIndex].isSingleItem = false
            advanceGrouping()
        }
    }

    private func advanceGrouping() {
        withAnimation(pageAnimation) {
            groupIndex += 1
            checkGroupingComplete()
        }
    }

    private func checkGroupingComplete() {
        if groupIndex >= model.groups.count {
            // All grouping decisions done. Move to attributes if any versioned groups exist;
            // otherwise skip straight to measurement.
            if versionedGroupIndices.isEmpty {
                startMeasurement()
            } else {
                substep = .attributes
                attrIndex = 0
            }
        }
    }

    // MARK: - Attributes handler

    private func handleAttributesContinue() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(pageAnimation) {
            attrIndex += 1
            if attrIndex >= versionedGroupIndices.count {
                startMeasurement()
            }
        }
    }

    // MARK: - Measurement handlers

    private func startMeasurement() {
        substep = .measurement
        measurementIndex = 0
    }

    private func handleMeasurementSelect(_ measurement: GuidedMeasurement) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard model.groups.indices.contains(measurementIndex) else { return }
        model.groups[measurementIndex].measurement = measurement
        switch measurement {
        case .piece:
            break
        case .length:
            model.groups[measurementIndex].lengthUnit = "ft"
        case .area:
            model.groups[measurementIndex].lengthUnit = "ft"
            model.groups[measurementIndex].widthUnit = "ft"
        }
        model.persist()
        withAnimation(pageAnimation) {
            measurementIndex += 1
            if measurementIndex >= model.groups.count {
                startStock()
            }
        }
    }

    // MARK: - Stock handlers

    private func startStock() {
        substep = .stock
        stockGroupIndex = 0
        stockVariantIndex = 0
        // Seed missing stock entries for the first group upfront.
        ensureStockEntries(for: stockGroupIndex)
    }

    /// Ensure model.groups[gIdx].stockEntries contains exactly one entry per variant.
    /// Creates entries lazily by variant id; preserves any existing entries.
    private func ensureStockEntries(for gIdx: Int) {
        guard model.groups.indices.contains(gIdx) else { return }
        let variants = GuidedStockDraftBuilder.variantDrafts(for: model.groups[gIdx])
        for variant in variants {
            if !model.groups[gIdx].stockEntries.contains(where: { $0.variantKey == variant.id }) {
                model.groups[gIdx].stockEntries.append(GuidedStockEntry(variantKey: variant.id))
            }
        }
    }

    private func handleStockContinue() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        model.persist()
        withAnimation(pageAnimation) {
            let variants = currentStockVariants
            if stockVariantIndex + 1 < variants.count {
                // More variants in this group.
                stockVariantIndex += 1
            } else if stockGroupIndex + 1 < model.groups.count {
                // Next group.
                stockGroupIndex += 1
                stockVariantIndex = 0
                ensureStockEntries(for: stockGroupIndex)
            } else {
                // All groups × variants complete — route to products or finalize.
                startProductsOrFinalize()
            }
        }
    }

    /// Transitions to .products if the operator has the permission AND there are selling groups;
    /// otherwise calls finalize() immediately (stock-only path).
    private func startProductsOrFinalize() {
        let selling = sellingGroupIndices
        if canManageProducts && !selling.isEmpty {
            substep = .products
            productsCursor = 0
        } else {
            finalize()
        }
    }

    // MARK: - Products handlers

    private func handleProductsContinue() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        model.persist()
        withAnimation(pageAnimation) {
            if productsCursor + 1 < sellingGroupIndices.count {
                productsCursor += 1
            } else {
                finalize()
            }
        }
    }

    // MARK: - Finalize

    private func finalize() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        for idx in model.groups.indices {
            model.groups[idx].isConfirmed = true
        }
        model.persist()
        model.advance()
    }

    // MARK: - Binding helpers

    private func binding(for groupIdx: Int) -> Binding<GuidedStructuredGroup> {
        Binding(
            get: { model.groups[groupIdx] },
            set: { model.groups[groupIdx] = $0 }
        )
    }

    private func groupBinding(for gIdx: Int) -> Binding<GuidedStructuredGroup> {
        Binding(
            get: { model.groups.indices.contains(gIdx) ? model.groups[gIdx] : GuidedStructuredGroup() },
            set: { if model.groups.indices.contains(gIdx) { model.groups[gIdx] = $0 } }
        )
    }

    /// Binding for a selling group's product answers inside the products substep.
    private func productsGroupBinding(for gIdx: Int) -> Binding<GuidedStructuredGroup> {
        Binding(
            get: { model.groups.indices.contains(gIdx) ? model.groups[gIdx] : GuidedStructuredGroup() },
            set: { if model.groups.indices.contains(gIdx) { model.groups[gIdx] = $0 } }
        )
    }

    /// Returns a Binding<GuidedStockEntry> for the given group index + variant id.
    /// Creates the entry if it doesn't exist yet (defensive — ensureStockEntries pre-seeds them).
    private func stockEntryBinding(groupIndex gIdx: Int, variant: CatalogSetupVariantDraft) -> Binding<GuidedStockEntry> {
        Binding(
            get: {
                guard model.groups.indices.contains(gIdx) else {
                    return GuidedStockEntry(variantKey: variant.id)
                }
                if let existing = model.groups[gIdx].stockEntries.first(where: { $0.variantKey == variant.id }) {
                    return existing
                }
                return GuidedStockEntry(variantKey: variant.id)
            },
            set: { newValue in
                guard model.groups.indices.contains(gIdx) else { return }
                if let idx = model.groups[gIdx].stockEntries.firstIndex(where: { $0.variantKey == variant.id }) {
                    model.groups[gIdx].stockEntries[idx] = newValue
                } else {
                    model.groups[gIdx].stockEntries.append(newValue)
                }
            }
        )
    }
}

// MARK: - GroupingCard

private struct GroupingCard: View {

    let group: GuidedStructuredGroup
    let capturedItems: [GuidedCapturedItem]
    let onYesOneItem: () -> Void
    let onNoKeepSeparate: () -> Void

    private var isMultiMember: Bool { group.memberItemIds.count > 1 }

    private var memberNames: [String] {
        group.memberItemIds.compactMap { id in
            capturedItems.first(where: { $0.id == id })?.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            // Question header
            if isMultiMember {
                Text("These look like the same thing:")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                // Member list — L2 nested card rows
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(memberNames, id: \.self) { name in
                        HStack {
                            Text(name)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .padding(.vertical, OPSStyle.Layout.spacing2)
                            Spacer()
                        }
                        .nestedCard()
                    }
                }
            } else {
                // Single-member: "Is {name} one thing, or does it come in versions?"
                Group {
                    Text("Is ")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    + Text(group.familyName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    + Text(" one thing, or does it come in versions?")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            // Choice buttons
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: onYesOneItem) {
                    Text(isMultiMember ? "YES — ONE ITEM" : "ONE THING")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StructureChoiceButtonStyle(accent: OPSStyle.Colors.primaryAccent))
                .accessibilityLabel(isMultiMember ? "Yes, one item" : "One thing")

                Button(action: onNoKeepSeparate) {
                    Text(isMultiMember ? "NO — KEEP SEPARATE" : "DIFFERENT VERSIONS")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StructureChoiceButtonStyle(accent: OPSStyle.Colors.secondaryText))
                .accessibilityLabel(isMultiMember ? "No, keep separate" : "Different versions")
            }

            // Teach line
            Text("// IN OPS: one Family, with versions called Variants")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }
}

// MARK: - AttributesCard

private struct AttributesCard: View {

    @Binding var group: GuidedStructuredGroup
    let onContinue: () -> Void

    // Chip options
    private let chipOptions = ["COLOR", "SIZE", "WIDTH", "LENGTH", "THICKNESS", "GRADE", "OTHER"]
    @State private var selectedChips: Set<String> = []
    @State private var otherFieldText: String = ""
    @State private var showOtherField: Bool = false

    // Derived: which attribute indices correspond to which selected chips (by name)
    private var selectedAttributeNames: [String] {
        selectedChips.filter { $0 != "OTHER" }.sorted { a, b in
            (chipOptions.firstIndex(of: a) ?? 99) < (chipOptions.firstIndex(of: b) ?? 99)
        } + (showOtherField && !otherFieldText.trimmingCharacters(in: .whitespaces).isEmpty
             ? [otherFieldText.trimmingCharacters(in: .whitespaces).capitalized]
             : [])
    }

    private var variantCount: Int {
        GuidedStockDraftBuilder.variantCount(for: group)
    }

    private var canContinue: Bool {
        let trimmedName = group.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        // At least one attribute with ≥2 non-blank values
        return group.attributes.contains { attr in
            !attr.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attr.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count >= 2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            // Editable family name
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// FAMILY NAME")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                TextField("Family name", text: $group.familyName)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }

            Divider()
                .background(OPSStyle.Colors.separator)

            // Attribute question
            Text("What's different between them?")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Attribute chips
            ChipGrid(
                options: chipOptions,
                selectedChips: $selectedChips,
                showOtherField: $showOtherField,
                otherFieldText: $otherFieldText,
                onChange: { syncAttributesFromChips() }
            )

            // Teach line
            Text("// IN OPS: that's an Attribute; each option is a Value")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            // Value editors for each selected attribute
            if !group.attributes.isEmpty {
                Divider()
                    .background(OPSStyle.Colors.separator)

                ForEach($group.attributes) { $attr in
                    if !attr.name.isEmpty {
                        AttributeValueEditor(attribute: $attr, prefillValues: prefillValues(for: attr))
                    }
                }

                // Live variant count
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Group {
                        Text("That's ")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        + Text("\(variantCount)")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        + Text(" versions.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Text("// IN OPS: \(variantCount) Variants")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .animation(OPSStyle.Animation.panel, value: variantCount)
            }

            // CONTINUE button
            Button(action: onContinue) {
                Text("CONTINUE →")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StructureCTAButtonStyle(isEnabled: canContinue))
            .disabled(!canContinue)
            .accessibilityLabel("Continue")
            .accessibilityValue(canContinue ? "Ready" : "Add at least two values to an attribute")
            .padding(.top, OPSStyle.Layout.spacing2)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
        .onAppear { syncChipsFromAttributes() }
    }

    // MARK: - Prefill

    /// The seeded prefill values for the FIRST attribute (from clustering), only used once.
    private func prefillValues(for attr: GuidedAttribute) -> [String] {
        // Only the first attribute gets prefilled values from the cluster seed.
        guard let firstAttr = group.attributes.first, firstAttr.id == attr.id else { return [] }
        return firstAttr.values
    }

    // MARK: - Chip ↔ Attribute sync

    private func syncAttributesFromChips() {
        let selectedNames: [String] = chipOptions.filter { $0 != "OTHER" && selectedChips.contains($0) }
            .map { $0.capitalized }
        + (showOtherField && !otherFieldText.trimmingCharacters(in: .whitespaces).isEmpty
           ? [otherFieldText.trimmingCharacters(in: .whitespaces).capitalized]
           : [])

        var updated: [GuidedAttribute] = []
        for name in selectedNames {
            if let existing = group.attributes.first(where: { $0.name == name }) {
                updated.append(existing)
            } else {
                // Preserve seeded prefill for the first new attribute if it matches an empty-name slot.
                let prefill: [String]
                if updated.isEmpty, let seedAttr = group.attributes.first, seedAttr.name.isEmpty {
                    prefill = seedAttr.values
                } else {
                    prefill = []
                }
                updated.append(GuidedAttribute(name: name, values: prefill))
            }
        }
        group.attributes = updated
    }

    private func syncChipsFromAttributes() {
        var chips: Set<String> = []
        for attr in group.attributes where !attr.name.isEmpty {
            let upper = attr.name.uppercased()
            if chipOptions.contains(upper) {
                chips.insert(upper)
            } else {
                chips.insert("OTHER")
                otherFieldText = attr.name
                showOtherField = true
            }
        }
        selectedChips = chips
    }
}

// MARK: - MeasurementCard
//
// Substep 2c — "How do you keep track of how much you have?"
// One screen per group; three large option rows; sets group.measurement.

private struct MeasurementCard: View {

    let group: GuidedStructuredGroup
    let onSelect: (GuidedMeasurement) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            // Family context
            Text(group.familyName.isEmpty ? "This item" : group.familyName)
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("How do you keep track of how much you have?")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Choice buttons — min 48pt per spec
            VStack(spacing: OPSStyle.Layout.spacing2) {
                MeasurementOptionRow(
                    label: "BY THE PIECE",
                    isSelected: group.measurement == .piece,
                    onTap: { onSelect(.piece) }
                )
                MeasurementOptionRow(
                    label: "BY LENGTH",
                    isSelected: group.measurement == .length,
                    onTap: { onSelect(.length) }
                )
                MeasurementOptionRow(
                    label: "BY AREA",
                    isSelected: group.measurement == .area,
                    onTap: { onSelect(.area) }
                )
            }

            // Teach line
            Text("// IN OPS: sets the Unit and whether stock is counted or measured")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }
}

// MARK: - MeasurementOptionRow

private struct MeasurementOptionRow: View {

    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: 48)
            .background(
                isSelected
                    ? OPSStyle.Colors.surfaceActive
                    : OPSStyle.Colors.surfaceInput
            )
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(OPSStyle.Animation.hover, value: isSelected)
    }
}

// MARK: - StockCard
//
// Substep 2d — "How much do you have?" per variant.
// Branches on group.measurement: piece / length / area.
// Live readout of on-hand total using CatalogSetupWorkflow.mirroredQuantityLabel.

private struct StockCard: View {

    @Binding var group: GuidedStructuredGroup
    let variant: CatalogSetupVariantDraft
    @Binding var entry: GuidedStockEntry
    let onContinue: () -> Void

    // Text state for each numeric field (avoids Double ↔ String round-trip cursor jumps)
    @State private var pieceCountText: String = ""
    @State private var fullWidthText: String = ""
    @State private var fullLengthText: String = ""
    @State private var fullCountText: String = ""
    @State private var offcutTexts: [String] = []

    private var variantLabel: String {
        GuidedStockDraftBuilder.variantLabel(for: group, variant: variant)
    }

    private var onHandLabel: String {
        let drafts = GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)
        if drafts.isEmpty { return "—" }
        return CatalogSetupWorkflow.mirroredQuantityLabel(for: drafts)
    }

    // Enable advancing: forgiving — allow 0/empty. Only block if fullCount > 0 but no length.
    private var canContinue: Bool {
        guard let m = group.measurement else { return true }
        switch m {
        case .piece:
            return true
        case .length, .area:
            // If they entered a full count > 0, they must have a positive length.
            if let count = entry.fullUnitCount, count > 0 {
                guard let length = entry.fullUnitLength, length > 0 else { return false }
                if m == .area {
                    guard let width = entry.fullUnitWidth, width > 0 else { return false }
                }
                return true
            }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            // Variant heading
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// VARIANT")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(variantLabel)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            Divider().background(OPSStyle.Colors.separator)

            // Branch on measurement
            if let measurement = group.measurement {
                switch measurement {
                case .piece:
                    pieceSection
                case .length, .area:
                    lengthAreaSection(isArea: measurement == .area)
                }
            }

            // Live on-hand readout
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("On hand:")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(onHandLabel)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .animation(OPSStyle.Animation.hover, value: onHandLabel)

            // CONTINUE button
            Button(action: {
                commitFieldsToEntry()
                onContinue()
            }) {
                Text("CONTINUE →")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StructureCTAButtonStyle(isEnabled: canContinue))
            .disabled(!canContinue)
            .frame(height: 52)
            .padding(.top, OPSStyle.Layout.spacing2)
            .accessibilityLabel("Continue")
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
        .onAppear { syncTextsFromEntry() }
        .onChange(of: variant.id) { _ in syncTextsFromEntry() }
    }

    // MARK: - Piece section

    private var pieceSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("How many do you have?")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            DecimalInputField(
                placeholder: "0",
                text: $pieceCountText,
                onChange: { syncEntryFromPieceText() }
            )

            Text("// IN OPS: on-hand quantity")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Length / Area section

    private func lengthAreaSection(isArea: Bool) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            // — Full unit dimensions —
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("What's one full unit?")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                if isArea {
                    // Width × Length row with shared unit picker
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        // Width field
                        DecimalInputField(
                            placeholder: "width",
                            text: $fullWidthText,
                            onChange: { syncEntryFromLengthAreaTexts() }
                        )

                        Text("×")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        // Length field
                        DecimalInputField(
                            placeholder: "length",
                            text: $fullLengthText,
                            onChange: { syncEntryFromLengthAreaTexts() }
                        )

                        // Unit picker (applies to both width and length for area)
                        UnitPicker(unit: Binding(
                            get: { group.lengthUnit },
                            set: {
                                group.lengthUnit = $0
                                group.widthUnit = $0
                            }
                        ))
                    }
                } else {
                    // Length only
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        DecimalInputField(
                            placeholder: "length",
                            text: $fullLengthText,
                            onChange: { syncEntryFromLengthAreaTexts() }
                        )

                        UnitPicker(unit: Binding(
                            get: { group.lengthUnit },
                            set: { group.lengthUnit = $0 }
                        ))
                    }
                }
            }
            .nestedCard()

            // — Full unit count —
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("How many full ones?")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                DecimalInputField(
                    placeholder: "0",
                    text: $fullCountText,
                    onChange: { syncEntryFromLengthAreaTexts() }
                )
            }
            .nestedCard()

            // — Offcuts —
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("Any leftover or offcut pieces?")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                ForEach(offcutTexts.indices, id: \.self) { idx in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        DecimalInputField(
                            placeholder: "remaining length",
                            text: offcutBinding(for: idx),
                            onChange: { syncOffcutsToEntry() }
                        )

                        Text(group.lengthUnit)
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(minWidth: 28, alignment: .leading)

                        // Delete offcut row
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(OPSStyle.Animation.hover) {
                                offcutTexts.remove(at: idx)
                                syncOffcutsToEntry()
                            }
                        } label: {
                            Image(systemName: OPSStyle.Icons.minusCircle)
                                .font(.system(size: OPSStyle.Layout.IconSize.md))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        .buttonStyle(.plain)
                    }
                }

                // Add offcut row
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(OPSStyle.Animation.hover) {
                        offcutTexts.append("")
                        syncOffcutsToEntry()
                    }
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.plusCircle)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("ADD OFFCUT")
                            .font(OPSStyle.Typography.metadata)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(.plain)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
            .nestedCard()

            // Teach line
            Text("// IN OPS: each full one and each offcut is a Stock Unit — we track remaining length so cut lists stay honest")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Text ↔ Entry sync

    private func syncTextsFromEntry() {
        pieceCountText = entry.pieceCount.map { Self.format($0) } ?? ""
        fullWidthText = entry.fullUnitWidth.map { Self.format($0) } ?? ""
        fullLengthText = entry.fullUnitLength.map { Self.format($0) } ?? ""
        fullCountText = entry.fullUnitCount.map { Self.format($0) } ?? ""
        offcutTexts = entry.offcutLengths.map { Self.format($0) }
    }

    private func commitFieldsToEntry() {
        syncEntryFromPieceText()
        syncEntryFromLengthAreaTexts()
        syncOffcutsToEntry()
    }

    private func syncEntryFromPieceText() {
        entry.pieceCount = Double(pieceCountText.trimmingCharacters(in: .whitespaces))
    }

    private func syncEntryFromLengthAreaTexts() {
        entry.fullUnitWidth = Double(fullWidthText.trimmingCharacters(in: .whitespaces))
        entry.fullUnitLength = Double(fullLengthText.trimmingCharacters(in: .whitespaces))
        entry.fullUnitCount = Double(fullCountText.trimmingCharacters(in: .whitespaces))
    }

    private func syncOffcutsToEntry() {
        entry.offcutLengths = offcutTexts
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func offcutBinding(for idx: Int) -> Binding<String> {
        Binding(
            get: { offcutTexts.indices.contains(idx) ? offcutTexts[idx] : "" },
            set: { newVal in
                if offcutTexts.indices.contains(idx) {
                    offcutTexts[idx] = newVal
                    syncOffcutsToEntry()
                }
            }
        )
    }

    private static func format(_ value: Double) -> String {
        // Omit trailing .0 for whole numbers; keep decimals otherwise.
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
    }
}

// MARK: - ProductsCard
//
// Substep 2e — Products / Bundles / Recipes (capability-gated, §7.2e).
// One selling group per screen. Scrollable when Q1 + Q2 + Q3 all appear.
// Answers are written into `group.product`.
//
// Q1 (always):          How do you sell this family?  → sellMode
// Q2 (stocked + own/both): Does selling one use stock? → sellingUsesStock
// Q3 (package/both):   What goes in the package?       → bundleChildren

private struct ProductsCard: View {

    @Binding var group: GuidedStructuredGroup
    let allCapturedItems: [GuidedCapturedItem]
    let isStocked: Bool
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    // MARK: - Derived

    /// Items that are NOT members of this group — candidates for bundle children.
    private var bundleCandidates: [GuidedCapturedItem] {
        allCapturedItems.filter { item in
            !group.memberItemIds.contains(item.id)
        }
    }

    /// Whether Q2 (recipe link) should be shown.
    private var showQ2: Bool {
        guard isStocked, let mode = group.product.sellMode else { return false }
        return mode == .onItsOwn || mode == .both
    }

    /// Whether Q3 (bundle builder) should be shown.
    private var showQ3: Bool {
        guard let mode = group.product.sellMode else { return false }
        return mode == .inPackage || mode == .both
    }

    /// The CONTINUE button is enabled once sellMode is set.
    private var canContinue: Bool {
        group.product.sellMode != nil
    }

    private var pageAnimation: Animation {
        reducedMotion ? .linear(duration: 0.15) : OPSStyle.Animation.page
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            // Q1 — Sell mode
            sellModeSection

            // Q2 — Recipe link (stocked + sells on own or both)
            if showQ2 {
                Divider().background(OPSStyle.Colors.separator)
                recipeLinkSection
            }

            // Q3 — Bundle builder (sells in package or both)
            if showQ3 {
                Divider().background(OPSStyle.Colors.separator)
                bundleSection
            }

            // CONTINUE
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onContinue()
            }) {
                Text("CONTINUE →")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StructureCTAButtonStyle(isEnabled: canContinue))
            .disabled(!canContinue)
            .frame(height: 52)
            .padding(.top, OPSStyle.Layout.spacing2)
            .accessibilityLabel("Continue")
            .accessibilityValue(canContinue ? "Ready" : "Choose how you sell this item")
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    // MARK: - Q1: Sell mode

    private var sellModeSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            // Question — emphasise the family name
            Group {
                Text("Do you sell ")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                + Text(group.familyName.isEmpty ? "this item" : group.familyName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                + Text(" on its own, or as part of a package?")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            // Three option rows — ≥48pt each
            VStack(spacing: OPSStyle.Layout.spacing2) {
                SellModeRow(
                    label: "ON ITS OWN",
                    isSelected: group.product.sellMode == .onItsOwn,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(pageAnimation) {
                            group.product.sellMode = .onItsOwn
                            // Clear package children when package mode is deselected.
                            group.product.bundleChildren = []
                        }
                    }
                )
                SellModeRow(
                    label: "IN A PACKAGE",
                    isSelected: group.product.sellMode == .inPackage,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(pageAnimation) {
                            group.product.sellMode = .inPackage
                            // Clear recipe link when own-sell mode is deselected.
                            group.product.sellingUsesStock = nil
                        }
                    }
                )
                SellModeRow(
                    label: "BOTH",
                    isSelected: group.product.sellMode == .both,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(pageAnimation) {
                            group.product.sellMode = .both
                        }
                    }
                )
            }
        }
    }

    // MARK: - Q2: Recipe link

    private var recipeLinkSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            Text("Does selling one use up your stock?")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                SellModeRow(
                    label: "YES",
                    isSelected: group.product.sellingUsesStock == true,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(pageAnimation) {
                            group.product.sellingUsesStock = true
                        }
                    }
                )
                SellModeRow(
                    label: "NO",
                    isSelected: group.product.sellingUsesStock == false,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(pageAnimation) {
                            group.product.sellingUsesStock = false
                        }
                    }
                )
            }

            // Teach line — verbatim from spec
            Text("// IN OPS: a recipe link — selling draws down inventory")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Q3: Bundle builder

    private var bundleSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {

            Text("What goes in the package?")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if bundleCandidates.isEmpty {
                Text("No other items available.")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(bundleCandidates) { candidate in
                        BundleChildRow(
                            candidate: candidate,
                            bundleChildren: $group.product.bundleChildren
                        )
                    }
                }
            }

            // Teach line — verbatim from spec
            Text("// IN OPS: a Bundle with required + suggested add-ons")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }
}

// MARK: - SellModeRow
//
// ≥48pt option row shared by Q1 and Q2 inside ProductsCard.
// Selected: white-on-surfaceActive + checkmark. Unselected: surfaceInput outline.

private struct SellModeRow: View {

    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: 48)
            .background(
                isSelected
                    ? OPSStyle.Colors.surfaceActive
                    : OPSStyle.Colors.surfaceInput
            )
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(OPSStyle.Animation.hover, value: isSelected)
    }
}

// MARK: - BundleChildRow
//
// One tappable row in the Q3 pick-list. Toggles membership in bundleChildren.
// When selected, shows a REQUIRED · SUGGESTED 2-way chip toggling isRequired.

private struct BundleChildRow: View {

    let candidate: GuidedCapturedItem
    @Binding var bundleChildren: [GuidedBundleChild]

    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    private var isSelected: Bool {
        bundleChildren.contains { $0.capturedItemId == candidate.id }
    }

    private var isRequired: Bool {
        bundleChildren.first { $0.capturedItemId == candidate.id }?.isRequired ?? true
    }

    private var pageAnimation: Animation {
        reducedMotion ? .linear(duration: 0.15) : OPSStyle.Animation.hover
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row — tapping toggles inclusion
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(pageAnimation) {
                    if isSelected {
                        bundleChildren.removeAll { $0.capturedItemId == candidate.id }
                    } else {
                        bundleChildren.append(GuidedBundleChild(capturedItemId: candidate.id, isRequired: true))
                    }
                }
            } label: {
                HStack {
                    Text(candidate.name)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.text)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: 48)
                .background(
                    isSelected
                        ? OPSStyle.Colors.surfaceActive
                        : OPSStyle.Colors.surfaceInput
                )
            }
            .buttonStyle(.plain)

            // REQUIRED · SUGGESTED chip row — only visible when selected
            if isSelected {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    RequiredChip(
                        label: "REQUIRED",
                        isActive: isRequired,
                        onTap: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(pageAnimation) {
                                setRequired(true)
                            }
                        }
                    )
                    RequiredChip(
                        label: "SUGGESTED",
                        isActive: !isRequired,
                        onTap: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(pageAnimation) {
                                setRequired(false)
                            }
                        }
                    )
                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.surfaceActive)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cornerRadius(OPSStyle.Layout.buttonRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(
                    isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.line,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .animation(pageAnimation, value: isSelected)
    }

    private func setRequired(_ required: Bool) {
        if let idx = bundleChildren.firstIndex(where: { $0.capturedItemId == candidate.id }) {
            bundleChildren[idx].isRequired = required
        }
    }
}

// MARK: - RequiredChip
//
// Two-way toggle chip for REQUIRED / SUGGESTED inside BundleChildRow.

private struct RequiredChip: View {
    let label: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(height: 32)
                .background(
                    isActive
                        ? OPSStyle.Colors.line
                        : OPSStyle.Colors.surfaceInput
                )
                .cornerRadius(OPSStyle.Layout.chipRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .stroke(
                            isActive ? Color.white.opacity(0.20) : OPSStyle.Colors.line,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(OPSStyle.Animation.hover, value: isActive)
    }
}

// MARK: - DecimalInputField
//
// Reusable numeric field: decimal pad keyboard, dataValue font, OPSStyle tokens.

private struct DecimalInputField: View {

    let placeholder: String
    @Binding var text: String
    let onChange: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .font(OPSStyle.Typography.dataValue)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .keyboardType(.decimalPad)
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .onChange(of: text) { _ in onChange() }
    }
}

// MARK: - UnitPicker
//
// Compact inline picker for ft / in / yd / m. Defaults to "ft".

private struct UnitPicker: View {

    @Binding var unit: String
    private let units = ["ft", "in", "yd", "m"]

    var body: some View {
        Menu {
            ForEach(units, id: \.self) { u in
                Button(u) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    unit = u
                }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(unit)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(height: OPSStyle.Layout.touchTargetMin)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }
}

// MARK: - ChipGrid

private struct ChipGrid: View {

    let options: [String]
    @Binding var selectedChips: Set<String>
    @Binding var showOtherField: Bool
    @Binding var otherFieldText: String
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Wrap chips — use a simple flow-wrap approach via LazyVGrid with adaptive columns
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 90), spacing: OPSStyle.Layout.spacing2)],
                alignment: .leading,
                spacing: OPSStyle.Layout.spacing2
            ) {
                ForEach(options, id: \.self) { option in
                    ChipButton(
                        label: option,
                        isSelected: selectedChips.contains(option),
                        onTap: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if selectedChips.contains(option) {
                                selectedChips.remove(option)
                                if option == "OTHER" {
                                    showOtherField = false
                                }
                            } else {
                                selectedChips.insert(option)
                                if option == "OTHER" {
                                    showOtherField = true
                                }
                            }
                            onChange()
                        }
                    )
                }
            }

            if showOtherField {
                TextField("Attribute name", text: $otherFieldText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .onChange(of: otherFieldText) { _ in onChange() }
            }
        }
    }
}

// MARK: - ChipButton

private struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text)
                }
                Text(label)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(height: 36)
            .background(isSelected
                ? OPSStyle.Colors.line
                : OPSStyle.Colors.surfaceInput
            )
            .cornerRadius(OPSStyle.Layout.chipRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(
                        isSelected ? Color.white.opacity(0.20) : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(OPSStyle.Animation.hover, value: isSelected)
    }
}

// MARK: - AttributeValueEditor

private struct AttributeValueEditor: View {
    @Binding var attribute: GuidedAttribute
    let prefillValues: [String]

    @State private var didApplyPrefill = false

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// WHAT ARE THE OPTIONS FOR \(attribute.name.uppercased())?")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            VStack(spacing: OPSStyle.Layout.spacing1) {
                ForEach(attribute.values.indices, id: \.self) { idx in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        TextField("Option", text: valueBinding(for: idx))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                            )

                        // Delete row — only show if more than 1 row
                        if attribute.values.count > 1 {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(OPSStyle.Animation.hover) {
                                    attribute.values.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: OPSStyle.Icons.minusCircle)
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Add row button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(OPSStyle.Animation.hover) {
                    attribute.values.append("")
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: OPSStyle.Icons.plusCircle)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    Text("ADD OPTION")
                        .font(OPSStyle.Typography.metadata)
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .buttonStyle(.plain)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .padding(OPSStyle.Layout.spacing3)
        .nestedCard()
        .onAppear { applyPrefillIfNeeded() }
    }

    private func valueBinding(for idx: Int) -> Binding<String> {
        Binding(
            get: { attribute.values.indices.contains(idx) ? attribute.values[idx] : "" },
            set: { newVal in
                if attribute.values.indices.contains(idx) {
                    attribute.values[idx] = newVal
                }
            }
        )
    }

    private func applyPrefillIfNeeded() {
        guard !didApplyPrefill else { return }
        didApplyPrefill = true
        // If the attribute currently has values from the seed, keep them.
        // If it's empty (newly selected chip), prime with one blank row.
        if attribute.values.isEmpty || attribute.values.allSatisfy({ $0.isEmpty }) {
            if !prefillValues.isEmpty {
                attribute.values = prefillValues
            } else if attribute.values.isEmpty {
                attribute.values = [""]
            }
        }
    }
}

// MARK: - StructureChoiceButtonStyle
//
// Large tap-target choice button used in the grouping step.
// Outlined at rest; fills with the given accent on press.

private struct StructureChoiceButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.buttonLabel)
            .textCase(.uppercase)
            .foregroundColor(configuration.isPressed ? .black : accent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(configuration.isPressed ? accent : Color.clear)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(accent, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
    }
}

// MARK: - StructureCTAButtonStyle
//
// 52pt full-width primary CTA for the attributes CONTINUE button.

private struct StructureCTAButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.buttonLabel)
            .textCase(.uppercase)
            .foregroundColor(isEnabled ? .white : OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isEnabled
                    ? OPSStyle.Colors.primaryAccent.opacity(configuration.isPressed ? 0.80 : 1.0)
                    : OPSStyle.Colors.fillNeutralDim
            )
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isEnabled ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.separator,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
    }
}
