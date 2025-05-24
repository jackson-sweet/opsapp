//
//  SegmentedControl.swift
//  OPS
//
//  Reusable segmented control component matching OPS design system
//

import SwiftUI

struct SegmentedControl<SelectionValue>: View where SelectionValue: Hashable {
    @Binding var selection: SelectionValue
    let options: [(value: SelectionValue, label: String)]
    
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
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = option.value
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
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.bodyBold)
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