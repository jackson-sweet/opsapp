//
//  VinylOrderSettingsControls.swift
//  OPS
//
//  The vinyl order's layout settings — RUN, PATTERN, LOCK RUN, and the ROLL /
//  SEAM / WRAP counters — as one component.
//
//  These used to exist twice: once in `VinylOrderSheet` and once in the bulk
//  wizard's LAYOUT section, with slightly different controls (the sheet still
//  used stock `Stepper`, whose hit targets sit far under 44pt — bug 1a8e48af,
//  "+/- need padding"). The full-screen workspace needs the same set again, so
//  they live here: one grammar, one set of bounds, one edit path.
//
//  Every mutation goes through `VinylOrderSettingsEdit`, so a tap that changes
//  nothing — re-selecting the segment already selected — neither writes the
//  binding nor asks the parent to re-plan.
//

import SwiftUI
import UIKit

/// One change the settings controls can make, as a value transform. Keeping
/// the mutation out of the view is what makes the write-then-re-plan contract
/// provable without driving SwiftUI.
enum VinylOrderSettingsEdit: Equatable {
    case direction(VinylLayoutDirection)
    case pattern(VinylPatternMode)
    case lockRun(Bool)
    case rollWidth(Double)
    case seamOverlap(Double)
    case edgeWrap(Double)

    func applied(to settings: VinylOrderSettings) -> VinylOrderSettings {
        var next = settings
        switch self {
        case .direction(let direction):
            next.direction = direction
        case .pattern(let mode):
            next.patternMode = mode
            // A linear pattern runs one way across the whole deck; it cannot
            // change direction at a wall, so picking it releases the lock.
            if mode == .linear {
                next.allowsDirectionalChanges = false
            }
        case .lockRun(let locked):
            next.allowsDirectionalChanges = !locked
        case .rollWidth(let inches):
            next.rollWidthInches = inches
        case .seamOverlap(let inches):
            next.seamOverlapInches = inches
        case .edgeWrap(let inches):
            next.edgeWrapInches = inches
        }
        return next
    }
}

struct VinylOrderSettingsControls: View {
    @Binding var settings: VinylOrderSettings
    /// Re-plan. Fires once per accepted edit — never on a no-op tap.
    let onChange: () -> Void

    /// At accessibility sizes the label column and the segments cannot both fit
    /// on one line: `PATTERN` broke mid-word into `PATT`/`ERN` and `LENGTH` /
    /// `WIDTH` truncated to `LEN…` / `WID…`. The row stacks instead.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: Bounds — the ranges the sheet and the wizard have always used

    static let rollWidthRange: ClosedRange<Double> = 24...144
    static let rollWidthStep: Double = 6
    static let seamRange: ClosedRange<Double> = 0...12
    static let seamStep: Double = 0.25
    static let wrapRange: ClosedRange<Double> = 0...18
    static let wrapStep: Double = 0.5

    // MARK: Edit resolution

    /// The settings an edit would produce, or nil when it would change nothing.
    static func resolve(
        _ edit: VinylOrderSettingsEdit,
        for settings: VinylOrderSettings
    ) -> VinylOrderSettings? {
        let next = edit.applied(to: settings)
        return next == settings ? nil : next
    }

    static func stepped(
        _ value: Double,
        by step: Double,
        in range: ClosedRange<Double>
    ) -> Double {
        min(range.upperBound, max(range.lowerBound, value + step))
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            segmentRow(
                label: "RUN",
                options: VinylLayoutDirection.allCases,
                selected: settings.direction,
                optionLabel: \.label
            ) { .direction($0) }

            segmentRow(
                label: "PATTERN",
                options: VinylPatternMode.allCases,
                selected: settings.patternMode,
                optionLabel: \.label
            ) { .pattern($0) }

            // Only a solid colour can change direction at a wall, so the lock
            // is meaningless — and absent — under a linear pattern.
            if settings.patternMode == .solid {
                lockRunRow
            }

            counterRow(
                label: "ROLL",
                value: settings.rollWidthInches,
                range: Self.rollWidthRange,
                step: Self.rollWidthStep,
                edit: VinylOrderSettingsEdit.rollWidth
            )

            counterRow(
                label: "SEAM",
                value: settings.seamOverlapInches,
                range: Self.seamRange,
                step: Self.seamStep,
                edit: VinylOrderSettingsEdit.seamOverlap
            )

            counterRow(
                label: "WRAP",
                value: settings.edgeWrapInches,
                range: Self.wrapRange,
                step: Self.wrapStep,
                edit: VinylOrderSettingsEdit.edgeWrap
            )
        }
    }

    // MARK: Rows

    private func segmentRow<Option: Hashable>(
        label: String,
        options: [Option],
        selected: Option,
        optionLabel: KeyPath<Option, String>,
        edit: @escaping (Option) -> VinylOrderSettingsEdit
    ) -> some View {
        let segments = HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    apply(edit(option))
                } label: {
                    Text(option[keyPath: optionLabel])
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(
                            option == selected
                                ? OPSStyle.Colors.text
                                : OPSStyle.Colors.text2
                        )
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .background(
                            option == selected
                                ? OPSStyle.Colors.surfaceActive
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selected ? [.isSelected] : [])
            }
        }
        .background(OPSStyle.Colors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    rowLabel(label)
                    segments
                }
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    rowLabel(label)
                    segments
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// The house switch tint — a brighter white track, never an accent
    /// (MOBILE.md §9). The row keeps the same label grammar as the segments
    /// above it so the stack reads as one column.
    private var lockRunRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("LOCK RUN")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.text3)
                Text(settings.allowsDirectionalChanges ? "MIXED" : "ONE DIRECTION")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text2)
            }

            Spacer(minLength: OPSStyle.Layout.spacing2)

            Toggle("", isOn: Binding(
                get: { !settings.allowsDirectionalChanges },
                set: { apply(.lockRun($0)) }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lock run")
    }

    private func counterRow(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        edit: @escaping (Double) -> VinylOrderSettingsEdit
    ) -> some View {
        OPSCounterRow(
            label: label,
            value: vinylFormatInches(value),
            canDecrement: value > range.lowerBound,
            canIncrement: value < range.upperBound,
            onDecrement: { apply(edit(Self.stepped(value, by: -step, in: range))) },
            onIncrement: { apply(edit(Self.stepped(value, by: step, in: range))) }
        )
    }

    /// The fixed label column is what keeps the stack reading as one column —
    /// but it is only wide enough for the default type scale, so a stacked
    /// accessibility row lets the label take the width the word needs.
    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.text3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                width: dynamicTypeSize.isAccessibilitySize ? nil : VinylOrderLayout.labelWidth,
                alignment: .leading
            )
    }

    // MARK: Applying

    private func apply(_ edit: VinylOrderSettingsEdit) {
        guard let next = Self.resolve(edit, for: settings) else { return }
        settings = next
        onChange()
        feedback(for: edit)
    }

    /// `OPSCounterRow` fires its own light impact, so the counters are left
    /// alone here — a second generator on the same tap is haptic spam.
    private func feedback(for edit: VinylOrderSettingsEdit) {
        switch edit {
        case .direction, .pattern, .lockRun:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .rollWidth, .seamOverlap, .edgeWrap:
            break
        }
    }
}
