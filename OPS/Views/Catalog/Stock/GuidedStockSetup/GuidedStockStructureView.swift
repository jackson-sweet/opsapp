import SwiftUI

// MARK: - GuidedStockStructureView
//
// STRUCTURE stage — the conversational grouping + attributes engine (§7.2a/2b).
// Owns its own sub-flow state, BACK affordance, and CONTINUE/finalize CTA.
// GuidedStockSetupFlow suppresses its generic bottom bar for this stage.
//
// Internal step machine:
//   substep .grouping  — iterates every GuidedStructuredGroup via groupIndex cursor;
//                        resolves multi-member merges and single-item "versions?" splits.
//   substep .attributes — iterates only the versioned (isSingleItem=false) groups via
//                         attrIndex cursor; collects attribute names + values.
//
// P4/P5 can append new cases to `Substep` and plug into the finalize/advance logic
// without touching the existing substep implementations.

struct GuidedStockStructureView: View {

    @ObservedObject var model: GuidedStockSetupModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    // MARK: - Internal sub-step state

    private enum Substep: Equatable {
        case grouping
        case attributes
    }

    @State private var substep: Substep = .grouping
    @State private var groupIndex: Int = 0   // cursor through model.groups (grouping phase)
    @State private var attrIndex: Int = 0    // cursor through versioned groups (attributes phase)

    // MARK: - Computed helpers

    private var currentGroup: GuidedStructuredGroup? {
        guard model.groups.indices.contains(groupIndex) else { return nil }
        return model.groups[groupIndex]
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
            // All grouping decisions done. Move to attributes if any versioned groups exist.
            if versionedGroupIndices.isEmpty {
                finalize()
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

    // MARK: - Binding helper

    private func binding(for groupIdx: Int) -> Binding<GuidedStructuredGroup> {
        Binding(
            get: { model.groups[groupIdx] },
            set: { model.groups[groupIdx] = $0 }
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
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                Text(label)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(height: 36)
            .background(isSelected
                ? OPSStyle.Colors.primaryAccent.opacity(0.12)
                : OPSStyle.Colors.surfaceInput
            )
            .cornerRadius(OPSStyle.Layout.chipRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(
                        isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.40) : OPSStyle.Colors.line,
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
        .nestedCard()
        .padding(OPSStyle.Layout.spacing2)
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
                    : OPSStyle.Colors.cardBackground
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
