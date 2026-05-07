// OPS/OPS/DeckBuilder/Views/PropertySheetView.swift

import SwiftUI
import SwiftData

struct PropertySheetView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    // Catalog data — feeds the metadata-field pickers when the company has
    // a default Product configured for the surface context. When the
    // queries return empty (offline preview / fresh install), fields fall
    // back to free-text input. (Deck-catalog integration spec § 4.3.)
    @Query private var products: [Product]
    @Query private var productOptions: [ProductOption]
    @Query private var productOptionValues: [ProductOptionValue]
    @Query private var companyDefaults: [CompanyDefaultProduct]

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
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("Edge Properties", icon: "line.diagonal")

            // Edge type picker
            ForEach(Array(viewModel.selection.selectedEdgeIds), id: \.self) { edgeId in
                if let edge = viewModel.drawingData.edge(byId: edgeId) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        // Dimension
                        if let dim = edge.dimension {
                            HStack {
                                Text("Length")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Spacer()
                                Text(DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem))
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }

                        // Edge type
                        HStack {
                            Text("Type")
                                .font(OPSStyle.Typography.caption)
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
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }

    @ViewBuilder
    private func railingSection(edgeId: String, edge: DeckEdge) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("Railing")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                if edge.railingConfig != nil {
                    Button("Remove") {
                        viewModel.setRailing(edgeId, config: nil)
                    }
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                }
            }

            if let railing = edge.railingConfig {
                Text(railing.railingType.displayName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                // Post spacing
                HStack {
                    Text("Max post spacing")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(DimensionEngine.formatImperial(railing.maxPostSpacing))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                // Post count
                if let dim = edge.dimension {
                    let posts = DimensionEngine.postCount(edgeLengthInches: dim, maxSpacing: railing.maxPostSpacing)
                    HStack {
                        Text("Posts needed")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text("\(posts)")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }

                // Catalog metadata vocabulary — what the adapter reads off
                // the design when generating estimates. Pickers when the
                // company default Product exposes the matching axis;
                // free-text fallback otherwise.
                metadataPicker(
                    label: "Color",
                    value: railing.color,
                    sourceKey: "color",
                    componentType: .railing,
                    onChange: { viewModel.setRailingMetadata(edgeId: edgeId, color: $0) }
                )
                metadataPicker(
                    label: "Mount type",
                    value: railing.mountType,
                    sourceKey: "mount_type",
                    componentType: .railing,
                    onChange: { viewModel.setRailingMetadata(edgeId: edgeId, mountType: $0) }
                )
                metadataPicker(
                    label: "Mount surface",
                    value: railing.mountSurface,
                    sourceKey: "mount_surface",
                    componentType: .railing,
                    onChange: { viewModel.setRailingMetadata(edgeId: edgeId, mountSurface: $0) }
                )
                postHeightStepper(
                    edgeId: edgeId,
                    current: railing.postHeight
                )
            } else {
                // Railing type picker
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(RailingType.allCases, id: \.self) { type in
                        Button {
                            let config = RailingConfig(
                                railingType: type,
                                maxPostSpacing: type.defaultMaxPostSpacing
                            )
                            viewModel.setRailing(edgeId, config: config)
                        } label: {
                            Text(type.displayName)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                                .padding(.vertical, OPSStyle.Layout.spacing2)
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
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("Stairs")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                if edge.stairConfig != nil {
                    Button("Remove") {
                        viewModel.setStairs(edgeId, config: nil)
                    }
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                } else {
                    Button("Add Stairs") {
                        viewModel.editingEdgeId = edgeId
                        viewModel.showingStairConfig = true
                    }
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }

            if let stair = edge.stairConfig {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    infoRow("Width", value: DimensionEngine.formatImperial(stair.width))
                    if let treads = stair.treadCount {
                        infoRow("Treads", value: "\(treads)")
                    }
                    infoRow("Rise/step", value: String(format: "%.1f\"", stair.risePerStep))
                    infoRow("Run/tread", value: String(format: "%.0f\"", stair.runPerTread))
                }

                // Catalog metadata for stairs — vocabulary differs from
                // railing (Surface | Top | Side instead of Topmount etc).
                metadataPicker(
                    label: "Color",
                    value: stair.color,
                    sourceKey: "color",
                    componentType: .stairSet,
                    onChange: { viewModel.setStairMetadata(edgeId: edgeId, color: $0) }
                )
                metadataPicker(
                    label: "Mount type",
                    value: stair.mountType,
                    sourceKey: "mount_type",
                    componentType: .stairSet,
                    onChange: { viewModel.setStairMetadata(edgeId: edgeId, mountType: $0) }
                )
            }
        }
    }

    // MARK: - Vertex Properties

    @ViewBuilder
    private var vertexProperties: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("Vertex Properties", icon: "circle.fill")

            ForEach(Array(viewModel.selection.selectedVertexIds), id: \.self) { vertexId in
                if let vertex = viewModel.drawingData.vertex(byId: vertexId) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        // Elevation
                        HStack {
                            Text("Elevation")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Spacer()
                            if let elev = vertex.elevation {
                                Text(String(format: "%.1f'", elev))
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            } else {
                                Text("Not set")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }

                        // Footing type
                        HStack {
                            Text("Footing")
                                .font(OPSStyle.Typography.caption)
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
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }

    // MARK: - Footprint Properties

    @ViewBuilder
    private var footprintProperties: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("Surface Properties", icon: "square.fill")

            // Area display
            if let area = viewModel.totalArea {
                HStack {
                    Text("Area")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(DimensionEngine.formatArea(area, system: viewModel.drawingData.config.measurementSystem))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

            // Assigned surface items
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("Assigned Items")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if viewModel.drawingData.footprint.assignedItems.isEmpty {
                    Text("No items assigned. Use the assignment wheel to add surfacing materials.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                } else {
                    ForEach(viewModel.drawingData.footprint.assignedItems) { item in
                        HStack {
                            Text(item.name)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Spacer()
                            Text(item.unitType.rawValue.replacingOccurrences(of: "_", with: " "))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Button {
                                viewModel.removeFootprintItem(item.id)
                            } label: {
                                Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                        }
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            // Catalog metadata for the surface(s) — drives `deck_board`
            // metadata in the components projection. Only renders when at
            // least one persisted surface is selected; the legacy single-
            // footprint store doesn't carry color/material today.
            surfaceMetadataSection
        }
    }

    // MARK: - Surface metadata section

    @ViewBuilder
    private var surfaceMetadataSection: some View {
        let selectedIds = viewModel.selection.selectedSurfaceIds
        let selectedSurfaces = selectedIds.compactMap { viewModel.findSurface(byId: $0) }
        if let first = selectedSurfaces.first {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("Decking")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                metadataPicker(
                    label: "Color",
                    value: first.color,
                    sourceKey: "color",
                    componentType: .deckBoard,
                    onChange: { viewModel.setColorOnSelectedSurfaces($0) }
                )
                metadataPicker(
                    label: "Material",
                    value: first.boardMaterial,
                    sourceKey: "material",
                    componentType: .deckBoard,
                    onChange: { viewModel.setMaterialOnSelectedSurfaces($0) }
                )
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(OPSStyle.Typography.bodyEmphasis)
            .foregroundColor(OPSStyle.Colors.primaryText)
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    // MARK: - Catalog metadata helpers

    /// One row that renders either a Picker (when the company default
    /// Product for `componentType` exposes an axis bound to
    /// `$design.<sourceKey>`) or a TextField (free-text fallback).
    /// Mirrors the catalog spec's "same form, different fields" pattern —
    /// the user sees the data the projection is committing to whether or
    /// not a Product is configured.
    @ViewBuilder
    private func metadataPicker(
        label: String,
        value: String,
        sourceKey: String,
        componentType: DesignComponentType,
        onChange: @escaping (String) -> Void
    ) -> some View {
        let values = optionValues(forSourceKey: sourceKey, componentType: componentType)
        HStack {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            if let values, !values.isEmpty {
                Picker("", selection: Binding(
                    get: { value },
                    set: { onChange($0) }
                )) {
                    // Surface the current value even when it's not in the
                    // axis's authored values — covers free-text data saved
                    // before the company set a default product.
                    if !values.contains(value) {
                        Text(value).tag(value)
                    }
                    ForEach(values, id: \.self) { v in
                        Text(v).tag(v)
                    }
                }
                .pickerStyle(.menu)
                .tint(OPSStyle.Colors.primaryAccent)
            } else {
                TextField(label, text: Binding(
                    get: { value },
                    set: { onChange($0) }
                ))
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: 180)
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private func postHeightStepper(edgeId: String, current: Double) -> some View {
        HStack {
            Text("Post height")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Stepper(
                value: Binding(
                    get: { current },
                    set: { viewModel.setRailingMetadata(edgeId: edgeId, postHeight: $0) }
                ),
                in: 24...48,
                step: 2
            ) {
                Text(DimensionEngine.formatImperial(current))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .labelsHidden()
            Text(DimensionEngine.formatImperial(current))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 60, alignment: .trailing)
        }
    }

    /// Finds the option values authored on the company's default Product
    /// for `componentType` whose `optionDefaultSource` matches
    /// `$design.<sourceKey>`. Returns nil when no default Product exists,
    /// or when the Product has no axis bound to that source — both cases
    /// tell the caller to render free-text.
    private func optionValues(forSourceKey key: String, componentType: DesignComponentType) -> [String]? {
        let companyId = viewModel.deckDesign.companyId
        guard let defaultRow = companyDefaults.first(where: {
            $0.companyId == companyId && $0.componentType == componentType
        }) else { return nil }
        let pid = defaultRow.productId
        let source = "$design.\(key)"
        guard let match = productOptions.first(where: {
            $0.productId == pid && $0.optionDefaultSource == source
        }) else { return nil }
        let values = productOptionValues
            .filter { $0.optionId == match.id }
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .map { $0.value }
        return values.isEmpty ? nil : values
    }
}
