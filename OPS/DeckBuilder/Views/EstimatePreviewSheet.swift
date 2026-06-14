// OPS/OPS/DeckBuilder/Views/EstimatePreviewSheet.swift

import SwiftUI

struct EstimatePreviewSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var lineItems: [CatalogEstimateMerger.LineItem] = []
    @State private var areaSqFt: Double = 0
    @State private var perimeterFt: Double = 0
    @State private var arNote: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    // Header
                    VStack(spacing: OPSStyle.Layout.spacing1) {
                        Text("GENERATE ESTIMATE")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("\(lineItems.count) line items from deck design")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.top, OPSStyle.Layout.spacing2)

                    // AR accuracy warning
                    if let note = arNote {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            Text(note)
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                        .padding(OPSStyle.Layout.spacing2_5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OPSStyle.Colors.warningStatus.opacity(0.15))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }

                    // Category breakdown
                    VStack(spacing: 0) {
                        categoryRow("Surface", items: lineItems.filter { $0.category == "Surface" })
                        categoryRow("Substructure", items: lineItems.filter { $0.category == "Substructure" })
                        categoryRow("Railing", items: lineItems.filter { $0.category == "Railing" })
                        categoryRow("Stairs", items: lineItems.filter { $0.category == "Stairs" })
                        categoryRow("Other", items: lineItems.filter { $0.category == "Other" })
                    }
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Totals
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        if areaSqFt > 0 {
                            totalRow("Total Area", value: "\(Int(areaSqFt.rounded())) sq ft")
                        }
                        if perimeterFt > 0 {
                            totalRow("Total Perimeter", value: "\(Int(perimeterFt.rounded())) lin ft")
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    Spacer(minLength: 20)

                    // Create Estimate button
                    Button {
                        Task {
                            // Check for existing estimate before creating
                            if let existing = await viewModel.checkForDuplicateEstimate() {
                                viewModel.existingEstimate = existing
                                viewModel.showingEstimatePreview = false
                                viewModel.showingDuplicateAlert = true
                            } else {
                                viewModel.showingEstimatePreview = false
                                await viewModel.generateEstimate()
                            }
                        }
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            if viewModel.isGeneratingEstimate {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "doc.text")
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                            }
                            Text("Create Estimate")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .disabled(viewModel.isGeneratingEstimate)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Cancel
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .padding(.bottom, OPSStyle.Layout.spacing3)
                }
            }
            .background(OPSStyle.Colors.background)
            .navigationBarHidden(true)
        }
        .onAppear {
            // Use the merged catalog/legacy result so the preview reflects
            // exactly what generateEstimate() will persist — adapter rows
            // win for component_types with a CompanyDefaultProduct,
            // legacy fills the gap (deck-catalog spec § 4.5).
            lineItems = viewModel.mergedCatalogLineItems()
            areaSqFt = EstimateGeneratorService.calculateAreaSqFt(drawingData: viewModel.drawingData)
            perimeterFt = EstimateGeneratorService.calculatePerimeterFt(drawingData: viewModel.drawingData)
            arNote = EstimateGeneratorService.arAccuracyNote(from: viewModel.drawingData)
        }
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(_ name: String, items: [CatalogEstimateMerger.LineItem]) -> some View {
        if !items.isEmpty {
            HStack {
                Text(name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Text("\(items.count) items")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                // Show aggregate quantity for railing
                if name == "Railing" {
                    let totalLinFt = items.filter { $0.unit == "linear ft" }.reduce(0.0) { $0 + $1.quantity }
                    if totalLinFt > 0 {
                        Text("(\(Int(totalLinFt.rounded())) lin ft)")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.cardBackground)

            Divider()
                .background(OPSStyle.Colors.secondaryText.opacity(0.2))
        }
    }

    // MARK: - Total Row

    private func totalRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}
