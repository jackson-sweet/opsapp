// OPS/OPS/DeckBuilder/Views/DeckSettingsSheet.swift

import SwiftUI

struct DeckSettingsSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    private let lengthSnapOptions: [(String, Double)] = [
        ("1\"", 1.0), ("2\"", 2.0), ("3\"", 3.0), ("6\"", 6.0), ("12\"", 12.0)
    ]

    private let angleSnapOptions: [(String, Double)] = [
        ("5°", 5.0), ("10°", 10.0), ("15°", 15.0), ("30°", 30.0), ("45°", 45.0), ("90°", 90.0)
    ]

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
                                    }
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
                                    }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.save()
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
