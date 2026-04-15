// OPS/OPS/DeckBuilder/Views/ElevationInputView.swift

import SwiftUI

struct ElevationInputView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ElevationMode = .overall
    @State private var overallHeightText: String = ""
    @State private var perVertexHeights: [String: String] = [:]
    @FocusState private var focusedField: String?
    @State private var showingARHeight = false
    @State private var arHeightTargetVertexId: String?
    @State private var showModeSwitch = false

    enum ElevationMode: String {
        case overall = "Level (uniform)"
        case perVertex = "Sloped (per-vertex)"
    }

    /// The vertex being edited (if one was selected when opened)
    private var targetVertexId: String? {
        viewModel.selection.selectedVertexIds.first
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let vertexId = targetVertexId {
                        // Single-vertex mode: only edit this vertex's height
                        singleVertexSection(vertexId: vertexId)
                    } else {
                        // No vertex selected — full elevation editor
                        Picker("Elevation Mode", selection: $mode) {
                            Text("Level").tag(ElevationMode.overall)
                            Text("Sloped").tag(ElevationMode.perVertex)
                        }
                        .pickerStyle(.segmented)

                        if mode == .overall {
                            overallSection
                        } else {
                            perVertexSection
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle(targetVertexId != nil ? "Vertex Height" : "Deck Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        applyElevation()
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([targetVertexId != nil ? .fraction(0.35) : .medium])
        .fullScreenCover(isPresented: $showingARHeight) {
            ARHeightMeasureView { heightInches, accuracyPercent in
                let heightFeet = heightInches / 12.0
                if let vertexId = arHeightTargetVertexId {
                    // Per-vertex elevation
                    perVertexHeights[vertexId] = String(format: "%.1f", heightFeet)
                    viewModel.setVertexElevation(vertexId, elevation: heightFeet, source: .ar)
                } else {
                    // Overall elevation
                    overallHeightText = String(format: "%.1f", heightFeet)
                    viewModel.setOverallElevation(heightFeet)
                }
                showingARHeight = false
            }
        }
        .onAppear {
            if let vertexId = targetVertexId {
                // Single-vertex mode — pre-fill from vertex elevation or overall
                if let vertex = viewModel.drawingData.vertex(byId: vertexId),
                   let elev = vertex.elevation {
                    perVertexHeights[vertexId] = String(format: "%.1f", elev)
                } else if let overall = viewModel.drawingData.overallElevation {
                    perVertexHeights[vertexId] = String(format: "%.1f", overall)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    focusedField = vertexId
                }
            } else if let height = viewModel.drawingData.overallElevation {
                overallHeightText = String(format: "%.1f", height)
                mode = .overall
            } else {
                let hasPerVertex = viewModel.drawingData.vertices.contains { $0.elevation != nil }
                mode = hasPerVertex ? .perVertex : .overall
            }

            for vertex in viewModel.drawingData.vertices {
                if let elev = vertex.elevation {
                    perVertexHeights[vertex.id] = String(format: "%.1f", elev)
                }
            }
        }
    }

    // MARK: - Single Vertex

    @ViewBuilder
    private func singleVertexSection(vertexId: String) -> some View {
        let vertexIndex = viewModel.drawingData.vertices.firstIndex(where: { $0.id == vertexId })
        let label = vertexIndex.map { "Corner \($0 + 1)" } ?? "Selected vertex"

        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text(label)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text("Height off ground")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                TextField("e.g., 3", text: Binding(
                    get: { perVertexHeights[vertexId] ?? "" },
                    set: { perVertexHeights[vertexId] = $0 }
                ))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: vertexId)

                Text("feet")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            // AR height button
            Button {
                arHeightTargetVertexId = vertexId
                showingARHeight = true
            } label: {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Measure with AR")
                }
                .font(OPSStyle.Typography.button)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
            }

            // Quick presets
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                ForEach(["2", "2.5", "3", "4", "8"], id: \.self) { preset in
                    Button {
                        perVertexHeights[vertexId] = preset
                    } label: {
                        Text("\(preset)'")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }
            }
        }
    }

    // MARK: - Overall

    @ViewBuilder
    private var overallSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("Deck height off ground")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                TextField("e.g., 2.5", text: $overallHeightText)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: "overall")

                Text("feet")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            // AR height measurement
            Button {
                arHeightTargetVertexId = nil  // nil = overall height
                showingARHeight = true
            } label: {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Record with AR")
                }
                .font(OPSStyle.Typography.button)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
            }

            // Quick presets
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                ForEach(["2'", "2.5'", "3'", "4'", "8'"], id: \.self) { preset in
                    Button {
                        overallHeightText = preset.replacingOccurrences(of: "'", with: "")
                    } label: {
                        Text(preset)
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }
            }
        }
    }

    // MARK: - Per-Vertex

    @ViewBuilder
    private var perVertexSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("Set height at each corner")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(Array(viewModel.drawingData.vertices.enumerated()), id: \.element.id) { index, vertex in
                HStack {
                    Text("Corner \(index + 1)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 80, alignment: .leading)

                    TextField("Height", text: Binding(
                        get: { perVertexHeights[vertex.id] ?? "" },
                        set: { perVertexHeights[vertex.id] = $0 }
                    ))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: vertex.id)

                    Text("ft")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Button {
                        arHeightTargetVertexId = vertex.id
                        showingARHeight = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding(OPSStyle.Layout.spacing2_5)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
            }
        }
    }

    // MARK: - Apply

    private func applyElevation() {
        if let vertexId = targetVertexId {
            // Single-vertex mode: apply just this vertex
            if let heightStr = perVertexHeights[vertexId],
               let height = Double(heightStr) {
                // If overall elevation exists and user is setting per-vertex, clear overall
                if viewModel.drawingData.overallElevation != nil {
                    viewModel.clearOverallElevation()
                }
                viewModel.setVertexElevation(vertexId, elevation: height)
            }
        } else if mode == .overall {
            if let height = Double(overallHeightText) {
                viewModel.setOverallElevation(height)
            }
        } else {
            if viewModel.drawingData.overallElevation != nil {
                viewModel.clearOverallElevation()
            }
            for (vertexId, heightStr) in perVertexHeights {
                if let height = Double(heightStr) {
                    viewModel.setVertexElevation(vertexId, elevation: height)
                }
            }
        }
    }
}
