// OPS/OPS/DeckBuilder/Views/PerimeterLengthControlView.swift

import SwiftUI

enum PerimeterSpeedDrawToolbarPolicy {
    static func showsSpeedDrawToolbar(for entry: PerimeterEntryMode) -> Bool {
        entry.activeAnchor != nil
    }

    static func showsStandardToolbar(for entry: PerimeterEntryMode) -> Bool {
        !showsSpeedDrawToolbar(for: entry)
    }
}

struct PerimeterSpeedDrawToolbarView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.perimeterEntry {
            case .idle:
                EmptyView()
            case .choosingDirection(let anchor):
                directionSelectionRow(anchor: anchor)
            case .enteringLength(_, _, _):
                PerimeterLengthControlView(viewModel: viewModel)
            }
        }
        .background(OPSStyle.Colors.cardBackground)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(OPSStyle.Animation.panel, value: viewModel.perimeterEntry)
    }

    private func directionSelectionRow(anchor: PerimeterEntryAnchor) -> some View {
        HStack(spacing: DeckMeasurementPickerTokens.standardGap) {
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
                    .measurementControlChrome()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit speed draw")

            VStack(alignment: .leading, spacing: 3) {
                Text("// POINT LOCKED")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)

                HStack(spacing: DeckMeasurementPickerTokens.tightGap) {
                    Image(systemName: "scope")
                        .font(.system(size: DeckMeasurementPickerTokens.smallIconSize, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.opsAccent)
                    Text(anchor.usesRelativeDirections ? "ANGLE" : "COMPASS")
                        .font(OPSStyle.Typography.badgeCake)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: DeckMeasurementPickerTokens.iconSize, weight: .medium))
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(
                    width: DeckMeasurementPickerTokens.minTouch,
                    height: DeckMeasurementPickerTokens.minTouch
                )
                .measurementControlChrome()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DeckMeasurementPickerTokens.panelPadding)
        .padding(.vertical, DeckMeasurementPickerTokens.standardGap)
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
