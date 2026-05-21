// OPS/OPS/DeckBuilder/Views/DeckSettingsSheet.swift

import SwiftData
import SwiftUI

struct DeckSettingsSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @Query private var catalogItems: [CatalogItem]
    @Query private var catalogVariants: [CatalogVariant]

    private let lengthSnapOptions: [(String, Double)] = [
        ("1\"", 1.0), ("2\"", 2.0), ("3\"", 3.0), ("6\"", 6.0), ("12\"", 12.0)
    ]

    private let angleSnapOptions: [(String, Double)] = [
        ("5°", 5.0), ("10°", 10.0), ("15°", 15.0), ("30°", 30.0), ("45°", 45.0), ("90°", 90.0)
    ]

    /// Haptic on apply so user feels the settings commit
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    private var vinylProductChoices: [VinylSettingsProductChoice] {
        let activeVariantsByItem = Dictionary(grouping: catalogVariants.filter { variant in
            variant.companyId == viewModel.deckDesign.companyId
                && variant.isActive
                && variant.deletedAt == nil
        }, by: \.catalogItemId)

        return catalogItems
            .filter { item in
                item.companyId == viewModel.deckDesign.companyId
                    && item.isActive
                    && item.deletedAt == nil
                    && !(activeVariantsByItem[item.id] ?? []).isEmpty
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { item in
                VinylSettingsProductChoice(
                    item: item,
                    variantCount: activeVariantsByItem[item.id]?.count ?? 0
                )
            }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Snapping", isOn: $viewModel.drawingData.config.snappingEnabled)
                        .tint(OPSStyle.Colors.primaryAccent)

                    if viewModel.drawingData.config.snappingEnabled {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("LENGTH SNAP")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                ForEach(lengthSnapOptions, id: \.1) { label, value in
                                    Button {
                                        viewModel.drawingData.config.lengthSnapIncrement = value
                                        viewModel.save()
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text(label)
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(
                                                viewModel.drawingData.config.lengthSnapIncrement == value
                                                    ? OPSStyle.Colors.buttonText
                                                    : OPSStyle.Colors.primaryText
                                            )
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 36)
                                            .background(
                                                viewModel.drawingData.config.lengthSnapIncrement == value
                                                    ? OPSStyle.Colors.primaryAccent
                                                    : OPSStyle.Colors.cardBackground
                                            )
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("ANGLE SNAP")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                ForEach(angleSnapOptions, id: \.1) { label, value in
                                    Button {
                                        viewModel.drawingData.config.angleSnapIncrement = value
                                        viewModel.save()
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text(label)
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(
                                                viewModel.drawingData.config.angleSnapIncrement == value
                                                    ? OPSStyle.Colors.buttonText
                                                    : OPSStyle.Colors.primaryText
                                            )
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 36)
                                            .background(
                                                viewModel.drawingData.config.angleSnapIncrement == value
                                                    ? OPSStyle.Colors.primaryAccent
                                                    : OPSStyle.Colors.cardBackground
                                            )
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                } header: {
                    Text("SNAPPING")
                }

                Section {
                    Toggle("Grid", isOn: $viewModel.drawingData.config.gridVisible)
                        .tint(OPSStyle.Colors.primaryAccent)

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("MEASUREMENT SYSTEM")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Picker("", selection: $viewModel.drawingData.config.measurementSystem) {
                            Text("Imperial").tag(MeasurementSystem.imperial)
                            Text("Metric").tag(MeasurementSystem.metric)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("DISPLAY")
                }

                Section {
                    Picker("Vinyl product", selection: Binding(
                        get: { viewModel.drawingData.config.vinylCatalogItemId ?? "" },
                        set: { viewModel.setVinylCatalogItemId($0) }
                    )) {
                        Text("None").tag("")
                        ForEach(vinylProductChoices) { choice in
                            Text(choice.displayName).tag(choice.id)
                        }
                    }

                    Button {
                        viewModel.vinylOrderSurfaceScope = .allSurfaces
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            viewModel.showingVinylOrderSheet = true
                        }
                    } label: {
                        Label("ORDER ALL VINYL", systemImage: "shippingbox")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                } header: {
                    Text("VINYL")
                } footer: {
                    Text("PRODUCT SETS THE COLOR LIST. NONE KEEPS FIELD TEXT.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Section {
                    Toggle("Autosave every 2 minutes", isOn: Binding(
                        get: { viewModel.autosaveEnabled },
                        set: { viewModel.setAutosavePreference($0) }
                    ))
                    .tint(OPSStyle.Colors.primaryAccent)
                } header: {
                    Text("AUTOSAVE")
                } footer: {
                    Text("Saves your changes silently so a crash or quit doesn't lose work.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Section {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        HStack {
                            Text("Endpoint Snap Radius")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Spacer()
                            Text("\(Int(viewModel.drawingData.config.endpointSnapRadius))pt")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        Slider(
                            value: $viewModel.drawingData.config.endpointSnapRadius,
                            in: 10...40,
                            step: 5
                        )
                        .tint(OPSStyle.Colors.primaryAccent)
                    }
                } header: {
                    Text("ADVANCED")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(OPSStyle.Colors.background)
            .navigationTitle("Canvas Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        mediumImpact.impactOccurred()
                        viewModel.save()
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct VinylSettingsProductChoice: Identifiable {
    let item: CatalogItem
    let variantCount: Int

    var id: String { item.id }

    var displayName: String {
        "\(item.name) / \(variantCount) VARIANTS"
    }
}
