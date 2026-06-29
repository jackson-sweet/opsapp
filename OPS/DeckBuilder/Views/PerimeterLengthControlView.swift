// OPS/OPS/DeckBuilder/Views/PerimeterLengthControlView.swift

import SwiftUI

enum PerimeterSpeedDrawOverlayLayout {
    static let touchZoneHeightFraction: CGFloat = 0.4

    // Speed-draw controls span the available width — no fixed cap.
    static var overlayMaxWidth: CGFloat { .infinity }
    static var controlGap: CGFloat { OPSStyle.Layout.spacing2 }
}

enum PerimeterSpeedDrawToolbarPolicy {
    static func showsSpeedDrawToolbar(for entry: PerimeterEntryMode) -> Bool {
        false
    }

    static func showsCanvasOverlay(for entry: PerimeterEntryMode) -> Bool {
        entry.activeAnchor != nil
    }

    static func showsStandardToolbar(for entry: PerimeterEntryMode) -> Bool {
        !showsCanvasOverlay(for: entry)
    }
}

struct PerimeterSpeedDrawOverlayView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel

    var body: some View {
        VStack(spacing: PerimeterSpeedDrawOverlayLayout.controlGap) {
            switch viewModel.perimeterEntry {
            case .idle:
                EmptyView()
            case .choosingDirection:
                HStack(spacing: DeckMeasurementPickerTokens.standardGap) {
                    Text("// POINT LOCKED")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    exitButton
                }
                .frame(maxWidth: .infinity)
                // No card — just a status line and exit, floating over the canvas.
                // The content shape still consumes taps in this strip.
                .contentShape(Rectangle())
            case .enteringLength(_, _, _):
                PerimeterLengthControlView(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(OPSStyle.Animation.panel, value: viewModel.perimeterEntry)
    }

    private var exitButton: some View {
        Button {
            viewModel.cancelPerimeterEntry()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: DeckMeasurementPickerTokens.iconSize, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(
                    width: DeckMeasurementPickerTokens.minTouch,
                    height: DeckMeasurementPickerTokens.minTouch
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exit speed draw")
    }
}

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
            onCancel: {
                viewModel.cancelPerimeterEntry()
            },
            onCommit: { _ in
                _ = viewModel.commitPerimeterLength()
            }
        )
        .frame(maxWidth: PerimeterSpeedDrawOverlayLayout.overlayMaxWidth)
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
