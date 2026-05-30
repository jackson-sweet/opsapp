//
//  FormInputs.swift
//  OPS
//
//  Form input primitives — spec v2 (2026-04-17).
//
//  Inputs use `surface-input` fill (rgba 255,255,255,0.04) with `line` border.
//  Focus brightens border to rgba(255,255,255,0.20) — accent is NOT used on input focus.
//  Toggles use text ladder on press/active (no accent). Radio options use `text` (white)
//  for the selected ring, not accent. Search bar matches input surface.
//

import SwiftUI
import UIKit
import Combine

// MARK: - FormField

/// Reusable form field with consistent styling.
struct FormField: View {
    var title: String
    var placeholder: String = ""
    @Binding var text: String
    var isEditable: Bool = true
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(0.12 * 14)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isEditable {
                editableInput
            } else {
                readOnlyValue
            }
        }
    }

    @ViewBuilder
    private var editableInput: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
            }
        }
        .font(OPSStyle.Typography.body)
        .foregroundColor(OPSStyle.Colors.text)
        .tint(OPSStyle.Colors.text)
        .focused($isFocused)
        .padding()
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.buttonRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(
                    isFocused ? Color.white.opacity(0.20) : OPSStyle.Colors.line,
                    lineWidth: 1
                )
        )
        .animation(OPSStyle.Animation.hover, value: isFocused)
    }

    private var readOnlyValue: some View {
        Text(text.isEmpty ? "Not set" : text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(text.isEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.text)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: 1)
            )
    }
}

// MARK: - FormTextEditor

struct FormTextEditor: View {
    var title: String
    var placeholder: String = ""
    @Binding var text: String
    var isEditable: Bool = true
    var height: CGFloat = 150

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(0.12 * 14)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isEditable {
                editableEditor
            } else {
                Text(text.isEmpty ? "Not set" : text)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(text.isEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.text)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: height, alignment: .topLeading)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: 1)
                    )
            }
        }
    }

    private var editableEditor: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                OPSStyle.Colors.surfaceInput
                    .cornerRadius(OPSStyle.Layout.buttonRadius)

                TextEditor(text: $text)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
                    .tint(OPSStyle.Colors.text)
                    .focused($isFocused)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isFocused ? Color.white.opacity(0.20) : OPSStyle.Colors.line,
                        lineWidth: 1
                    )
            )
            .animation(OPSStyle.Animation.hover, value: isFocused)

            if text.isEmpty {
                Text(placeholder)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - FormToggle

/// Toggle with text-ladder behavior. Spec: no accent on toggles.
struct FormToggle: View {
    var title: String
    var description: String
    @Binding var isOn: Bool
    var onToggleChanged: ((Bool) -> Void)? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)

                Text(description)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.text3)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    isOn = newValue
                    onToggleChanged?(newValue)
                }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
        }
        .padding(16)
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.buttonRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: 1)
        )
    }
}

// MARK: - RadioOption

/// Radio option row. Spec: no accent — selected ring and dot use `text` (white).
struct RadioOption: View {
    var title: String
    var description: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text)

                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(2)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.line, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(OPSStyle.Colors.text)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(16)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(isSelected ? Color.white.opacity(0.18) : OPSStyle.Colors.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SearchBar

struct SearchBar: View {
    @Binding var searchText: String
    var placeholder: String = "Search..."
    var onSearch: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack {
                Image(OPSStyle.Icons.search)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text3)

                TextField(placeholder, text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
                    .tint(OPSStyle.Colors.text)
                    .focused($isFocused)
                    .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in
                        onSearch?()
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        onSearch?()
                    }) {
                        Image(OPSStyle.Icons.close)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isFocused ? Color.white.opacity(0.20) : OPSStyle.Colors.line,
                        lineWidth: 1
                    )
            )
            .animation(OPSStyle.Animation.hover, value: isFocused)
        }
    }
}

// MARK: - EmptyStateView

/// Spec: empty states use typography + token value. Icon tint is `text-mute` (decorative only).
/// No illustrations, no coach-marks.
struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .padding(.bottom, 8)
                Spacer()
            }

            Text(title.uppercased())
                .font(OPSStyle.Typography.section)
                .foregroundColor(OPSStyle.Colors.text)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("[\(message)]")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(24)
    }
}

// MARK: - Preview

struct FormComponentsPreview: View {
    @State private var text = "Sample text"
    @State private var emptyText = ""
    @State private var toggleValue = true
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 20) {
            FormField(title: "Name", placeholder: "Enter your name", text: $text)

            FormField(title: "Email", placeholder: "Enter email address", text: $emptyText, keyboardType: .emailAddress)

            FormTextEditor(title: "Notes", placeholder: "Enter any additional notes here...", text: $text)

            FormToggle(title: "Notifications", description: "Enable push notifications for updates", isOn: $toggleValue)

            RadioOption(title: "Standard Delivery", description: "3-5 business days", isSelected: true) {}

            SearchBar(searchText: $searchText, placeholder: "Search projects...")

            EmptyStateView(
                icon: "folder",
                title: "No projects",
                message: "projects will appear here"
            )
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
    }
}

#if swift(>=5.9)
#Preview {
    FormComponentsPreview()
}
#else
struct FormComponentsPreview_Previews: PreviewProvider {
    static var previews: some View {
        FormComponentsPreview()
    }
}
#endif
