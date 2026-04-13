//
//  SegmentedControl.swift
//  OPS
//
//  Reusable segmented control component matching OPS design system
//

import SwiftUI

/// How a single segment is rendered. Text for labeled pickers, icon for
/// compact icon-only pickers like a 2D/3D toggle.
fileprivate enum SegmentContent: Equatable {
    case text(String)
    case icon(systemName: String)
}

struct SegmentedControl<SelectionValue>: View where SelectionValue: Hashable {
    @Binding var selection: SelectionValue
    fileprivate let segments: [(value: SelectionValue, content: SegmentContent)]

    /// Text-labeled segments. Labels are uppercased for display.
    init(selection: Binding<SelectionValue>, options: [(SelectionValue, String)]) {
        self._selection = selection
        self.segments = options.map { (value: $0.0, content: .text($0.1)) }
    }

    /// Icon-only segments. Each value is paired with an SF Symbol name.
    /// Best for compact toggles (e.g. 2D/3D view mode) where text labels
    /// would be redundant or overflow the available width.
    init(selection: Binding<SelectionValue>, iconOptions: [(SelectionValue, String)]) {
        self._selection = selection
        self.segments = iconOptions.map { (value: $0.0, content: .icon(systemName: $0.1)) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.value) { segment in
                SegmentButton(
                    content: segment.content,
                    isSelected: selection == segment.value,
                    action: {
                        withAnimation(OPSStyle.Animation.fast) {
                            selection = segment.value
                        }
                    }
                )
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

private struct SegmentButton: View {
    let content: SegmentContent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                switch content {
                case .text(let title):
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                case .icon(let systemName):
                    Image(systemName: systemName)
                        .font(.system(
                            size: OPSStyle.Layout.IconSize.md,
                            weight: .semibold
                        ))
                }
            }
            .foregroundColor(isSelected ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isSelected {
                        Color.white
                    } else {
                        Color.clear
                    }
                }
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}

// Convenience initializer for enum-based selections
extension SegmentedControl where SelectionValue: CaseIterable & RawRepresentable, SelectionValue.RawValue == String {
    init(selection: Binding<SelectionValue>) {
        let options = SelectionValue.allCases.map { ($0, $0.rawValue) }
        self.init(selection: selection, options: options)
    }
}

// MARK: - Settings Segmented Picker

/// Subtle segmented picker for settings screens (permissions, notifications).
/// Uses `subtleBackground` fill for selected segment, `tertiaryText` for unselected.
/// Supports optional "mixed" state where no segment is highlighted.
struct SettingsSegmentedPicker<SelectionValue>: View where SelectionValue: Hashable {
    let selection: SelectionValue?
    let options: [(value: SelectionValue, label: String)]
    let isMixed: Bool
    let onChange: (SelectionValue) -> Void

    init(
        selection: SelectionValue?,
        options: [(SelectionValue, String)],
        isMixed: Bool = false,
        onChange: @escaping (SelectionValue) -> Void
    ) {
        self.selection = selection
        self.options = options.map { (value: $0.0, label: $0.1) }
        self.isMixed = isMixed
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onChange(option.value)
                }) {
                    Text(option.label)
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.3)
                        .foregroundColor(
                            !isMixed && selection == option.value
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(
                                    !isMixed && selection == option.value
                                        ? OPSStyle.Colors.subtleBackground
                                        : Color.clear
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.subtleBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
        )
        // Always fully interactive — mixed state just means no segment is highlighted
    }
}

/// Convenience initializer for CaseIterable enums
extension SettingsSegmentedPicker where SelectionValue: CaseIterable & RawRepresentable, SelectionValue.RawValue == String {
    init(
        selection: SelectionValue?,
        isMixed: Bool = false,
        onChange: @escaping (SelectionValue) -> Void
    ) {
        let options = SelectionValue.allCases.map { ($0, $0.rawValue) }
        self.init(selection: selection, options: options, isMixed: isMixed, onChange: onChange)
    }
}

// Preview
struct SegmentedControl_Previews: PreviewProvider {
    enum TestTab: String, CaseIterable {
        case settings = "Settings"
        case data = "Data"
    }
    
    static var previews: some View {
        VStack(spacing: 20) {
            // Enum-based
            SegmentedControl(selection: .constant(TestTab.settings))
                .padding()
            
            // Custom options
            SegmentedControl(
                selection: .constant("option1"),
                options: [
                    ("option1", "Option 1"),
                    ("option2", "Option 2"),
                    ("option3", "Option 3")
                ]
            )
            .padding()
        }
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
    }
}