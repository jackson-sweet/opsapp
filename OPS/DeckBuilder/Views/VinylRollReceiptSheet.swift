// OPS/OPS/DeckBuilder/Views/VinylRollReceiptSheet.swift

import SwiftUI

/// What the roll-receipt prompt needs to seed physical rolls into tracked stock
/// after a vinyl order is drafted.
struct VinylRollReceiptContext: Identifiable {
    let id = UUID()
    let orderItemId: String?
    let variantId: String
    let variantLabel: String
    let defaultRollCount: Int
    let defaultRollLengthFeet: Double
    let defaultRollWidthInches: Double
}

/// Confirms the rolls received against a drafted vinyl order and commits them to
/// tracked stock (one `catalog_stock_units` roll per physical roll). Only
/// presented for companies running tracked inventory — see
/// `VinylOffcutInventoryService`.
struct VinylRollReceiptSheet: View {
    let context: VinylRollReceiptContext
    /// Returns `true` when the rolls were committed to stock.
    let onReceive: (_ count: Int, _ lengthFeet: Double, _ widthInches: Double) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var rollCount: Int
    @State private var rollLengthFeet: Double
    @State private var rollWidthInches: Double
    @State private var isReceiving = false
    @State private var errorMessage: String?

    init(
        context: VinylRollReceiptContext,
        onReceive: @escaping (_ count: Int, _ lengthFeet: Double, _ widthInches: Double) async -> Bool
    ) {
        self.context = context
        self.onReceive = onReceive
        _rollCount = State(initialValue: max(1, context.defaultRollCount))
        _rollLengthFeet = State(initialValue: max(1, context.defaultRollLengthFeet.rounded()))
        _rollWidthInches = State(initialValue: max(1, context.defaultRollWidthInches.rounded()))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PUT THESE ROLLS ON HAND")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .tracking(0.8)
                        Text(context.variantLabel.uppercased())
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        countStepper
                        valueStepper(label: "LENGTH", suffix: "FT", value: $rollLengthFeet, range: 5...2000, step: 5)
                        valueStepper(label: "WIDTH", suffix: "IN", value: $rollWidthInches, range: 6...144, step: 1)
                    }

                    onHandPreview

                    if let errorMessage {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .tracking(0.6)
                    }

                    Spacer(minLength: 0)

                    receiveButton
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .navigationTitle("// RECEIVE ROLLS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("NOT NOW") { dismiss() }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .disabled(isReceiving)
                }
            }
        }
    }

    private var countStepper: some View {
        Stepper(value: $rollCount, in: 1...50, step: 1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("ROLLS")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 72, alignment: .leading)
                Text("\(rollCount)")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 0)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
        .disabled(isReceiving)
    }

    private func valueStepper(
        label: String,
        suffix: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: 72, alignment: .leading)
                Text("\(Int(value.wrappedValue.rounded())) \(suffix)")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 0)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
        .disabled(isReceiving)
    }

    private var onHandPreview: some View {
        let areaSqFt = Double(rollCount) * rollLengthFeet * (rollWidthInches / 12.0)
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("ADDS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("\(Int(areaSqFt.rounded())) SQ FT")
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.tan)
            Spacer(minLength: 0)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    private var receiveButton: some View {
        Button {
            commit()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if isReceiving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(OPSStyle.Colors.primaryText)
                } else {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                }
                Text(isReceiving ? "RECEIVING…" : "RECEIVE")
                    .font(OPSStyle.Typography.buttonLabel)
                    .tracking(0.8)
            }
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.primaryAccent)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isReceiving)
    }

    private func commit() {
        guard !isReceiving else { return }
        isReceiving = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let success = await onReceive(rollCount, rollLengthFeet, rollWidthInches)
            await MainActor.run {
                isReceiving = false
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                } else {
                    errorMessage = "RECEIVE FAILED"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
