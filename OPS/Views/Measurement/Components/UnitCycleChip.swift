//
//  UnitCycleChip.swift
//  OPS
//
//  Top-right unit chip on `DimensionedAnnotationView` (spec §5.2). Pinned
//  to the photo content area, safe-area aware. Tap cycles imperial fraction
//  → decimal feet → metric (and back). Long-press opens a popover menu with
//  all three options plus a per-user default toggle.
//
//  Visual: 44×30 pt minimum tap target (extends past visible chip via
//  contentShape) showing the current unit short tag — `IN`, `FT`, or `M`.
//  Cake Mono Light 12pt. Glass-dense background. Light haptic on tap.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §5.2
//

import SwiftUI
import UIKit

public struct UnitCycleChip: View {

    @Binding public var unit: DimensionsData.Measurement.DisplayUnit
    @Binding public var saveAsDefault: Bool

    @State private var showingPopover = false
    @State private var dimmedForOverlap = false

    public init(
        unit: Binding<DimensionsData.Measurement.DisplayUnit>,
        saveAsDefault: Binding<Bool> = .constant(false)
    ) {
        self._unit = unit
        self._saveAsDefault = saveAsDefault
    }

    public var body: some View {
        Button(action: cycle) {
            Text(shortTag)
                .font(.custom("CakeMono-Light", size: 12))
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(OPSStyle.Colors.glassBorder, lineWidth: 0.5)
                        )
                )
        }
        .contentShape(Rectangle())
        .frame(minWidth: 44, minHeight: 30, alignment: .trailing)
        .opacity(dimmedForOverlap ? 0.0 : 1.0)
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.15),
                   value: dimmedForOverlap)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingPopover = true
                }
        )
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            popoverBody
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unit: \(shortTag). Tap to cycle.")
        .accessibilityHint("Long press to open unit options.")
    }

    // MARK: - Public hint

    /// Lets the parent view temporarily hide the chip when a measurement
    /// label is about to overlap it (spec §5.2: "Auto-hides for 1.5 s when it
    /// would overlap a measurement label, then re-appears.")
    public func dim(for seconds: Double) {
        dimmedForOverlap = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            dimmedForOverlap = false
        }
    }

    // MARK: - Behaviour

    private var shortTag: String {
        switch unit {
        case .imperialFraction: return "IN"
        case .decimalFeet:      return "FT"
        case .metric:           return "M"
        }
    }

    private func cycle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch unit {
        case .imperialFraction: unit = .decimalFeet
        case .decimalFeet:      unit = .metric
        case .metric:           unit = .imperialFraction
        }
    }

    // MARK: - Popover

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverRow("INCHES (FRACTIONS)", "IN", isOn: unit == .imperialFraction) {
                unit = .imperialFraction; showingPopover = false
            }
            Divider().background(OPSStyle.Colors.line)
            popoverRow("DECIMAL FEET", "FT", isOn: unit == .decimalFeet) {
                unit = .decimalFeet; showingPopover = false
            }
            Divider().background(OPSStyle.Colors.line)
            popoverRow("METRIC", "M", isOn: unit == .metric) {
                unit = .metric; showingPopover = false
            }
            Divider().background(OPSStyle.Colors.line).padding(.vertical, 4)
            Toggle(isOn: $saveAsDefault) {
                Text("SET AS DEFAULT")
                    .font(.custom("CakeMono-Light", size: 11))
                    .tracking(1)
                    .foregroundColor(OPSStyle.Colors.text2)
            }
            .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.opsAccent))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 220)
        .background(OPSStyle.Colors.background)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private func popoverRow(_ title: String, _ tag: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.custom("CakeMono-Light", size: 12))
                    .tracking(1)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
                Text(tag)
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .foregroundColor(isOn ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.text3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
