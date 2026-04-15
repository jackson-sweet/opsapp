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
    @State private var inlineHeightText: String = ""
    @State private var alignment: StairAlignment = .center
    @State private var offsetText: String = "0"

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

    /// Edge length in inches (for defaulting stair width)
    private var edgeLengthInches: Double? {
        guard let edgeId = viewModel.editingEdgeId,
              let edge = viewModel.drawingData.edge(byId: edgeId),
              let dim = edge.dimension else { return nil }
        return dim
    }

    /// Whether stair width is less than edge length (show alignment controls)
    private var needsAlignment: Bool {
        guard let edgeLen = edgeLengthInches,
              let width = Double(widthText) else { return false }
        return width < edgeLen - 1  // 1" tolerance
    }

    /// Left and right gap measurements in inches
    private var gapMeasurements: (left: Double, right: Double)? {
        guard let edgeLen = edgeLengthInches,
              let width = Double(widthText), width < edgeLen else { return nil }
        let offset = Double(offsetText) ?? 0
        let gap = edgeLen - width
        switch alignment {
        case .left:   return (left: offset, right: gap - offset)
        case .center: return (left: gap / 2 + offset, right: gap / 2 - offset)
        case .right:  return (left: gap - offset, right: offset)
        }
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

                    // Alignment & offset (only when width < edge length)
                    if needsAlignment {
                        alignmentSection
                    }

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
                alignment = existing.alignment
                offsetText = String(format: "%.0f", existing.offset)
                if let railing = existing.railingConfig {
                    addRailing = true
                    railingType = railing.railingType
                }
            } else if let edgeLen = edgeLengthInches {
                // Default width = edge length
                widthText = String(format: "%.0f", edgeLen)
            }
        }
    }

    // MARK: - Rise Info

    @ViewBuilder
    private var riseInfoCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("Total Rise")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text(DimensionEngine.formatImperial(totalRise))
                    .font(OPSStyle.Typography.headlineMono)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            Spacer()
            Text("IRC R311.7")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    @ViewBuilder
    private var noElevationWarning: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.exclamationmarkTriangle)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                Text("Deck height required")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            Text("Enter the deck height to calculate treads automatically.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                TextField("e.g., 3", text: $inlineHeightText)
                    .font(OPSStyle.Typography.titleMono)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.decimalPad)
                    .onChange(of: inlineHeightText) { _, newValue in
                        if let height = Double(newValue), height > 0 {
                            viewModel.setOverallElevation(height)
                        }
                    }

                Text("feet")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.background)
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)

            // Quick presets
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(["2", "2.5", "3", "4"], id: \.self) { preset in
                    Button {
                        inlineHeightText = preset
                        if let height = Double(preset) {
                            viewModel.setOverallElevation(height)
                        }
                    } label: {
                        Text("\(preset)'")
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(OPSStyle.Colors.background)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Width Input

    @ViewBuilder
    private var widthInput: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Stair Width")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                TextField("48", text: $widthText)
                    .font(OPSStyle.Typography.titleMono)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.numberPad)

                Text("inches")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)

            // Quick presets
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach([36, 42, 48, 60], id: \.self) { width in
                    Button {
                        widthText = "\(width)"
                    } label: {
                        Text("\(width)\"")
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(OPSStyle.Colors.background)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }
            }
        }
    }

    // MARK: - Alignment & Offset

    @ViewBuilder
    private var alignmentSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("Position Along Edge")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            // Alignment picker
            Picker("Alignment", selection: $alignment) {
                ForEach(StairAlignment.allCases, id: \.self) { align in
                    Text(align.displayName).tag(align)
                }
            }
            .pickerStyle(.segmented)

            // Offset input
            HStack {
                Text("Offset")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                TextField("0", text: $offsetText)
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("inches")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            // Gap measurements
            if let gaps = gapMeasurements {
                HStack {
                    Text("Left gap: \(DimensionEngine.formatImperial(gaps.left))")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text("Right gap: \(DimensionEngine.formatImperial(gaps.right))")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.top, OPSStyle.Layout.spacing1)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Code Parameters

    @ViewBuilder
    private var codeParameters: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("Building Code (IRC R311.7)")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            HStack {
                Text("Rise per step")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(String(format: "%.1f\"", risePerStep))
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Stepper("", value: $risePerStep, in: 7.0...7.75, step: 0.25)
                    .labelsHidden()
                    .frame(width: 100)
            }

            HStack {
                Text("Run per tread")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(String(format: "%.0f\"", runPerTread))
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Stepper("", value: $runPerTread, in: 10.0...12.0, step: 0.5)
                    .labelsHidden()
                    .frame(width: 100)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Calculated Values

    @ViewBuilder
    private func calculatedValues(spec: StairCalculator.StairSpec) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Auto-Calculated")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            calcRow("Treads", value: "\(spec.treadCount)")
            calcRow("Actual rise/step", value: String(format: "%.2f\"", spec.risePerStep))
            calcRow("Total run", value: DimensionEngine.formatImperial(spec.totalRun))
            calcRow("Stringer length", value: DimensionEngine.formatImperial(spec.stringerLength))
            calcRow("Stringers needed", value: "\(spec.stringerCount)")
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.primaryAccent.opacity(0.08))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    @ViewBuilder
    private func calcRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.monoValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    // MARK: - Railing

    @ViewBuilder
    private var railingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Toggle(isOn: $addRailing) {
                Text("Add Railing")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
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
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Apply

    private func applyStairs() {
        guard let edgeId = viewModel.editingEdgeId,
              let spec = stairSpec else { return }

        var config = StairConfig(width: spec.width, risePerStep: risePerStep, runPerTread: runPerTread)
        config.treadCount = spec.treadCount
        config.alignment = alignment
        config.offset = Double(offsetText) ?? 0

        if addRailing {
            config.railingConfig = RailingConfig(
                railingType: railingType,
                maxPostSpacing: railingType.defaultMaxPostSpacing
            )
        }

        viewModel.setStairs(edgeId, config: config)
    }
}
