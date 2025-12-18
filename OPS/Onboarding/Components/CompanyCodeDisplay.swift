//
//  CompanyCodeDisplay.swift
//  OPS
//
//  Displays company code with [ brackets ] format and copy functionality.
//  Used in ProfileCompany success phase and ProfileJoin code input.
//

import SwiftUI

// MARK: - Company Code Display (Read-only)

/// Displays a company code in [ brackets ] format with copy button
struct CompanyCodeDisplay: View {
    let code: String
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            // Code display with brackets
            codeDisplayView

            // Copy button
            copyButton
        }
    }

    private var codeDisplayView: some View {
        HStack(spacing: 8) {
            Text("[")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text(code)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("]")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = code
            copied = true
            onCopy()

            // Reset copied state after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark" : OPSStyle.Icons.copy)
                    .font(.system(size: 14, weight: .medium))
                Text(copied ? "Copied!" : "Copy Code")
                    .font(OPSStyle.Typography.button)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
    }
}

// MARK: - Company Code Input Field

/// Input field for entering company code with [ brackets ] format
struct CompanyCodeInput: View {
    @Binding var code: String
    let placeholder: String

    init(code: Binding<String>, placeholder: String = "Enter code") {
        self._code = code
        self.placeholder = placeholder
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("[")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            TextField("", text: $code)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .placeholder(when: code.isEmpty) {
                    Text(placeholder)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.placeholderText)
                }

            Text("]")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Company Code Section

/// Complete section with label and code display/input
struct CompanyCodeSection: View {
    let label: String
    let code: String?
    @Binding var inputCode: String
    let isEditable: Bool
    let onCopy: (() -> Void)?

    init(
        label: String = "COMPANY CODE",
        code: String? = nil,
        inputCode: Binding<String> = .constant(""),
        isEditable: Bool = true,
        onCopy: (() -> Void)? = nil
    ) {
        self.label = label
        self.code = code
        self._inputCode = inputCode
        self.isEditable = isEditable
        self.onCopy = onCopy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Label
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Display or Input
            if let code = code, !isEditable {
                CompanyCodeDisplay(code: code) {
                    onCopy?()
                }
            } else {
                CompanyCodeInput(code: $inputCode)
            }
        }
    }
}

// MARK: - Previews

#Preview("Code Display") {
    VStack(spacing: 40) {
        CompanyCodeDisplay(
            code: "ABC123DEF456GHI789JKL012MNO345"
        ) {
            print("Copied!")
        }

        CompanyCodeDisplay(
            code: "SHORTCODE"
        ) {
            print("Copied!")
        }
    }
    .padding(40)
    .background(OPSStyle.Colors.background)
}

#Preview("Code Input") {
    struct PreviewWrapper: View {
        @State private var code = ""

        var body: some View {
            VStack(spacing: 40) {
                CompanyCodeInput(code: $code)

                Text("Entered: \(code)")
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(OPSStyle.Colors.background)
        }
    }

    return PreviewWrapper()
}

#Preview("Code Section") {
    struct PreviewWrapper: View {
        @State private var inputCode = ""

        var body: some View {
            VStack(spacing: 40) {
                // Display mode
                CompanyCodeSection(
                    label: "YOUR COMPANY CODE",
                    code: "ABC123DEF456GHI789JKL012",
                    isEditable: false,
                    onCopy: { print("Copied") }
                )

                // Input mode
                CompanyCodeSection(
                    label: "ENTER COMPANY CODE",
                    inputCode: $inputCode,
                    isEditable: true
                )
            }
            .padding(40)
            .background(OPSStyle.Colors.background)
        }
    }

    return PreviewWrapper()
}
