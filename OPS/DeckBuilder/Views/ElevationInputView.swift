// OPS/OPS/DeckBuilder/Views/ElevationInputView.swift

import SwiftUI

/// Height entry for exactly one thing: the selected corner when a vertex is
/// selected, otherwise the SELECTED LEVEL on a multi-level drawing, otherwise
/// the whole deck. The sheet names its target in the title and never writes
/// outside it — the previous version wrote the deck-wide `overallElevation`
/// even on multi-level drawings, which re-based every level that lacked an
/// explicit height (the "HEIGHT overwrites everything" bug).
struct ElevationInputView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    enum ElevationMode: String {
        case flat
        case sloped
    }

    @State private var mode: ElevationMode = .flat
    @State private var feet: Int = 2
    @State private var inches: Int = 6
    @State private var perVertexHeights: [String: String] = [:]
    @State private var showingARHeight = false
    @State private var arHeightTargetVertexId: String?
    /// The dial value an AR measure filled in, if any. At apply time the
    /// height is attributed to AR only when the dials still hold this exact
    /// value — any manual respin reverts attribution to `.manual`.
    @State private var arFilledComponents: (feet: Int, inches: Int)?
    /// Sloped rows filled by AR, same rule keyed by the row's current text.
    @State private var arFilledRowValues: [String: String] = [:]
    @State private var didLoad = false

    // MARK: - Context

    /// The vertex being edited (if one was selected when opened).
    private var targetVertexId: String? {
        viewModel.selection.selectedVertexIds.first
    }

    /// Corners of the active drawing context — the selected level's on a
    /// multi-level drawing (the top-level array is empty there).
    private var contextVertices: [DeckVertex] {
        if viewModel.isMultiLevel, let level = viewModel.activeLevel { return level.vertices }
        return viewModel.drawingData.vertices
    }

    private var activeLevel: DeckLevel? {
        viewModel.isMultiLevel ? viewModel.activeLevel : nil
    }

    private var navigationTitle: String {
        if targetVertexId != nil { return "Corner Height" }
        if let level = activeLevel { return "\(level.name) Height" }
        return "Deck Height"
    }

    /// The target's current effective height in feet — explicit if set,
    /// otherwise what the renderer resolves — so the dials always open on
    /// reality instead of zero.
    private var currentHeightFeet: Double {
        if let vertexId = targetVertexId {
            if let vertex = viewModel.findVertex(byId: vertexId), let elevation = vertex.elevation {
                return elevation
            }
        }
        if let level = activeLevel {
            return viewModel.drawingData.renderElevationFeet(for: level, levelIndex: viewModel.activeLevelIndex)
        }
        return viewModel.drawingData.renderElevationFeetSingleLevel
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3_5) {
                    if let vertexId = targetVertexId {
                        singleVertexSection(vertexId: vertexId)
                    } else {
                        if let level = activeLevel {
                            levelChip(level)
                        }

                        Picker("Height Mode", selection: $mode) {
                            Text("Flat").tag(ElevationMode.flat)
                            Text("Sloped").tag(ElevationMode.sloped)
                        }
                        .pickerStyle(.segmented)

                        if mode == .flat {
                            flatSection
                        } else {
                            slopedSection
                        }
                    }

                    Spacer()
                }
                .padding(OPSStyle.Layout.spacing3_5)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        applyElevation()
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([targetVertexId != nil ? .fraction(0.45) : .medium])
        .fullScreenCover(isPresented: $showingARHeight) {
            ARHeightMeasureView { heightInches, _ in
                let heightFeet = heightInches / 12.0
                if let vertexId = arHeightTargetVertexId, targetVertexId == nil {
                    let text = String(format: "%.1f", heightFeet)
                    perVertexHeights[vertexId] = text
                    arFilledRowValues[vertexId] = text
                } else {
                    let components = DeckFeetInchesWheels.components(fromFeet: heightFeet)
                    feet = components.feet
                    inches = components.inches
                    arFilledComponents = components
                }
                showingARHeight = false
            }
        }
        .onAppear(perform: loadCurrent)
    }

    // MARK: - Level chip

    private func levelChip(_ level: DeckLevel) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Circle()
                .fill(level.displayColor.swiftUIColor)
                .frame(width: OPSStyle.Layout.Indicator.dotMD, height: OPSStyle.Layout.Indicator.dotMD)
            Text(level.name)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
    }

    // MARK: - Flat

    private var flatSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text(activeLevel != nil ? "Height off ground for this level" : "Deck height off ground")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            DeckFeetInchesWheels(feet: $feet, inches: $inches)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(flatPresets, id: \.label) { preset in
                    Button {
                        feet = preset.feet
                        inches = preset.inches
                    } label: {
                        Text(preset.label)
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }

                Spacer()

                Button {
                    arHeightTargetVertexId = nil
                    showingARHeight = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "camera.viewfinder")
                        Text("AR")
                    }
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }
            }
        }
    }

    private var flatPresets: [(label: String, feet: Int, inches: Int)] {
        [("2'", 2, 0), ("2' 6\"", 2, 6), ("3'", 3, 0), ("4'", 4, 0), ("8'", 8, 0)]
    }

    // MARK: - Sloped

    private var slopedSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("Set height at each corner")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(Array(contextVertices.enumerated()), id: \.element.id) { index, vertex in
                HStack {
                    Text("Corner \(index + 1)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 80, alignment: .leading)

                    TextField("Height", text: Binding(
                        get: { perVertexHeights[vertex.id] ?? "" },
                        set: { perVertexHeights[vertex.id] = $0 }
                    ))
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.decimalPad)

                    Text("ft")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Button {
                        arHeightTargetVertexId = vertex.id
                        showingARHeight = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
            }
        }
    }

    // MARK: - Single Vertex

    private func singleVertexSection(vertexId: String) -> some View {
        let vertexIndex = contextVertices.firstIndex(where: { $0.id == vertexId })
        let label = vertexIndex.map { "Corner \($0 + 1)" } ?? "Selected corner"

        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let level = activeLevel {
                    Circle()
                        .fill(level.displayColor.swiftUIColor)
                        .frame(width: OPSStyle.Layout.Indicator.dotMD, height: OPSStyle.Layout.Indicator.dotMD)
                }
                Text(label)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            Text("Height off ground")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            DeckFeetInchesWheels(feet: $feet, inches: $inches)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(flatPresets, id: \.label) { preset in
                    Button {
                        feet = preset.feet
                        inches = preset.inches
                    } label: {
                        Text(preset.label)
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }

                Spacer()

                Button {
                    arHeightTargetVertexId = vertexId
                    showingARHeight = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "camera.viewfinder")
                        Text("AR")
                    }
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }
            }
        }
    }

    // MARK: - Load / Apply

    private func loadCurrent() {
        guard !didLoad else { return }
        didLoad = true

        if targetVertexId != nil {
            let components = DeckFeetInchesWheels.components(fromFeet: currentHeightFeet)
            feet = components.feet
            inches = components.inches
            // AR result routes to the selected corner unless a sloped row
            // re-targets it.
            arHeightTargetVertexId = targetVertexId
            return
        }

        let hasUniform: Bool
        if let level = activeLevel {
            hasUniform = level.elevation != nil
        } else {
            hasUniform = viewModel.drawingData.overallElevation != nil
        }
        let hasPerVertex = contextVertices.contains { $0.elevation != nil }
        mode = (!hasUniform && hasPerVertex) ? .sloped : .flat

        let components = DeckFeetInchesWheels.components(fromFeet: currentHeightFeet)
        feet = components.feet
        inches = components.inches

        for vertex in contextVertices {
            if let elevation = vertex.elevation {
                perVertexHeights[vertex.id] = String(format: "%.1f", elevation)
            }
        }
    }

    /// True while the dials still hold the exact value an AR measure set.
    private var dialsHoldARMeasure: Bool {
        guard let ar = arFilledComponents else { return false }
        return ar.feet == feet && ar.inches == inches
    }

    private func applyElevation() {
        if let vertexId = targetVertexId {
            let height = DeckFeetInchesWheels.feetValue(feet: feet, inches: inches)
            viewModel.setVertexHeightBreakingUniform(
                vertexId,
                elevation: height,
                source: dialsHoldARMeasure ? .ar : .manual
            )
            return
        }

        if mode == .flat {
            let height = DeckFeetInchesWheels.feetValue(feet: feet, inches: inches)
            if viewModel.isMultiLevel {
                viewModel.setLevelElevation(at: viewModel.activeLevelIndex, elevation: height)
            } else {
                viewModel.applyUniformDeckElevation(height)
            }
            return
        }

        var heights: [String: Double] = [:]
        var allFromAR = !perVertexHeights.isEmpty
        for (vertexId, text) in perVertexHeights {
            if let value = Double(text), value >= 0 {
                heights[vertexId] = value
                if arFilledRowValues[vertexId] != text { allFromAR = false }
            }
        }
        guard !heights.isEmpty else { return }
        let source: ElevationSource = allFromAR ? .ar : .manual
        if viewModel.isMultiLevel {
            viewModel.applyLevelSlopedElevations(at: viewModel.activeLevelIndex, heights: heights, source: source)
        } else {
            viewModel.applySlopedDeckElevations(heights: heights, source: source)
        }
    }
}
