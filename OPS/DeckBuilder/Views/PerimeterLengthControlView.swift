// OPS/OPS/DeckBuilder/Views/PerimeterLengthControlView.swift

import SwiftUI

struct PerimeterLengthControlView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel

    private var selectedDirection: PerimeterDirection? {
        viewModel.perimeterEntry.selectedDirection
    }

    var body: some View {
        DeckMeasurementPickerView(
            title: "LENGTH",
            value: perimeterLengthBinding,
            leadingSystemImage: selectedDirection?.systemImage,
            message: viewModel.perimeterEntryMessage,
            onBack: {
                viewModel.stepBackPerimeterEntry()
            },
            onCommit: { _ in
                _ = viewModel.commitPerimeterLength()
            }
        )
    }

    private var perimeterLengthBinding: Binding<DeckMeasurementValue> {
        Binding(
            get: {
                viewModel.perimeterEntry.lengthDraft
                    ?? .zero(system: viewModel.drawingData.config.measurementSystem)
            },
            set: { value in
                viewModel.updatePerimeterLength(value)
            }
        )
    }
}
