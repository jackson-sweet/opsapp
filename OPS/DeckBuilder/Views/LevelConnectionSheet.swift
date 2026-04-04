// OPS/OPS/DeckBuilder/Views/LevelConnectionSheet.swift

import SwiftUI

struct LevelConnectionSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var upperLevelIndex: Int = 0
    @State private var lowerLevelIndex: Int = 1
    @State private var selectedEdgeId: String?
    @State private var stairWidthInches: Double = 48  // 4 feet default
    @State private var elevationInputText: String = ""
    @State private var elevationInputLevelIndex: Int?

    private var levels: [DeckLevel] { viewModel.drawingData.levels }

    private var upperLevel: DeckLevel? {
        guard upperLevelIndex < levels.count else { return nil }
        return levels[upperLevelIndex]
    }

    private var lowerLevel: DeckLevel? {
        guard lowerLevelIndex < levels.count else { return nil }
        return levels[lowerLevelIndex]
    }

    /// Elevation difference in inches (upper - lower)
    private var elevationDiffInches: Double? {
        guard let upper = upperLevel, let lower = lowerLevel,
              let upperElev = upper.elevation, let lowerElev = lower.elevation else { return nil }
        return (upperElev - lowerElev) * 12.0
    }

    private var stairSpec: StairCalculator.StairSpec? {
        guard let diff = elevationDiffInches, diff > 0 else { return nil }
        return StairCalculator.calculate(totalRise: diff, width: stairWidthInches)
    }

    private var canAdd: Bool {
        guard let diff = elevationDiffInches, diff > 0,
              selectedEdgeId != nil else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Level selectors
                    levelPickerSection

                    // Elevation warning with inline input
                    if let upper = upperLevel, upper.elevation == nil {
                        elevationInputSection(levelName: upper.name, levelIndex: upperLevelIndex)
                    } else if let lower = lowerLevel, lower.elevation == nil {
                        elevationInputSection(levelName: lower.name, levelIndex: lowerLevelIndex)
                    }

                    // Edge picker (only if upper level has edges)
                    if let upper = upperLevel, !upper.edges.isEmpty {
                        edgePickerSection(level: upper)
                    }

                    // Stair width input
                    stairWidthSection

                    // Auto-calculated specs
                    if let spec = stairSpec {
                        stairSpecSection(spec: spec)
                    }

                    // Add button
                    Button {
                        addConnection()
                    } label: {
                        Text("Add Stairs")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(canAdd ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.3))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .disabled(!canAdd)
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("Connect Levels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .onAppear {
            autoSelectLevels()
        }
    }

    // MARK: - Level Picker

    private var levelPickerSection: some View {
        VStack(spacing: 12) {
            // From (higher)
            HStack {
                Text("From (higher)")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Picker("Upper Level", selection: $upperLevelIndex) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                        HStack {
                            Circle().fill(level.displayColor.swiftUIColor).frame(width: 8, height: 8)
                            Text(level.name)
                            if let elev = level.elevation {
                                Text("(\(formatElevation(elev)))")
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                        .tag(index)
                    }
                }
                .tint(OPSStyle.Colors.primaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            // To (lower)
            HStack {
                Text("To (lower)")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Picker("Lower Level", selection: $lowerLevelIndex) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                        if index != upperLevelIndex {
                            HStack {
                                Circle().fill(level.displayColor.swiftUIColor).frame(width: 8, height: 8)
                                Text(level.name)
                                if let elev = level.elevation {
                                    Text("(\(formatElevation(elev)))")
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                            }
                            .tag(index)
                        }
                    }
                }
                .tint(OPSStyle.Colors.primaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Edge Picker

    private func edgePickerSection(level: DeckLevel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attach stairs to edge")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(level.edges, id: \.id) { edge in
                let isSelected = selectedEdgeId == edge.id
                Button {
                    selectedEdgeId = edge.id
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)

                        Text(edgeLabel(edge, level: level))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        if let dim = edge.dimension {
                            Text(DimensionEngine.formatImperial(dim))
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.1) : OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
    }

    // MARK: - Stair Width

    private var stairWidthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stair width")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                Text(DimensionEngine.formatImperial(stairWidthInches))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                // Quick presets
                ForEach([36.0, 48.0, 60.0], id: \.self) { width in
                    Button {
                        stairWidthInches = width
                    } label: {
                        Text(DimensionEngine.formatImperial(width))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(stairWidthInches == width ? .white : OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(stairWidthInches == width ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.1))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Stair Spec Display

    private func stairSpecSection(spec: StairCalculator.StairSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calculated stairs")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 8) {
                specRow("Elevation difference", value: formatInches(spec.totalRise))
                specRow("Treads", value: "\(spec.treadCount)")
                specRow("Rise per step", value: String(format: "%.1f\"", spec.risePerStep))
                specRow("Total run", value: formatInches(spec.totalRun))
                specRow("Stringers", value: "\(spec.stringerCount)")
                specRow("Stringer length", value: formatInches(spec.stringerLength))
            }
            .padding(12)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private func specRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    // MARK: - Elevation Input

    private func elevationInputSection(levelName: String, levelIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                Text("Set elevation for \(levelName)")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            HStack(spacing: 8) {
                TextField("Height in feet", text: $elevationInputText)
                    .keyboardType(.decimalPad)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)

                Text("ft")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Button {
                    guard let feet = Double(elevationInputText), feet > 0 else { return }
                    viewModel.setLevelElevation(at: levelIndex, elevation: feet)
                    elevationInputText = ""
                } label: {
                    Text("Set")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
        .padding(12)
        .background(OPSStyle.Colors.warningStatus.opacity(0.1))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Actions

    private func addConnection() {
        guard let upper = upperLevel, let lower = lowerLevel,
              let edgeId = selectedEdgeId else { return }
        viewModel.connectLevels(
            upperLevelId: upper.id,
            lowerLevelId: lower.id,
            upperEdgeId: edgeId,
            stairWidth: stairWidthInches
        )
        dismiss()
    }

    private func autoSelectLevels() {
        // Sort by elevation descending — highest becomes "from", lowest becomes "to"
        let sorted = levels.enumerated()
            .sorted { ($0.element.elevation ?? 0) > ($1.element.elevation ?? 0) }
        if let first = sorted.first { upperLevelIndex = first.offset }
        if sorted.count > 1 { lowerLevelIndex = sorted[1].offset }

        // Auto-select first edge of upper level
        if let upper = upperLevel, let firstEdge = upper.edges.first {
            selectedEdgeId = firstEdge.id
        }
    }

    // MARK: - Formatting

    private func edgeLabel(_ edge: DeckEdge, level: DeckLevel) -> String {
        let startIdx = level.vertices.firstIndex(where: { $0.id == edge.startVertexId }).map { $0 + 1 } ?? 0
        let endIdx = level.vertices.firstIndex(where: { $0.id == edge.endVertexId }).map { $0 + 1 } ?? 0
        let typeLabel = edge.edgeType == .houseEdge ? " (house)" : ""
        return "Edge \(startIdx)\u{2013}\(endIdx)\(typeLabel)"
    }

    private func formatElevation(_ feet: Double) -> String {
        let wholeFeet = Int(feet)
        let inches = Int((feet - Double(wholeFeet)) * 12)
        if inches == 0 { return "\(wholeFeet)'" }
        return "\(wholeFeet)' \(inches)\""
    }

    private func formatInches(_ inches: Double) -> String {
        DimensionEngine.formatImperial(inches)
    }
}
