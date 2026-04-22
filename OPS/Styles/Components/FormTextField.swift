//
//  FormTextField.swift
//  OPS
//
//  Standardized text field component for forms
//

import SwiftUI

// MARK: - Input Type Enum

/// Input field types for OPSProfileInput
enum OPSInputType {
    case text
    case email
    case phone
    case url
    case password

    var keyboardType: UIKeyboardType {
        switch self {
        case .text: return .default
        case .email: return .emailAddress
        case .phone: return .phonePad
        case .url: return .URL
        case .password: return .default
        }
    }

    var autocapitalization: TextInputAutocapitalization {
        switch self {
        case .text: return .words
        case .email, .url, .password: return .never
        case .phone: return .never
        }
    }
}

// MARK: - OPSProfileInput (Unified Profile Input Component)

/// Unified input component for profile and settings screens
/// Provides consistent styling across editable and non-editable inputs
struct OPSProfileInput: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var type: OPSInputType = .text
    var isEditable: Bool = true
    var helperText: String? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label — JetBrains Mono uppercase, tactical
            Text(label.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(0.12 * 14)

            // Input field or display text
            if isEditable {
                editableField
            } else {
                nonEditableField
            }

            // Helper text — bracket-wrapped metadata per spec voice
            if let helper = helperText {
                Text("[\(helper)]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
    }

    // MARK: - Editable Field
    //
    // Spec v2: inputs use `surface-input` fill (rgba 255,255,255,0.04) with `line` border.
    // Focus brightens border to rgba(255,255,255,0.20) — NO accent on input focus rings.
    // (Accent focus is reserved for buttons and system-level focus; inputs are the lone
    // exception that does NOT use accent on focus.)
    private var editableField: some View {
        Group {
            if type == .password {
                SecureField("", text: $text)
                    .placeholder(when: text.isEmpty) {
                        Text(placeholder.isEmpty ? label : placeholder)
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
            } else {
                TextField("", text: $text)
                    .placeholder(when: text.isEmpty) {
                        Text(placeholder.isEmpty ? label : placeholder)
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                    .keyboardType(type.keyboardType)
                    .textInputAutocapitalization(type.autocapitalization)
                    .autocorrectionDisabled()
            }
        }
        .font(OPSStyle.Typography.body)
        .foregroundColor(OPSStyle.Colors.text)
        .tint(OPSStyle.Colors.text)
        .focused($isFocused)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
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
        .onChange(of: isFocused) { _, newValue in
            onFocusChange?(newValue)
        }
    }

    // MARK: - Non-Editable Field

    private var nonEditableField: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(text.isEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: 1)
            )
    }
}

// MARK: - Placeholder View Extension

extension View {
    /// Add placeholder text when the field is empty
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Legacy FormTextField (for backward compatibility)

struct FormTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(0.12 * 14)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isSecure {
                    SecureField("", text: $text)
                        .placeholder(when: text.isEmpty) {
                            Text(placeholder.isEmpty ? title : placeholder)
                                .foregroundColor(OPSStyle.Colors.text3)
                        }
                } else {
                    TextField("", text: $text)
                        .placeholder(when: text.isEmpty) {
                            Text(placeholder.isEmpty ? title : placeholder)
                                .foregroundColor(OPSStyle.Colors.text3)
                        }
                        .keyboardType(keyboardType)
                }
            }
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.text)
            .tint(OPSStyle.Colors.text)
            .focused($isFocused)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
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

// MARK: - Previews

struct FormTextField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // New unified component
            OPSProfileInput(
                label: "First Name",
                text: .constant("John"),
                placeholder: "Enter first name"
            )

            OPSProfileInput(
                label: "Email Address",
                text: .constant("john@example.com"),
                type: .email,
                isEditable: false,
                helperText: "Email cannot be changed"
            )

            OPSProfileInput(
                label: "Phone",
                text: .constant(""),
                placeholder: "Enter phone number",
                type: .phone
            )

            // Legacy component
            FormTextField(title: "Legacy Field", text: .constant("Test"))
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
    }
}