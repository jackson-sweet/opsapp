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
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("MEASUREMENT SYSTEM")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Picker("", selection: Binding(
                            get: { viewModel.drawingData.config.measurementSystem },
                            set: { viewModel.setMeasurementSystem($0) }
                        )) {
                            Text("Imperial").tag(MeasurementSystem.imperial)
                            Text("Metric").tag(MeasurementSystem.metric)
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("Snapping", isOn: Binding(
                        get: { viewModel.drawingData.config.snappingEnabled },
                        set: { viewModel.setSnappingEnabled($0) }
                    ))
                    .tint(OPSStyle.Colors.text)

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
                                                    ? OPSStyle.Colors.text
                                                    : OPSStyle.Colors.primaryText
                                            )
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 36)
                                            .background(
                                                viewModel.drawingData.config.lengthSnapIncrement == value
                                                    ? OPSStyle.Colors.surfaceActive
                                                    : OPSStyle.Colors.cardBackground
                                            )
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .strokeBorder(
                                                        viewModel.drawingData.config.lengthSnapIncrement == value
                                                            ? OPSStyle.Colors.text
                                                            : Color.clear,
                                                        lineWidth: 1
                                                    )
                                            )
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
                                                    ? OPSStyle.Colors.text
                                                    : OPSStyle.Colors.primaryText
                                            )
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 36)
                                            .background(
                                                viewModel.drawingData.config.angleSnapIncrement == value
                                                    ? OPSStyle.Colors.surfaceActive
                                                    : OPSStyle.Colors.cardBackground
                                            )
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .strokeBorder(
                                                        viewModel.drawingData.config.angleSnapIncrement == value
                                                            ? OPSStyle.Colors.text
                                                            : Color.clear,
                                                        lineWidth: 1
                                                    )
                                            )
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        HStack {
                            Text("Endpoint Snap Radius")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Spacer()
                            Text("\(Int(viewModel.drawingData.config.endpointSnapRadius))pt")
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        Slider(
                            value: Binding(
                                get: { viewModel.drawingData.config.endpointSnapRadius },
                                set: { viewModel.setEndpointSnapRadius($0) }
                            ),
                            in: 10...40,
                            step: 5
                        )
                        .tint(OPSStyle.Colors.text)
                    }
                } header: {
                    Text("MEASUREMENT & SNAPPING")
                }

                Section {
                    Toggle("Grid", isOn: Binding(
                        get: { viewModel.drawingData.config.gridVisible },
                        set: { viewModel.setGridVisible($0) }
                    ))
                    .tint(OPSStyle.Colors.text)
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
                    Toggle("Start listening automatically", isOn: Binding(
                        get: { viewModel.dictateAutoStartEnabled },
                        set: { viewModel.setDictateAutoStartPreference($0) }
                    ))
                    .tint(OPSStyle.Colors.text)
                } header: {
                    Text("DICTATION")
                } footer: {
                    Text("Speed draw opens the mic for each new length. Speak the measurement, tap continue.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(OPSStyle.Colors.background)
            .navigationTitle("Canvas Settings")
            .navigationBarTitleDisplayMode(.inline)
            // No Cancel. Every control here commits and saves the moment it is
            // touched, so a Cancel that neither reverted nor saved was a lie —
            // it dismissed while keeping the change. This is a live settings
            // surface, not a form: Done is the only exit it needs.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        mediumImpact.impactOccurred()
                        viewModel.flushPendingSave()
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Defence in depth for the swipe-to-dismiss exit, which never reaches
        // Done: the coalesced write is still 0.4 s out at that moment, and a
        // force-quit inside that window would drop it.
        .onDisappear {
            viewModel.flushPendingSave()
        }
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
