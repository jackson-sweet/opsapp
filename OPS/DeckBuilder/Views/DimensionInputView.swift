// OPS/OPS/DeckBuilder/Views/DimensionInputView.swift

import SwiftUI

struct DimensionInputView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool
    @StateObject private var voiceInput = VoiceDimensionInput(expectedDimensionCount: 1)

    private var currentEdge: DeckEdge? {
        guard let edgeId = viewModel.editingEdgeId else { return nil }
        return viewModel.drawingData.edge(byId: edgeId)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: OPSStyle.Layout.spacing4) {
                // Current dimension display
                if let edge = currentEdge, let dim = edge.dimension {
                    Text(DimensionEngine.format(dim, system: viewModel.drawingData.config.measurementSystem))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                } else {
                    Text("No dimension set")
                        .font(OPSStyle.Typography.heading)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                // Input field
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("Enter dimension")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextField(
                        viewModel.drawingData.config.measurementSystem == .imperial
                            ? "e.g., 24' 6\""
                            : "e.g., 7.5m",
                        text: $inputText
                    )
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .onChange(of: inputText) { _, newValue in
                        // Belt-and-suspenders: parser already normalizes smart quotes, but
                        // we also swap them in the field so the visible text always shows
                        // the ASCII `'` / `"` the user thought they typed. Quotes only —
                        // don't rewrite word suffixes mid-keystroke.
                        let sanitized = DimensionEngine.sanitizeQuotesForLiveInput(newValue)
                        if sanitized != newValue { inputText = sanitized }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }

                // Voice input
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    if voiceInput.isListening {
                        VoiceWaveformView(isListening: true)
                            .frame(height: 40)
                    }

                    Button {
                        if voiceInput.isListening {
                            voiceInput.stopListening()
                        } else {
                            isFocused = false
                            voiceInput.startListening()
                        }
                    } label: {
                        Image(systemName: voiceInput.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(voiceInput.isListening ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
                .onChange(of: voiceInput.parsedDimensions) { dims in
                    if let first = dims.first, let inches = first {
                        inputText = DimensionEngine.format(inches, system: viewModel.drawingData.config.measurementSystem)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }

                // Action buttons
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    Button("Clear") {
                        inputText = ""
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)

                    Button("Confirm") {
                        applyDimension()
                    }
                    .font(OPSStyle.Typography.bodyEmphasis)
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
                        Label("Auto-fill from scale", image: OPSStyle.Icons.magicGenerate)
                            .font(OPSStyle.Typography.bodyBold)
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
