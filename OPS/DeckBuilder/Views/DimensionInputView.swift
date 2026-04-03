// OPS/OPS/DeckBuilder/Views/DimensionInputView.swift

import SwiftUI

struct DimensionInputView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool

    private var currentEdge: DeckEdge? {
        guard let edgeId = viewModel.editingEdgeId else { return nil }
        return viewModel.drawingData.edge(byId: edgeId)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Current dimension display
                if let edge = currentEdge, let dim = edge.dimension {
                    Text(DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                } else {
                    Text("No dimension set")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                // Input field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter dimension")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextField(
                        viewModel.drawingData.config.measurementSystem == .imperial
                            ? "e.g., 24' 6\""
                            : "e.g., 7.5m",
                        text: $inputText
                    )
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($isFocused)
                    .padding(16)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button("Clear") {
                        inputText = ""
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)

                    Button("Confirm") {
                        applyDimension()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }

                // Scale auto-fill option
                if viewModel.drawingData.scaleFactor != nil && viewModel.isClosed {
                    Button {
                        viewModel.autoFillDimensionsFromScale()
                        dismiss()
                    } label: {
                        Label("Auto-fill from scale", systemImage: "wand.and.stars")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(OPSStyle.Colors.background)
            .navigationTitle("Dimension")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if let edge = currentEdge, let dim = edge.dimension {
                inputText = DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem)
            }
            isFocused = true
        }
    }

    private func applyDimension() {
        guard let edgeId = viewModel.editingEdgeId else { return }
        if let inches = DimensionEngine.parseToInches(inputText, system: viewModel.drawingData.config.measurementSystem) {
            viewModel.setEdgeDimension(edgeId, inches: inches)
        }
        dismiss()
    }
}
