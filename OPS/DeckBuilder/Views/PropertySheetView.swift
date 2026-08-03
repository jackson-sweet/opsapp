// OPS/OPS/DeckBuilder/Views/PropertySheetView.swift

import SwiftUI
import SwiftData

/// Owns the transient text for a deck label and emits a normalized value only
/// when editing is explicitly committed. Keystrokes are draft-only so they
/// cannot create undo, persistence, sync, or feedback side effects.
struct DeckLabelEditSession: Equatable {
    struct Commit: Equatable {
        let value: String?
    }

    enum Action: Equatable {
        case changed(String)
        case commit
        case synchronize(String?)
    }

    private(set) var draft: String
    private var committedValue: String?

    init(sourceValue: String?) {
        draft = sourceValue ?? ""
        committedValue = Self.normalized(sourceValue)
    }

    mutating func handle(_ action: Action) -> Commit? {
        switch action {
        case .changed(let value):
            draft = value
            return nil

        case .commit:
            let value = Self.normalized(draft)
            guard value != committedValue else { return nil }
            committedValue = value
            return Commit(value: value)

        case .synchronize(let value):
            draft = value ?? ""
            committedValue = Self.normalized(value)
            return nil
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}

/// A visually-neutral TextField wrapper that gives deck labels one shared,
/// idempotent commit contract across keyboard Done, focus loss, and dismissal.
private struct CommittingDeckLabelField: View {
    let placeholder: String
    let sourceValue: String?
    let target: DeckLabelEditTarget
    let onCommit: (DeckLabelEditTarget, String?) -> Void

    @State private var session: DeckLabelEditSession
    @State private var editTarget: DeckLabelEditTarget
    @FocusState private var isFocused: Bool

    init(
        _ placeholder: String,
        sourceValue: String?,
        target: DeckLabelEditTarget,
        onCommit: @escaping (DeckLabelEditTarget, String?) -> Void
    ) {
        self.placeholder = placeholder
        self.sourceValue = sourceValue
        self.target = target
        self.onCommit = onCommit
        _session = State(initialValue: DeckLabelEditSession(sourceValue: sourceValue))
        _editTarget = State(initialValue: target)
    }

    var body: some View {
        TextField(
            placeholder,
            text: Binding(
                get: { session.draft },
                set: { _ = session.handle(.changed($0)) }
            )
        )
        .focused($isFocused)
        .onSubmit {
            commit()
            isFocused = false
        }
        .onChange(of: isFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
                commit()
            }
        }
        .onChange(of: sourceValue) { _, value in
            guard !isFocused, editTarget == target else { return }
            _ = session.handle(.synchronize(value))
        }
        .onDisappear {
            commit()
        }
    }

    private func commit() {
        guard let commit = session.handle(.commit) else { return }
        onCommit(editTarget, commit.value)
    }
}

struct PropertySheetView: View {
    /// A free-text vocabulary value being typed. Held here so one alert
    /// serves every field on the sheet.
    private struct VocabularyEdit {
        let title: String
        var text: String
        let commit: (String?) -> Void
    }

    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingNestedMaterialPicker = false
    @State private var vocabularyEdit: VocabularyEdit?

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
                VStack(spacing: OPSStyle.Layout.spacing3) {
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
                .padding(OPSStyle.Layout.spacing3_5)
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
        .sheet(isPresented: $showingNestedMaterialPicker) {
            MaterialPickerSheet(viewModel: viewModel)
        }
        .alert(vocabularyEdit?.title ?? "", isPresented: Binding(
            get: { vocabularyEdit != nil },
            set: { if !$0 { vocabularyEdit = nil } }
        )) {
            TextField("Value", text: Binding(
                get: { vocabularyEdit?.text ?? "" },
                set: { vocabularyEdit?.text = $0 }
            ))
            Button("Save") {
                if let edit = vocabularyEdit {
                    let trimmed = edit.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    edit.commit(trimmed.isEmpty ? nil : trimmed)
                }
                vocabularyEdit = nil
            }
            Button("Cancel", role: .cancel) { vocabularyEdit = nil }
        }
        .onChange(of: viewModel.activeLevelIndex) { _, _ in
            // Dismiss when level switches — edge/vertex references may belong to the previous level
            dismiss()
        }
        .onDisappear {
            // Label commits inside this sheet queue a coalesced write rather
            // than persisting inside each focus hand-off (which dropped the
            // keyboard between fields). Closing the sheet ends the burst.
            viewModel.flushPendingSave()
        }
    }

    // MARK: - Edge Properties

    @ViewBuilder
    private var edgeProperties: some View {
        let selectedIds = Array(viewModel.selection.selectedEdgeIds)
        let selectedEdges = selectedIds.compactMap { viewModel.findEdge(byId: $0) }
        let houseEdgeIds = selectedEdges.filter { $0.edgeType == .houseEdge }.map(\.id)
        let parapetEdgeIds = selectedEdges
            .filter { $0.edgeType == .deckEdge && $0.railingConfig?.railingType == .parapetWall }
            .map(\.id)
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("Edge Properties", icon: "line.diagonal")

            // Bulk edge-type control — when more than one edge is selected a
            // single Type toggle applies to the WHOLE selection in one action,
            // so "mark these as house edge" lands on all of them, not just one.
            // The per-edge cards below own Type in single-select.
            if selectedIds.count > 1 {
                bulkEdgeTypeControl(edgeIds: selectedIds)
            }

            materialPickerEntry(
                title: "Material",
                detail: selectedIds.count == 1 ? "Assign catalog material to this edge" : "Assign catalog material to selected edges"
            )

            if selectedIds.count > 1, !houseEdgeIds.isEmpty {
                houseCladdingPicker(edgeIds: houseEdgeIds, activeMaterial: commonHouseMaterial(for: houseEdgeIds))
            }

            if selectedIds.count > 1, !parapetEdgeIds.isEmpty {
                parapetFinishPicker(edgeIds: parapetEdgeIds, activeMaterial: commonParapetMaterial(for: parapetEdgeIds))
            }

            ForEach(selectedIds, id: \.self) { edgeId in
                // Multi-level-aware lookup. The plain `drawingData.edge(byId:)`
                // only inspects the top-level edges array, which is empty in
                // multi-level mode — so the section rendered nothing for the
                // reporter's two-level design. Bug 6d1c0a2a / 0b55c546.
                if let edge = viewModel.findEdge(byId: edgeId) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        // Edge type — single-select only; the bulk control
                        // above owns Type when multiple edges are selected.
                        if selectedIds.count == 1 {
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
                        }

                        // House cladding picker — only shown for house edges.
                        // Bug 3d72ce0b — surfaces a tactile picker so the
                        // user sees the rendered wall material in 2D and 3D.
                        if edge.edgeType == .houseEdge, selectedIds.count == 1 {
                            houseCladdingPicker(edgeIds: [edgeId], activeMaterial: edge.houseEdgeMaterial)
                        }

                        // Free-text label rendered as the secondary line on
                        // the dimension pill ("Hot tub side", "BBQ wall").
                        // Bug 4a03f507.
                        edgeLabelField(edgeId: edgeId, edge: edge)

                        if edge.edgeType == .deckEdge {
                            Divider().background(OPSStyle.Colors.separator)

                            // Railing / parapet. House edges cannot carry
                            // railing configuration; switching to house edge
                            // clears any legacy railing state in the view model.
                            railingSection(edgeId: edgeId, edge: edge, showMaterialControls: selectedIds.count == 1)
                        }

                        Divider().background(OPSStyle.Colors.separator)

                        // Stairs
                        stairSection(edgeId: edgeId, edge: edge)

                        // Measured length, below everything that changes the
                        // edge — the operator opened this card to edit, not
                        // to re-read a number the canvas already shows.
                        readoutRow(
                            "Length",
                            value: edge.dimension.map {
                                DimensionEngine.format($0, system: viewModel.drawingData.config.measurementSystem)
                            }
                        )
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
    }

    /// Single Type toggle shown above the per-edge cards when more than one
    /// edge is selected. Setting it applies the chosen type to every selected
    /// edge in one atomic action. Shows the common type when the selection is
    /// uniform, otherwise defaults the toggle to Deck Edge.
    @ViewBuilder
    private func bulkEdgeTypeControl(edgeIds: [String]) -> some View {
        let types = Set(edgeIds.compactMap { viewModel.findEdge(byId: $0)?.edgeType })
        let common: EdgeType = types.count == 1 ? (types.first ?? .deckEdge) : .deckEdge
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack {
                Text("Type")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Picker("", selection: Binding(
                    get: { common },
                    set: { viewModel.setEdgeType(edgeIds, type: $0) }
                )) {
                    Text("Deck Edge").tag(EdgeType.deckEdge)
                    Text("House Edge").tag(EdgeType.houseEdge)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            Text("Applies to \(edgeIds.count) selected edges")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    @ViewBuilder
    private func railingSection(edgeId: String, edge: DeckEdge, showMaterialControls: Bool) -> some View {
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

                if railing.railingType == .parapetWall {
                    if showMaterialControls {
                        parapetFinishPicker(edgeIds: [edgeId], activeMaterial: railing.wallMaterial)
                    }
                } else {
                    // Catalog metadata vocabulary — what the adapter reads off
                    // the design when generating estimates.
                    vocabularyRow(
                        label: "Color",
                        value: railing.color,
                        sourceKey: "color",
                        componentType: .railing,
                        allowsClearing: false,
                        onChange: { value in
                            guard let value else { return }
                            viewModel.setRailingMetadata(edgeId: edgeId, color: value)
                        }
                    )
                    vocabularyRow(
                        label: "Mount type",
                        value: railing.mountType,
                        sourceKey: "mount_type",
                        componentType: .railing,
                        allowsClearing: false,
                        onChange: { value in
                            guard let value else { return }
                            viewModel.setRailingMetadata(edgeId: edgeId, mountType: value)
                        }
                    )
                    vocabularyRow(
                        label: "Mount surface",
                        value: railing.mountSurface,
                        sourceKey: "mount_surface",
                        componentType: .railing,
                        allowsClearing: false,
                        onChange: { value in
                            guard let value else { return }
                            viewModel.setRailingMetadata(edgeId: edgeId, mountSurface: value)
                        }
                    )
                    postHeightStepper(
                        edgeId: edgeId,
                        current: railing.postHeight
                    )

                    // Derived figures, below the controls that drive them.
                    readoutRow(
                        "Max post spacing",
                        value: DimensionEngine.formatImperial(railing.maxPostSpacing)
                    )
                    readoutRow(
                        "Posts needed",
                        value: edge.dimension.map {
                            "\(DimensionEngine.postCount(edgeLengthInches: $0, maxSpacing: railing.maxPostSpacing))"
                        }
                    )
                }
            } else {
                // Railing type picker
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(RailingType.assignableDefaultTypes, id: \.self) { type in
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
        // An edge carries ONE stair — a fixed-rise config OR a level
        // connection. This block only ever looked at `stairConfig`, so an
        // edge whose stairs run down to another level still offered "Add
        // Stairs" as though it had none. Bug ee41a0a0.
        let connection = viewModel.connection(forEdgeId: edgeId)
        let stair = edge.stairConfig ?? connection?.stairConfig
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("Stairs")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                if stair != nil {
                    Button("Remove") {
                        // Clears whichever kind the edge carries. `setStairs(nil)`
                        // only ever cleared the fixed-rise config and left a
                        // connection in place.
                        viewModel.removeStairs(edgeId: edgeId)
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

            if let stair {
                if connection != nil {
                    Text("Connects to \(connectedLevelName(for: connection) ?? "another level")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                // Catalog metadata for stairs — vocabulary differs from
                // railing (Surface | Top | Side instead of Topmount etc).
                vocabularyRow(
                    label: "Color",
                    value: stair.color,
                    sourceKey: "color",
                    componentType: .stairSet,
                    allowsClearing: false,
                    onChange: { value in
                        guard let value else { return }
                        viewModel.setStairMetadata(edgeId: edgeId, color: value)
                    }
                )
                vocabularyRow(
                    label: "Mount type",
                    value: stair.mountType,
                    sourceKey: "mount_type",
                    componentType: .stairSet,
                    allowsClearing: false,
                    onChange: { value in
                        guard let value else { return }
                        viewModel.setStairMetadata(edgeId: edgeId, mountType: value)
                    }
                )

                // Built figures, below the controls that change them.
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    readoutRow("Width", value: DimensionEngine.formatImperial(stair.width))
                    readoutRow("Treads", value: stair.treadCount.map { "\($0)" })
                    readoutRow("Rise/step", value: String(format: "%.1f\"", stair.risePerStep))
                    readoutRow("Run/tread", value: String(format: "%.0f\"", stair.runPerTread))
                }
            }
        }
    }

    private func connectedLevelName(for connection: LevelConnection?) -> String? {
        guard let connection else { return nil }
        return viewModel.drawingData.levels.first { $0.id == connection.lowerLevelId }?.name
    }

    // MARK: - Edge Label (bug 4a03f507)

    /// Free-text label for an individual edge. Wires `DeckEdge.label`
    /// through the view model so the dimension pill picks it up as the
    /// secondary line.
    @ViewBuilder
    private func edgeLabelField(edgeId: String, edge: DeckEdge) -> some View {
        let labelTarget = DeckLabelEditTarget.edge(
            id: edgeId,
            levelId: viewModel.activeLevel?.id
        )
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "tag")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
            CommittingDeckLabelField(
                "Label (optional)",
                sourceValue: edge.label,
                target: labelTarget,
                onCommit: { viewModel.setLabel($1, for: $0) }
            )
            .id(labelTarget)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.background.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    @ViewBuilder
    private func parapetFinishPicker(edgeIds: [String], activeMaterial: HouseEdgeMaterial?) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Finish")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(HouseEdgeMaterial.allCases, id: \.self) { material in
                    Button {
                        viewModel.setRailingWallMaterial(edgeIds, material: material)
                    } label: {
                        VStack(spacing: OPSStyle.Layout.spacing1) {
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .fill(Color(hex: material.fillHex) ?? .gray)
                                .frame(height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                        .stroke(
                                            activeMaterial == material
                                                ? OPSStyle.Colors.text
                                                : Color.white.opacity(0.15),
                                            lineWidth: activeMaterial == material ? 2 : 1
                                        )
                                )
                            Text(material.displayName)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(
                                    activeMaterial == material
                                        ? OPSStyle.Colors.primaryText
                                        : OPSStyle.Colors.secondaryText
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - House Cladding (bug 3d72ce0b)

    /// Cladding picker shown on house edges. House siding drives the 2D
    /// hatch color, the 3D wall fill, and the floating "HOUSE" label tone.
    /// None means "no material picked yet" and renders the neutral fallback.
    @ViewBuilder
    private func houseCladdingPicker(edgeIds: [String], activeMaterial: HouseEdgeMaterial?) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Cladding")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(HouseEdgeMaterial.allCases, id: \.self) { material in
                    Button {
                        if activeMaterial == material {
                            viewModel.setHouseEdgeMaterial(edgeIds, material: nil)
                        } else {
                            viewModel.setHouseEdgeMaterial(edgeIds, material: material)
                        }
                    } label: {
                        VStack(spacing: OPSStyle.Layout.spacing1) {
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .fill(Color(hex: material.fillHex) ?? .gray)
                                .frame(height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                        .stroke(
                                            activeMaterial == material
                                                ? OPSStyle.Colors.text
                                                : Color.white.opacity(0.15),
                                            lineWidth: activeMaterial == material ? 2 : 1
                                        )
                                )
                            Text(material.displayName)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(
                                    activeMaterial == material
                                        ? OPSStyle.Colors.primaryText
                                        : OPSStyle.Colors.secondaryText
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if edgeIds.count > 1 {
                Text("Applies to \(edgeIds.count) selected edges")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }

    // MARK: - Vertex Properties

    @ViewBuilder
    private var vertexProperties: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("Vertex Properties", icon: "circle.fill")

            ForEach(Array(viewModel.selection.selectedVertexIds), id: \.self) { vertexId in
                if let vertex = viewModel.findVertex(byId: vertexId) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        // The only control on this card leads. Footing writes
                        // now route through the active level with undo — the
                        // old path wrote to the top-level vertices array, which
                        // is empty on a multi-level drawing, so the picker
                        // silently did nothing there.
                        HStack {
                            Text("Footing")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { vertex.footingType ?? .sonoTube },
                                set: { viewModel.setFootingType($0, forVertexId: vertexId) }
                            )) {
                                ForEach(FootingType.allCases, id: \.self) { type in
                                    Text(type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(OPSStyle.Colors.text)
                        }

                        readoutRow(
                            "Elevation",
                            value: vertex.elevation.map { String(format: "%.1f'", $0) }
                        )
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
        let summary = viewModel.selectedSurfaceSummary
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("Surface Properties", icon: "square.fill")

            // Naming and specifying the surface is what the operator came
            // here to do — those lead. Area and perimeter are figures the
            // canvas already shows; they sit at the bottom as reference.
            surfaceLabelField

            // Catalog metadata for the surface(s) — drives `deck_board`
            // metadata in the components projection.
            surfaceMetadataSection

            materialPickerEntry(
                title: "Material",
                detail: "Assign catalog material to selected surfaces"
            )

            // Assigned surface items
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("Assigned Items")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                let assignedItems = summary?.assignedItems ?? []
                if assignedItems.isEmpty {
                    Text("No surface material assigned.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                } else {
                    ForEach(assignedItems) { item in
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

            if let summary {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    readoutRow(
                        "Area",
                        value: DimensionEngine.formatArea(
                            summary.areaSquareInches,
                            system: viewModel.drawingData.config.measurementSystem
                        )
                    )
                    readoutRow(
                        "Perimeter",
                        value: DimensionEngine.format(
                            summary.perimeterInches,
                            system: viewModel.drawingData.config.measurementSystem
                        )
                    )
                }
                .padding(OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    // MARK: - Surface label field (bug 4a03f507)

    /// Free-text label that floats on the canvas over the selected surfaces.
    /// One label per selection, by design — naming three surfaces at once
    /// names all three. Empty input clears it.
    ///
    /// This section only renders when at least one surface is selected
    /// (`selectedFootprint` IS `!selectedSurfaceIds.isEmpty`), so the old
    /// legacy-footprint fallback branch was unreachable — it has been
    /// removed rather than left to imply a path that never runs.
    @ViewBuilder
    private var surfaceLabelField: some View {
        let selectedSurfaceIds = viewModel.selection.selectedSurfaceIds
        let surfaces = selectedSurfaceIds.compactMap { viewModel.findSurface(byId: $0) }
        // Seed from the value they all share. Showing the first one's name
        // for a mixed selection would claim the others answer to it too.
        let activeLabel = commonValue(surfaces.map(\.label)).value ?? ""
        let labelTarget = DeckLabelEditTarget.surfaces(
            ids: selectedSurfaceIds,
            levelId: viewModel.activeLevel?.id
        )

        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Label")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "tag")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                CommittingDeckLabelField(
                    "e.g. BBQ pad, Hot tub deck",
                    sourceValue: activeLabel,
                    target: labelTarget,
                    onCommit: { viewModel.setLabel($1, for: $0) }
                )
                .id(labelTarget)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.background.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Surface metadata section

    @ViewBuilder
    private var surfaceMetadataSection: some View {
        let selectedIds = viewModel.selection.selectedSurfaceIds
        let selectedSurfaces = selectedIds.compactMap { viewModel.findSurface(byId: $0) }
        if !selectedSurfaces.isEmpty {
            // Across the whole selection, not just the first one. Editing
            // three surfaces used to look exactly like editing one.
            let colour = commonValue(selectedSurfaces.map(\.color))
            let material = commonValue(selectedSurfaces.map(\.boardMaterial))
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("Decking")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                vocabularyRow(
                    label: "Color",
                    value: colour.value,
                    isMixed: colour.isMixed,
                    sourceKey: "color",
                    componentType: .deckBoard,
                    onChange: { viewModel.setColorOnSelectedSurfaces($0) }
                )
                vocabularyRow(
                    label: "Material",
                    value: material.value,
                    isMixed: material.isMixed,
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
    private func materialPickerEntry(title: String, detail: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "shippingbox")
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(detail)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            Button {
                showingNestedMaterialPicker = true
            } label: {
                Text("Choose")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private func commonHouseMaterial(for edgeIds: [String]) -> HouseEdgeMaterial? {
        let materials = edgeIds.map { viewModel.findEdge(byId: $0)?.houseEdgeMaterial }
        guard let first = materials.first,
              materials.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private func commonParapetMaterial(for edgeIds: [String]) -> HouseEdgeMaterial? {
        let materials = edgeIds.map { viewModel.findEdge(byId: $0)?.railingConfig?.wallMaterial }
        guard let first = materials.first,
              materials.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(OPSStyle.Typography.bodyEmphasis)
            .foregroundColor(OPSStyle.Colors.primaryText)
    }

    // MARK: - Catalog metadata helpers

    /// One vocabulary field. When the company has a default Product for this
    /// component type, the menu offers that Product's authored option values
    /// — those strings have to match exactly or the adapter's pricing
    /// modifiers never fire. A crew is never blocked by a catalog that hasn't
    /// caught up, so free text stays available either way, and a value that
    /// isn't in the list is marked custom rather than flagged as wrong.
    ///
    /// Unset reads `—`. It used to read whatever the model defaulted to,
    /// which presented a choice nobody had made (bug ee41a0a0).
    @ViewBuilder
    private func vocabularyRow(
        label: String,
        value: String?,
        isMixed: Bool = false,
        sourceKey: String,
        componentType: DesignComponentType,
        allowsClearing: Bool = true,
        onChange: @escaping (String?) -> Void
    ) -> some View {
        let values = optionValues(forSourceKey: sourceKey, componentType: componentType) ?? []
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let isCustom = resolved.map { !values.isEmpty && !values.contains($0) } ?? false

        HStack {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Menu {
                ForEach(values, id: \.self) { option in
                    Button(option) { onChange(option) }
                }
                Button("Custom\u{2026}") {
                    vocabularyEdit = VocabularyEdit(
                        title: label,
                        text: resolved ?? "",
                        commit: onChange
                    )
                }
                if allowsClearing, resolved != nil {
                    Button("Clear", role: .destructive) { onChange(nil) }
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    if isCustom {
                        Text("CUSTOM")
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing1)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }
                    Text(isMixed ? "Mixed" : (resolved ?? "\u{2014}"))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(
                            (isMixed || resolved == nil)
                                ? OPSStyle.Colors.tertiaryText
                                : OPSStyle.Colors.primaryText
                        )
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
    }

    /// A measured or derived figure — never editable, always below the
    /// controls that change it. `—` when there is nothing to show.
    @ViewBuilder
    private func readoutRow(_ label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value ?? "\u{2014}")
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(value == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
        }
    }

    /// The one value every selected element agrees on, plus whether they
    /// disagree. The sheet used to render the FIRST selection's value as if
    /// it spoke for all of them, so editing three surfaces looked like
    /// editing one. Bug ee41a0a0.
    private func commonValue(_ values: [String?]) -> (value: String?, isMixed: Bool) {
        guard let first = values.first else { return (nil, false) }
        let allAgree = values.allSatisfy { $0 == first }
        return allAgree ? (first, false) : (nil, true)
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
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .labelsHidden()
            Text(DimensionEngine.formatImperial(current))
                .font(OPSStyle.Typography.dataValue)
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
