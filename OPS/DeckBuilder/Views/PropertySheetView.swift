// OPS/OPS/DeckBuilder/Views/PropertySheetView.swift

import SwiftUI

struct PropertySheetView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.selection.hasEdges {
                        edgeProperties
                    }

                    if viewModel.selection.hasVertices {
                        vertexProperties
                    }

                    if viewModel.selection.selectedFootprint {
                        footprintProperties
                    }
                }
                .padding(20)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("Properties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: viewModel.activeLevelIndex) { _ in
            // Dismiss when level switches — edge/vertex references may belong to the previous level
            dismiss()
        }
    }

    // MARK: - Edge Properties

    @ViewBuilder
    private var edgeProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Edge Properties", icon: "line.diagonal")

            // Edge type picker
            ForEach(Array(viewModel.selection.selectedEdgeIds), id: \.self) { edgeId in
                if let edge = viewModel.drawingData.edge(byId: edgeId) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Dimension
                        if let dim = edge.dimension {
                            HStack {
                                Text("Length")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Spacer()
                                Text(DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem))
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                        }

                        // Edge type
                        HStack {
                            Text("Type")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { edge.edgeType },
                                set: { viewModel.setEdgeType(edgeId, type: $0) }
                            )) {
                                Text("Deck Edge").tag(EdgeType.deckEdge)
                                Text("House Edge").tag(EdgeType.houseEdge)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }

                        Divider().background(OPSStyle.Colors.separator)

                        // Railing
                        railingSection(edgeId: edgeId, edge: edge)

                        Divider().background(OPSStyle.Colors.separator)

                        // Stairs
                        stairSection(edgeId: edgeId, edge: edge)
                    }
                    .padding(16)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }

    @ViewBuilder
    private func railingSection(edgeId: String, edge: DeckEdge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Railing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if edge.railingConfig != nil {
                    Button("Remove") {
                        viewModel.setRailing(edgeId, config: nil)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                }
            }

            if let railing = edge.railingConfig {
                Text(railing.railingType.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                // Post spacing
                HStack {
                    Text("Max post spacing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(DimensionEngine.formatImperial(railing.maxPostSpacing))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }

                // Post count
                if let dim = edge.dimension {
                    let posts = DimensionEngine.postCount(edgeLengthInches: dim, maxSpacing: railing.maxPostSpacing)
                    HStack {
                        Text("Posts needed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text("\(posts)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            } else {
                // Railing type picker
                HStack(spacing: 8) {
                    ForEach(RailingType.allCases, id: \.self) { type in
                        Button {
                            let config = RailingConfig(
                                railingType: type,
                                maxPostSpacing: type.defaultMaxPostSpacing
                            )
                            viewModel.setRailing(edgeId, config: config)
                        } label: {
                            Text(type.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(OPSStyle.Colors.background)
                                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stairSection(edgeId: String, edge: DeckEdge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stairs")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if edge.stairConfig != nil {
                    Button("Remove") {
                        viewModel.setStairs(edgeId, config: nil)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                } else {
                    Button("Add Stairs") {
                        viewModel.editingEdgeId = edgeId
                        viewModel.showingStairConfig = true
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }

            if let stair = edge.stairConfig {
                VStack(alignment: .leading, spacing: 4) {
                    infoRow("Width", value: DimensionEngine.formatImperial(stair.width))
                    if let treads = stair.treadCount {
                        infoRow("Treads", value: "\(treads)")
                    }
                    infoRow("Rise/step", value: String(format: "%.1f\"", stair.risePerStep))
                    infoRow("Run/tread", value: String(format: "%.0f\"", stair.runPerTread))
                }
            }
        }
    }

    // MARK: - Vertex Properties

    @ViewBuilder
    private var vertexProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Vertex Properties", icon: "circle.fill")

            ForEach(Array(viewModel.selection.selectedVertexIds), id: \.self) { vertexId in
                if let vertex = viewModel.drawingData.vertex(byId: vertexId) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Elevation
                        HStack {
                            Text("Elevation")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Spacer()
                            if let elev = vertex.elevation {
                                Text(String(format: "%.1f'", elev))
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            } else {
                                Text("Not set")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }

                        // Footing type
                        HStack {
                            Text("Footing")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { vertex.footingType ?? .sonoTube },
                                set: { type in
                                    var v = vertex
                                    v.footingType = type
                                    viewModel.drawingData.updateVertex(v)
                                    viewModel.save()
                                }
                            )) {
                                ForEach(FootingType.allCases, id: \.self) { type in
                                    Text(type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .padding(16)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }

    // MARK: - Footprint Properties

    @ViewBuilder
    private var footprintProperties: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Surface Properties", icon: "square.fill")

            // Area display
            if let area = viewModel.totalArea {
                HStack {
                    Text("Area")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(DimensionEngine.formatArea(area, system: viewModel.drawingData.config.measurementSystem))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(16)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

            // Assigned surface items
            VStack(alignment: .leading, spacing: 8) {
                Text("Assigned Items")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                if viewModel.drawingData.footprint.assignedItems.isEmpty {
                    Text("No items assigned. Use the assignment wheel to add surfacing materials.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.vertical, 8)
                } else {
                    ForEach(viewModel.drawingData.footprint.assignedItems) { item in
                        HStack {
                            Text(item.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text(item.unitType.rawValue.replacingOccurrences(of: "_", with: " "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Button {
                                viewModel.removeFootprintItem(item.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}
