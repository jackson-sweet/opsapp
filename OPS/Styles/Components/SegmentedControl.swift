//
//  SegmentedControl.swift
//  OPS
//
//  Segmented control — spec v2 (2026-04-17).
//
//  Selected indicator: **underline bar only — no fill, no border box, no accent.**
//  Typography-only differentiation: selected = `text` full, unselected = `text-3`.
//  Underline bar animates to the selected segment (200ms, `easeSmooth`).
//

import SwiftUI

struct SegmentedControl<SelectionValue>: View where SelectionValue: Hashable {
    @Binding var selection: SelectionValue
    let options: [(value: SelectionValue, label: String)]

    @Namespace private var underlineNamespace

    init(selection: Binding<SelectionValue>, options: [(SelectionValue, String)]) {
        self._selection = selection
        self.options = options.map { (value: $0.0, label: $0.1) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                SegmentButton(
                    title: option.label,
                    isSelected: selection == option.value,
                    namespace: underlineNamespace,
                    action: {
                        withAnimation(OPSStyle.Animation.panel) {
                            selection = option.value
                        }
                    }
                )
            }
        }
    }
}

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.section) // Cake Mono Light 18pt — reduce tracking to keep tight
                    .tracking(0.08 * 13)
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)

                // Underline bar — the only selected-state affordance
                ZStack {
                    if isSelected {
                        Rectangle()
                            .fill(OPSStyle.Colors.text)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "segment-underline", in: namespace)
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// Convenience initializer for enum-based selections
extension SegmentedControl where SelectionValue: CaseIterable & RawRepresentable, SelectionValue.RawValue == String {
    init(selection: Binding<SelectionValue>) {
        let options = SelectionValue.allCases.map { ($0, $0.rawValue) }
        self.init(selection: selection, options: options)
    }
}

// MARK: - Previews

struct SegmentedControl_Previews: PreviewProvider {
    enum TestTab: String, CaseIterable {
        case settings = "Settings"
        case data = "Data"
    }

    static var previews: some View {
        VStack(spacing: 32) {
            SegmentedControl(selection: .constant(TestTab.settings))
                .padding(.horizontal)

            SegmentedControl(
                selection: .constant("option1"),
                options: [
                    ("option1", "Option 1"),
                    ("option2", "Option 2"),
                    ("option3", "Option 3")
                ]
            )
            .padding(.horizontal)
        }
        .padding(.vertical, 40)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
    }
}
