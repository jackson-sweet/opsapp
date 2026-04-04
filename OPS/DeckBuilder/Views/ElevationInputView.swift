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

    enum ElevationMode: String {
        case overall = "Level (uniform)"
        case perVertex = "Sloped (per-vertex)"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Mode toggle
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

                    Spacer()
                }
                .padding(20)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("Deck Height")
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
        .presentationDetents([.medium])
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
            if let height = viewModel.drawingData.overallElevation {
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

    // MARK: - Overall

    @ViewBuilder
    private var overallSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deck height off ground")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                TextField("e.g., 2.5", text: $overallHeightText)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: "overall")

                Text("feet")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(16)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
            }

            // Quick presets
            HStack(spacing: 12) {
                ForEach(["2'", "2.5'", "3'", "4'", "8'"], id: \.self) { preset in
                    Button {
                        overallHeightText = preset.replacingOccurrences(of: "'", with: "")
                    } label: {
                        Text(preset)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Set height at each corner")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(Array(viewModel.drawingData.vertices.enumerated()), id: \.element.id) { index, vertex in
                HStack {
                    Text("Corner \(index + 1)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 80, alignment: .leading)

                    TextField("Height", text: Binding(
                        get: { perVertexHeights[vertex.id] ?? "" },
                        set: { perVertexHeights[vertex.id] = $0 }
                    ))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: vertex.id)

                    Text("ft")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Button {
                        arHeightTargetVertexId = vertex.id
                        showingARHeight = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding(12)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
            }
        }
    }

    // MARK: - Apply

    private func applyElevation() {
        if mode == .overall {
            if let height = Double(overallHeightText) {
                viewModel.setOverallElevation(height)
            }
        } else {
            for (vertexId, heightStr) in perVertexHeights {
                if let height = Double(heightStr) {
                    viewModel.setVertexElevation(vertexId, elevation: height)
                }
            }
        }
    }
}
