//
//  CatalogBulkVariantChangeStep.swift
//  OPS
//

import SwiftUI

struct CatalogBulkVariantChangeStep: View {
    @ObservedObject var model: CatalogBulkVariantExpansionModel
    let optionSuggestions: [String]
    let existingValueSuggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("DEFINE THE CHANGE")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                Text("Set one option across every selected family. OPS builds the matching combinations.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                OPSProfileInput(
                    label: "OPTION",
                    text: Binding(
                        get: { model.axisName },
                        set: model.setAxisName
                    ),
                    placeholder: "Top profile"
                )
                if !optionSuggestions.isEmpty {
                    suggestionRow(
                        label: "CURRENT OPTIONS",
                        values: optionSuggestions,
                        selected: model.axisName,
                        action: model.setAxisName
                    )
                }
            }

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                OPSProfileInput(
                    label: "EXISTING VALUE",
                    text: Binding(
                        get: { model.existingValue },
                        set: model.setExistingValue
                    ),
                    placeholder: "Round top"
                )
                Text("This labels what is already in stock. Existing quantities and SKUs stay unchanged.")
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .fixedSize(horizontal: false, vertical: true)
                if !existingValueSuggestions.isEmpty {
                    suggestionRow(
                        label: "CURRENT VALUES",
                        values: existingValueSuggestions,
                        selected: model.existingValue,
                        action: model.setExistingValue
                    )
                }
            }

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("NEW VALUES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.text3)

                ForEach(model.newValues) { value in
                    HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                        TextField(
                            "Flat top",
                            text: Binding(
                                get: { value.text },
                                set: { model.setNewValue($0, at: value.id) }
                            )
                        )
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.surfaceInput)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                        }
                        .accessibilityLabel("New option value")

                        Button {
                            model.removeNewValue(id: value.id)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: model.newValues.count == 1 ? OPSStyle.Icons.close : OPSStyle.Icons.trash)
                        }
                        .opsIconButtonStyle(
                            backgroundColor: OPSStyle.Colors.surfaceInput,
                            foregroundColor: OPSStyle.Colors.text3
                        )
                        .accessibilityLabel(model.newValues.count == 1 ? "Clear new value" : "Remove new value")
                    }
                }

                Button {
                    model.addNewValue()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("ADD ANOTHER VALUE", systemImage: OPSStyle.Icons.plus)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(model.newValues.count >= 20 ? OPSStyle.Colors.textMute : OPSStyle.Colors.text2)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(.plain)
                .disabled(model.newValues.count >= 20)

                Text("OPS creates matching variants with zero stock and blank SKUs.")
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .fixedSize(horizontal: false, vertical: true)

                if let message = model.changeValidationMessage, model.hasMeaningfulDraft {
                    HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: OPSStyle.Icons.exclamationmarkCircleFill)
                            .foregroundColor(OPSStyle.Colors.roseTextM)
                        Text(message)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.roseTextM)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Correction needed. \(message)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestionRow(
        label: String,
        values: [String],
        selected: String,
        action: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(values, id: \.self) { value in
                        let isSelected = normalized(value) == normalized(selected)
                        Button(value.uppercased()) {
                            action(value)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .background(isSelected ? OPSStyle.Colors.surfaceSelected : OPSStyle.Colors.surfaceInput)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
                        .overlay {
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .stroke(
                                    isSelected ? OPSStyle.Colors.activeChipBorder : OPSStyle.Colors.line,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        }
                    }
                }
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
