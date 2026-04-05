// OPS/OPS/DeckBuilder/Views/CreationPickerView.swift

import SwiftUI
import SwiftData

struct CreationPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let projectId: String?
    let companyId: String
    let userId: String?
    let onDesignCreated: (DeckDesign) -> Void

    @State private var showingTemplatePicker = false
    @State private var templatePickerInitialTab: Int = 0
    @State private var showingSketchCapture = false
    @State private var showingARPerimeter = false

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("New Deck Design")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.top, OPSStyle.Layout.spacing4)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                // Blank Canvas
                creationOption(
                    icon: "square.and.pencil",
                    title: "Blank Canvas",
                    subtitle: "Start from scratch"
                ) {
                    let design = createBlankDesign()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDesignCreated(design)
                    dismiss()
                }

                // From Template
                creationOption(
                    icon: "square.grid.2x2",
                    title: "From Template",
                    subtitle: "Choose a shape, enter dimensions"
                ) {
                    templatePickerInitialTab = 0
                    showingTemplatePicker = true
                }

                // From Recent
                creationOption(
                    icon: "clock.arrow.circlepath",
                    title: "From Recent Design",
                    subtitle: "Copy a past project's layout"
                ) {
                    templatePickerInitialTab = 1
                    showingTemplatePicker = true
                }

                // Scan Paper Sketch
                creationOption(
                    icon: "doc.viewfinder",
                    title: "Scan Paper Sketch",
                    subtitle: "Photograph a hand-drawn sketch"
                ) {
                    showingSketchCapture = true
                }

                // Walk Perimeter (AR)
                creationOption(
                    icon: "camera.viewfinder",
                    title: "Walk Perimeter (AR)",
                    subtitle: "Walk the deck, tap at each corner"
                ) {
                    showingARPerimeter = true
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            Spacer()
        }
        .background(OPSStyle.Colors.background)
        .fullScreenCover(isPresented: $showingSketchCapture) {
            SketchCaptureView(
                projectId: projectId,
                companyId: companyId,
                userId: userId
            ) { scanResult in
                // Convert scan result to DeckDrawingData and create design
                let drawingData = scanResult.toDeckDrawingData(
                    canvasWidth: 600,
                    canvasHeight: 400
                )
                let design = DeckDesign(
                    companyId: companyId,
                    projectId: projectId,
                    title: scanResult.clientNameCandidate.map { "\($0) Deck" } ?? "Scanned Deck",
                    drawingDataJSON: drawingData.toJSON(),
                    createdBy: userId
                )
                modelContext.insert(design)
                try? modelContext.save()
                showingSketchCapture = false
                onDesignCreated(design)
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showingARPerimeter) {
            ARPerimeterView { drawingData in
                guard !drawingData.vertices.isEmpty else {
                    showingARPerimeter = false
                    return
                }
                let design = DeckDesign(
                    companyId: companyId,
                    projectId: projectId,
                    title: "AR Deck Sketch",
                    drawingDataJSON: drawingData.toJSON(),
                    createdBy: userId
                )
                modelContext.insert(design)
                try? modelContext.save()
                showingARPerimeter = false
                onDesignCreated(design)
                dismiss()
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerView(
                initialTab: templatePickerInitialTab,
                projectId: projectId,
                companyId: companyId,
                userId: userId,
                onDesignCreated: { design in
                    showingTemplatePicker = false
                    onDesignCreated(design)
                    dismiss()
                }
            )
        }
    }

    // MARK: - Option Row

    private func creationOption(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(subtitle)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        }
    }

    // MARK: - Actions

    private func createBlankDesign() -> DeckDesign {
        // Auto-assign title from project context if available
        let title: String
        if let projectId = projectId, let project = try? modelContext.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        ).first {
            title = "\(project.title) — Deck"
        } else {
            title = "Untitled Deck"
        }

        let design = DeckDesign(
            companyId: companyId,
            projectId: projectId,
            title: title,
            createdBy: userId
        )
        modelContext.insert(design)
        try? modelContext.save()
        return design
    }
}
