// OPS/OPS/DeckBuilder/Views/StairConfigView.swift

import SwiftUI

struct StairConfigView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var widthText: String = "48"
    @State private var risePerStep: Double = 7.5
    @State private var runPerTread: Double = 10.0
    @State private var addRailing: Bool = false
    @State private var railingType: RailingType = .picket

    private var totalRise: Double {
        // Get elevation from edge endpoints or overall elevation
        guard let edgeId = viewModel.editingEdgeId,
              let edge = viewModel.drawingData.edge(byId: edgeId) else {
            return (viewModel.drawingData.overallElevation ?? 0) * 12 // feet → inches
        }

        // Try per-vertex elevation at edge endpoints
        let startElev = viewModel.drawingData.vertex(byId: edge.startVertexId)?.elevation
        let endElev = viewModel.drawingData.vertex(byId: edge.endVertexId)?.elevation

        if let se = startElev, let ee = endElev {
            return max(se, ee) * 12 // feet → inches
        }

        return (viewModel.drawingData.overallElevation ?? 0) * 12
    }

    private var stairSpec: StairCalculator.StairSpec? {
        guard let width = Double(widthText), width > 0, totalRise > 0 else { return nil }
        return StairCalculator.calculate(
            totalRise: totalRise,
            width: width,
            risePerStep: risePerStep,
            runPerTread: runPerTread
        )
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Total rise display
                    if totalRise > 0 {
                        riseInfoCard
                    } else {
                        noElevationWarning
                    }

                    // Width input
                    widthInput

                    // Code parameters
                    codeParameters

                    // Calculated values
                    if let spec = stairSpec {
                        calculatedValues(spec: spec)
                    }

                    // Railing toggle
                    railingSection

                    Spacer()
                }
                .padding(20)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("Stair Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyStairs()
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(stairSpec == nil)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let edgeId = viewModel.editingEdgeId,
               let edge = viewModel.drawingData.edge(byId: edgeId),
               let existing = edge.stairConfig {
                widthText = String(format: "%.0f", existing.width)
                risePerStep = existing.risePerStep
                runPerTread = existing.runPerTread
                if let railing = existing.railingConfig {
                    addRailing = true
                    railingType = railing.railingType
                }
            }
        }
    }

    // MARK: - Rise Info

    @ViewBuilder
    private var riseInfoCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Rise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(DimensionEngine.formatImperial(totalRise))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            Spacer()
            Text("IRC R311.7")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
                .cornerRadius(4)
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    @ViewBuilder
    private var noElevationWarning: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            Text("Set deck height first")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text("Go back and set the deck elevation to auto-calculate treads.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Width Input

    @ViewBuilder
    private var widthInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stair Width")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                TextField("48", text: $widthText)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .keyboardType(.numberPad)

                Text("inches")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(12)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)

            // Quick presets
            HStack(spacing: 8) {
                ForEach([36, 42, 48, 60], id: \.self) { width in
                    Button {
                        widthText = "\(width)"
                    } label: {
                        Text("\(width)\"")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(OPSStyle.Colors.background)
                            .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - Code Parameters

    @ViewBuilder
    private var codeParameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Building Code (IRC R311.7)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            HStack {
                Text("Rise per step")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(String(format: "%.1f\"", risePerStep))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Stepper("", value: $risePerStep, in: 7.0...7.75, step: 0.25)
                    .labelsHidden()
                    .frame(width: 100)
            }

            HStack {
                Text("Run per tread")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(String(format: "%.0f\"", runPerTread))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Stepper("", value: $runPerTread, in: 10.0...12.0, step: 0.5)
                    .labelsHidden()
                    .frame(width: 100)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Calculated Values

    @ViewBuilder
    private func calculatedValues(spec: StairCalculator.StairSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Auto-Calculated")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            calcRow("Treads", value: "\(spec.treadCount)")
            calcRow("Actual rise/step", value: String(format: "%.2f\"", spec.risePerStep))
            calcRow("Total run", value: DimensionEngine.formatImperial(spec.totalRun))
            calcRow("Stringer length", value: DimensionEngine.formatImperial(spec.stringerLength))
            calcRow("Stringers needed", value: "\(spec.stringerCount)")
        }
        .padding(16)
        .background(OPSStyle.Colors.primaryAccent.opacity(0.08))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    @ViewBuilder
    private func calcRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    // MARK: - Railing

    @ViewBuilder
    private var railingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $addRailing) {
                Text("Add Railing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .tint(OPSStyle.Colors.primaryAccent)

            if addRailing {
                Picker("Railing Type", selection: $railingType) {
                    ForEach(RailingType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Apply

    private func applyStairs() {
        guard let edgeId = viewModel.editingEdgeId,
              let spec = stairSpec else { return }

        var config = StairConfig(width: spec.width, risePerStep: risePerStep, runPerTread: runPerTread)
        config.treadCount = spec.treadCount

        if addRailing {
            config.railingConfig = RailingConfig(
                railingType: railingType,
                maxPostSpacing: railingType.defaultMaxPostSpacing
            )
        }

        viewModel.setStairs(edgeId, config: config)
    }
}
