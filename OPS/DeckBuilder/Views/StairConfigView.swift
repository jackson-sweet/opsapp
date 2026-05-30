// OPS/OPS/DeckBuilder/Views/StairConfigView.swift

import SwiftUI

struct StairConfigView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var widthText: String = "48"
    @State private var risePerStep: Double = 7.5
    @State private var runPerTread: Double = 10.0
    @State private var treadCountText: String = ""
    @State private var addRailing: Bool = false
    @State private var railingType: RailingType = .parapetWall
    @State private var inlineHeightText: String = ""
    @State private var alignment: StairAlignment = .center
    @State private var offsetText: String = "0"
    /// Per-stair elevation in feet. Bug bfbc4068 — once filled in, the user
    /// must be able to edit it on subsequent passes. Stored on the StairConfig
    /// itself (totalRiseInches) so re-opening the editor pre-fills the value.
    @State private var stairHeightText: String = ""
    /// Bug a7429390 — whether to flip the rendered stair direction onto the
    /// opposite perpendicular. Default off: stairs run away from the deck fill.
    @State private var flipDirection: Bool = false

    /// Total rise in inches.
    /// Priority (bug bfbc4068):
    /// 1. The stair's own stored elevation (StairConfig.totalRiseInches) — what
    ///    the user typed last time, always editable.
    /// 2. The user-edited stairHeightText (in feet) for THIS sheet session.
    /// 3. Per-vertex elevations at the edge endpoints.
    /// 4. Overall deck elevation.
    private var totalRise: Double {
        // 1 + 2 — the per-stair value, either from store or live entry
        if let typedFeet = Double(stairHeightText), typedFeet > 0 {
            return typedFeet * 12
        }

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
            runPerTread: runPerTread,
            treadCountOverride: manualTreadCount
        )
    }

    private var manualTreadCount: Int? {
        let trimmed = treadCountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Total rise — ALWAYS editable so a stair already
                    // configured can be edited on subsequent passes through
                    // this sheet. Bug bfbc4068.
                    riseInfoCard

                    // Width input
                    widthInput

                    // Alignment & offset (only when width < edge length)
                    if needsAlignment {
                        alignmentSection
                    }

                    // Direction toggle — flips the rendered stair onto the
                    // opposite perpendicular when the auto-outward heuristic
                    // is wrong. Bug a7429390.
                    directionSection

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
                if let treadCount = existing.treadCount, treadCount > 0 {
                    treadCountText = "\(treadCount)"
                }
                alignment = existing.alignment
                offsetText = String(format: "%.0f", existing.offset)
                flipDirection = existing.flipDirection
                if let railing = existing.railingConfig {
                    addRailing = true
                    railingType = railing.railingType
                }
                // Bug bfbc4068 — pre-fill stair height so the user can edit it.
                if let storedRiseInches = existing.totalRiseInches, storedRiseInches > 0 {
                    stairHeightText = String(format: "%.1f", storedRiseInches / 12.0)
                } else {
                    // Fall back to overall / per-vertex elevations when this is the
                    // first time the user opens the editor for this stair.
                    let inches = totalRise
                    if inches > 0 {
                        stairHeightText = String(format: "%.1f", inches / 12.0)
                    }
                }
            } else if let edgeLen = edgeLengthInches {
                // Default width = edge length
                widthText = String(format: "%.0f", edgeLen)
                // Pre-fill height from any deck-level elevation if available
                let inches = totalRise
                if inches > 0 {
                    stairHeightText = String(format: "%.1f", inches / 12.0)
                }
            }
        }
    }

    // MARK: - Rise Info

    /// Always-editable rise card. Bug bfbc4068 — once a stair has a height,
    /// it must remain editable on subsequent passes. The card now ALWAYS
    /// shows the editable text field (pre-filled with the current value).
    /// The "Total Rise" readout reflects whatever's currently typed, falling
    /// back to elevation sources beneath it.
    @ViewBuilder
    private var riseInfoCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
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

            // Editable height entry — replaces the read-only display once a
            // stair has been configured. User can change at any time.
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("Stair height")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                TextField("e.g., 3", text: $stairHeightText)
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("feet")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.background)
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)

            // Quick presets
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(["1", "2", "2.5", "3", "4"], id: \.self) { preset in
                    Button {
                        stairHeightText = preset
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

    @ViewBuilder
    private var noElevationWarning: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(OPSStyle.Icons.exclamationmarkTriangle)
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

    // MARK: - Direction Toggle (bug a7429390)

    @ViewBuilder
    private var directionSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Toggle(isOn: $flipDirection) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flip Direction")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("By default stairs run away from the deck. Toggle if they should run the other way.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                }
            }
            .tint(OPSStyle.Colors.primaryAccent)
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
                Text("Tread count")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                TextField("AUTO", text: $treadCountText)
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Button {
                    treadCountText = ""
                } label: {
                    Text("AUTO")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.background)
                        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }
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
            Text(manualTreadCount == nil ? "Auto-Calculated" : "Manual Count")
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
                    ForEach(RailingType.assignableDefaultTypes, id: \.self) { type in
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
        config.flipDirection = flipDirection
        // Persist stair height (bug bfbc4068) so the editor pre-fills next time.
        if let typedFeet = Double(stairHeightText), typedFeet > 0 {
            config.totalRiseInches = typedFeet * 12.0
        } else {
            config.totalRiseInches = totalRise > 0 ? totalRise : nil
        }

        if addRailing {
            config.railingConfig = RailingConfig(
                railingType: railingType,
                maxPostSpacing: railingType.defaultMaxPostSpacing
            )
        }

        viewModel.setStairs(edgeId, config: config)
    }
}
