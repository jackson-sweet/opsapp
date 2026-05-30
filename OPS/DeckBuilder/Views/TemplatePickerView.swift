// OPS/OPS/DeckBuilder/Views/TemplatePickerView.swift

import SwiftUI
import SwiftData

struct TemplatePickerView: View {
    let initialTab: Int  // 0 = templates, 1 = recents
    let projectId: String?
    let companyId: String
    let userId: String?
    let onDesignCreated: (DeckDesign) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int
    @State private var selectedTemplate: DeckTemplateType?
    @State private var showingDimensionInput = false
    @State private var recentDesigns: [DeckDesign] = []

    init(
        initialTab: Int,
        projectId: String?,
        companyId: String,
        userId: String?,
        onDesignCreated: @escaping (DeckDesign) -> Void
    ) {
        self.initialTab = initialTab
        self.projectId = projectId
        self.companyId = companyId
        self.userId = userId
        self.onDesignCreated = onDesignCreated
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Tab selector
            SegmentedControl(
                selection: $selectedTab,
                options: [(0, "Templates"), (1, "Recents")]
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)

            // Content
            if selectedTab == 0 {
                templatesGrid
            } else {
                recentsList
            }
        }
        .background(OPSStyle.Colors.background)
        .onAppear { loadRecentDesigns() }
        .sheet(isPresented: $showingDimensionInput) {
            if let template = selectedTemplate {
                // Bug e7965781 — receive the user's active unit mode and pass
                // it into the engine so the resulting deck design's
                // DrawingConfig.measurementSystem is set correctly. Otherwise
                // metric input renders in imperial in the deck builder.
                TemplateDimensionInputView(templateType: template) { dimensions, system in
                    createFromTemplate(template: template, dimensions: dimensions, system: system)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image("ops.close")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }

            Spacer()

            Text("Choose a Starting Point")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            // Spacer to balance the X button
            Color.clear
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - Templates Grid

    private var templatesGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: OPSStyle.Layout.spacing3),
                    GridItem(.flexible(), spacing: OPSStyle.Layout.spacing3),
                ],
                spacing: OPSStyle.Layout.spacing3
            ) {
                ForEach(DeckTemplateType.allCases) { template in
                    templateCard(template)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    private func templateCard(_ template: DeckTemplateType) -> some View {
        Button {
            selectedTemplate = template
            showingDimensionInput = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                // Shape icon
                Image(systemName: template.iconName)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(height: 56)

                // Name
                Text(template.displayName)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                // Dimension count badge
                Text("\(template.dimensionCount) dimensions")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Recents List

    private var recentsList: some View {
        ScrollView {
            if recentDesigns.isEmpty {
                emptyRecentsState
            } else {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(recentDesigns) { design in
                        recentRow(design)
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
        }
    }

    private func recentRow(_ design: DeckDesign) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Thumbnail
            if let urlStr = design.thumbnailURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                        .overlay(
                            Image("ops.view-grid")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        )
                }
                .frame(width: 60, height: 60)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .clipped()
            } else {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image("ops.view-grid")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    )
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(design.title)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Text(dimensionSummary(design))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)

                Text(relativeDate(design.createdAt))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            // Copy button
            Button {
                copyDesign(design)
            } label: {
                Text("Copy")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.12))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: 1)
        )
    }

    private var emptyRecentsState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            Image("ops.in-progress")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("No previous designs yet.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("Create your first deck to see it here.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, OPSStyle.Layout.spacing5)
    }

    // MARK: - Actions

    private func createFromTemplate(
        template: DeckTemplateType,
        dimensions: [Double],
        system: MeasurementSystem
    ) {
        // Bug e7965781 — pass the user's chosen unit mode through so the
        // generated drawing's `config.measurementSystem` matches what the
        // user typed. Affects every dimension format in the builder afterward.
        var config = DrawingConfig()
        config.measurementSystem = system

        guard let drawingData = DeckTemplateEngine.generate(
            template: template,
            dimensions: dimensions,
            config: config
        ) else { return }

        let design = DeckDesign(
            companyId: companyId,
            projectId: projectId,
            title: "\(template.displayName) Deck",
            createdBy: userId
        )
        design.drawingData = drawingData
        modelContext.insert(design)
        try? modelContext.save()

        showingDimensionInput = false
        onDesignCreated(design)
    }

    private func copyDesign(_ original: DeckDesign) {
        let copiedData = DeckTemplateEngine.copyDrawingData(original.drawingData)

        let design = DeckDesign(
            companyId: companyId,
            projectId: nil,
            title: "Copy of \(original.title)",
            createdBy: userId
        )
        design.drawingData = copiedData
        modelContext.insert(design)
        try? modelContext.save()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onDesignCreated(design)
    }

    // MARK: - Data Loading

    private func loadRecentDesigns() {
        let cid = companyId
        var descriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate<DeckDesign> {
                $0.companyId == cid && $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\DeckDesign.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        recentDesigns = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Helpers

    private func dimensionSummary(_ design: DeckDesign) -> String {
        let data = design.drawingData
        guard !data.edges.isEmpty else { return "Empty" }

        let dims = data.edges.compactMap(\.dimension)
        guard !dims.isEmpty else { return "\(data.vertices.count) vertices" }

        // Show first two distinct dimensions as rough shape descriptor
        let uniqueDims = Array(Set(dims)).sorted().prefix(2)
        let formatted = uniqueDims.map { DimensionEngine.format($0, system: data.config.measurementSystem) }
        return formatted.joined(separator: " × ")
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
