//
//  FormTextField.swift
//  OPS
//
//  Standardized text field component for forms
//

import SwiftUI

struct FormTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Group {
                if isSecure {
                    SecureField(placeholder.isEmpty ? title : placeholder, text: $text)
                } else {
                    TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                        .keyboardType(keyboardType)
                }
            }
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
            )
        }
    }
}

// Preview
struct FormTextField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            FormTextField(title: "First Name", text: .constant("John"))
            FormTextField(title: "Email", text: .constant(""), placeholder: "Enter your email")
            FormTextField(title: "Phone", text: .constant(""), keyboardType: .phonePad)
        }
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}