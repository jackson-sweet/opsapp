//
//  FormInputs.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI
import UIKit
import Combine

/// Reusable form field component with consistent styling
struct FormField: View {
    var title: String
    var placeholder: String = ""
    @Binding var text: String
    var isEditable: Bool = true
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isEditable {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                        .keyboardType(keyboardType)
                        .padding()
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                } else {
                    TextField(placeholder, text: $text)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                        .keyboardType(keyboardType)
                        .padding()
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                }
            } else {
                Text(text.isEmpty ? "Not set" : text)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(text.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }
}

/// Reusable form TextEditor component with consistent styling
struct FormTextEditor: View {
    var title: String
    var placeholder: String = ""
    @Binding var text: String
    var isEditable: Bool = true
    var height: CGFloat = 150
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isEditable {
                ZStack(alignment: .topLeading) {
                    // iOS 16 compatibility handling 
                    ZStack {
                        OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        
                        TextEditor(text: $text)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(.white)
                            .background(Color.clear)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .frame(height: height)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                    )
                    
                    if text.isEmpty {
                        Text(placeholder)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                Text(text.isEmpty ? "Not set" : text)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(text.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: height, alignment: .topLeading)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }
}

/// Standard toggle component with consistent styling and labeling
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
                    .foregroundColor(.white)
                
                Text(description)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
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
            .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

/// Standard radio button option component for option selection
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
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(isSelected ? 
                                OPSStyle.Colors.primaryAccent : 
                                OPSStyle.Colors.secondaryText.opacity(0.5),
                                lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}

/// Standard search bar component with consistent styling
struct SearchBar: View {
    @Binding var searchText: String
    var placeholder: String = "Search..."
    var onSearch: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                TextField(placeholder, text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(.white)
                    .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { _ in
                        onSearch?()
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        onSearch?()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}

/// Standard empty state view with consistent styling
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
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, 8)
                Spacer()
            }
            
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(message)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}



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
                icon: "folder.fill",
                title: "No projects found",
                message: "Projects you've worked on will appear here"
            )
        }
        .padding()
        .background(OPSStyle.Colors.backgroundGradient)
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