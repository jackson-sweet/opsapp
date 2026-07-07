//
//  VinylOrderConfirmSheet.swift
//  OPS
//
//  The MARK ORDERED confirm step (spec § 5.2). Every orderable quantity is
//  pre-filled with the calculator's suggestion and made nudgeable, so the frozen
//  record captures what was ACTUALLY ordered — spare sticks, a rounded-up glue
//  count, a full roll bought whole. Confirming returns a
//  `DeckMaterialsOrderConfirmation`; the caller freezes it via
//  `DeckMaterialsOrderService.markOrdered(confirmed:)`.
//
//  Roll mode swaps the vinyl line to ROLLS with a read-only ≈ SQ FT echo; cut-list
//  mode shows ORDER SQ FT. Sticks and glue are identical in both modes. The
//  geometry drift signal is never derived from these edits — a hand-edit here can
//  never flag DESIGN CHANGED SINCE ORDER.
//
//  OPS section styling, OPSStyle tokens only. Copy is product register: terse,
//  UPPERCASE authority labels, sentence-case hint, no exclamation.
//

import SwiftUI
import UIKit

/// Everything a MARK ORDERED entry point needs to present `VinylOrderConfirmSheet`
/// and, on confirm, freeze the order through `markOrdered(confirmed:)`. Both entry
/// points (the Vinyl Order sheet and the Details-tab marker) resolve one of these
/// and drive an identical confirm-then-freeze flow. `Identifiable` so it can back a
/// `.sheet(item:)`.
struct PendingVinylOrderConfirm: Identifiable {
    let id = UUID()
    let design: DeckDesign
    let materials: DeckMaterialsList
    let settings: DeckMaterialsSettings
    let vinylSettings: VinylOrderSettings
    let projectId: String
    let projectTitle: String
    let deckTitle: String

    /// The calculator's suggestion — the confirm sheet's pre-fill and RESET target.
    var calculated: DeckMaterialsOrderConfirmation {
        DeckMaterialsOrderConfirmation.calculated(from: materials, settings: settings)
    }

    var rollWidthInches: Double { vinylSettings.rollWidthInches }
}

struct VinylOrderConfirmSheet: View {
    let projectTitle: String
    let deckTitle: String
    /// Roll width (inches) of the ordered vinyl — drives the roll-mode ≈ SQ FT echo.
    let rollWidthInches: Double
    /// The calculator's suggestion — the RESET target and the isEdited baseline.
    let calculated: DeckMaterialsOrderConfirmation
    let onConfirm: (DeckMaterialsOrderConfirmation) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The operator's working copy. Seeded from `initial` — which equals
    /// `calculated` on a first order, or the stored order values when re-opened
    /// via EDIT ORDER (spec § 6: pre-fill with the current snapshot, not the calc).
    @State private var draft: DeckMaterialsOrderConfirmation

    init(
        projectTitle: String,
        deckTitle: String,
        rollWidthInches: Double,
        calculated: DeckMaterialsOrderConfirmation,
        initial: DeckMaterialsOrderConfirmation? = nil,
        onConfirm: @escaping (DeckMaterialsOrderConfirmation) -> Void
    ) {
        self.projectTitle = projectTitle
        self.deckTitle = deckTitle
        self.rollWidthInches = rollWidthInches
        self.calculated = calculated
        self.onConfirm = onConfirm
        self._draft = State(initialValue: initial ?? calculated)
    }

    private var isRollMode: Bool { draft.orderMode == .fullRolls }
    private var isEdited: Bool { draft.differs(fromCalculated: calculated) }

    /// Area the ordered rolls yield: rolls × full-roll length × roll width.
    private var rollEchoSqFt: Int {
        max(0, Int((Double(draft.rollCount) * draft.fullRollLengthFeet * rollWidthInches / 12.0).rounded()))
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        header
                        vinylSection
                        consumablesSection
                        resetButton
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
                footer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("// CONFIRM ORDER")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            Text("\(projectTitle.uppercased()) · \(deckTitle.uppercased())")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Adjust any line to what you actually ordered.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Vinyl

    @ViewBuilder
    private var vinylSection: some View {
        section(title: "VINYL") {
            if isRollMode {
                quantityStepper(label: "ROLLS", value: $draft.rollCount, range: 0...500, step: 1)
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("≈ \(rollEchoSqFt) SQ FT")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Text("@ \(Int(draft.fullRollLengthFeet))' × \(Int(rollWidthInches.rounded()))\"")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .monospacedDigit()
                }
            } else {
                quantityStepper(label: "ORDER SQ FT", value: $draft.vinylOrderedSqFt, range: 0...20000, step: 5)
            }
        }
    }

    // MARK: - Flashing & glue

    private var consumablesSection: some View {
        section(title: "FLASHING & GLUE") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                quantityStepper(label: "DRIP STICKS", value: $draft.dripSticks, range: 0...999, step: 1)
                quantityStepper(label: "CLIP STICKS", value: $draft.clipSticks, range: 0...999, step: 1)
                quantityStepper(label: "90 STICKS", value: $draft.ninetySticks, range: 0...999, step: 1)
                quantityStepper(label: "GLUE BUCKETS", value: $draft.glueBuckets, range: 0...999, step: 1)
            }
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            draft = calculated
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text("RESET TO CALCULATED")
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEdited)
        .opacity(isEdited ? 1 : 0.4)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onConfirm(draft)
                dismiss()
            } label: {
                Text("CONFIRM ORDERED")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.primaryAccent)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Reusable pieces

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func quantityStepper(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)
                Text("\(value.wrappedValue)")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }
}
