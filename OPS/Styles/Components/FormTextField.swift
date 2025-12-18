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
            // Label
            Text(label.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Input field or display text
            if isEditable {
                editableField
            } else {
                nonEditableField
            }

            // Helper text (if provided)
            if let helper = helperText {
                Text(helper)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .italic()
            }
        }
    }

    // MARK: - Editable Field

    private var editableField: some View {
        Group {
            if type == .password {
                SecureField("", text: $text)
                    .placeholder(when: text.isEmpty) {
                        Text(placeholder.isEmpty ? label : placeholder)
                            .foregroundColor(OPSStyle.Colors.placeholderText)
                    }
            } else {
                TextField("", text: $text)
                    .placeholder(when: text.isEmpty) {
                        Text(placeholder.isEmpty ? label : placeholder)
                            .foregroundColor(OPSStyle.Colors.placeholderText)
                    }
                    .keyboardType(type.keyboardType)
                    .textInputAutocapitalization(type.autocapitalization)
                    .autocorrectionDisabled()
            }
        }
        .font(OPSStyle.Typography.body)
        .foregroundColor(OPSStyle.Colors.primaryText)
        .tint(OPSStyle.Colors.primaryText)
        .focused($isFocused)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.clear)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    isFocused ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                    lineWidth: 1
                )
        )
        .onChange(of: isFocused) { _, newValue in
            onFocusChange?(newValue)
        }
    }

    // MARK: - Non-Editable Field

    private var nonEditableField: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(text.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.tertiaryText.opacity(0.3), lineWidth: 1)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isSecure {
                    SecureField("", text: $text)
                        .placeholder(when: text.isEmpty) {
                            Text(placeholder.isEmpty ? title : placeholder)
                                .foregroundColor(OPSStyle.Colors.placeholderText)
                        }
                } else {
                    TextField("", text: $text)
                        .placeholder(when: text.isEmpty) {
                            Text(placeholder.isEmpty ? title : placeholder)
                                .foregroundColor(OPSStyle.Colors.placeholderText)
                        }
                        .keyboardType(keyboardType)
                }
            }
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .tint(OPSStyle.Colors.primaryText)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
            )
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