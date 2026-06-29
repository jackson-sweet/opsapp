// OPS/OPS/DeckBuilder/Views/PerimeterLengthControlView.swift

import SwiftUI

enum PerimeterSpeedDrawOverlayLayout {
    static let touchZoneHeightFraction: CGFloat = 0.4

    static var overlayMaxWidth: CGFloat { DeckMeasurementPickerTokens.panelMaxWidth }
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
                .padding(DeckMeasurementPickerTokens.standardGap)
                .frame(maxWidth: PerimeterSpeedDrawOverlayLayout.overlayMaxWidth)
                // Same L1 plate + hit-shield as the length panel so this state's
                // bottom zone is a contained instrument (not a lone floating x),
                // and gap-taps can't fall through to the canvas reorient drag.
                .measurementControlChrome(cornerRadius: DeckMeasurementPickerTokens.panelRadius)
                .contentShape(RoundedRectangle(cornerRadius: DeckMeasurementPickerTokens.panelRadius, style: .continuous))
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
                .font(.system(size: DeckMeasurementPickerTokens.smallIconSize, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(
                    width: DeckMeasurementPickerTokens.minTouch,
                    height: DeckMeasurementPickerTokens.minTouch
                )
                .measurementControlChrome(flat: true)
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
