//
//  SettingsComponents.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import SwiftUI

// MARK: - Header Components

struct SettingsHeader: View {
    var title: String
    var showEditButton: Bool = false
    var isEditing: Bool = false
    var onBackTapped: () -> Void
    var onEditTapped: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            // Back button with consistent styling
            Button(action: {
                onBackTapped()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
            
            Spacer()
            
            // Title with consistent styling
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Edit button or spacer for balance
            if showEditButton {
                Button(action: {
                    onEditTapped?()
                }) {
                    Text(isEditing ? "Cancel" : "Edit")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .frame(width: 80, height: 44)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(12)
            } else {
                // Empty spacer to balance the header
                Spacer()
                    .frame(width: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

// MARK: - Card Components

struct SettingsCard<Content: View>: View {
    var title: String
    var content: Content
    var showTitle: Bool = true
    
    init(title: String, showTitle: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.showTitle = showTitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showTitle {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            content
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}

struct SettingsSectionHeader: View {
    var title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }
}

// MARK: - Form Controls

struct SettingsToggle: View {
    var title: String
    var description: String
    @Binding var isOn: Bool
    var onToggleChanged: ((Bool) -> Void)? = nil
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 13))
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
        .cornerRadius(12)
    }
}

struct SettingsButton: View {
    var title: String
    var icon: String
    var style: ButtonStyle = .primary
    var action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        
        var textColor: Color {
            switch self {
            case .primary:
                return .black
            case .secondary:
                return .white
            case .destructive:
                return .white
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .primary:
                return OPSStyle.Colors.primaryAccent
            case .secondary:
                return OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
            case .destructive:
                return OPSStyle.Colors.errorStatus
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(style.textColor)
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(style.textColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(style.backgroundColor)
            .cornerRadius(12)
        }
    }
}

struct SettingsCategoryButton: View {
    var title: String
    var description: String
    var icon: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon in colored circle
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
        }
    }
}

struct SettingsField: View {
    var title: String
    var placeholder: String = ""
    @Binding var text: String
    var isEditable: Bool = true
    var isSecure: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            if isEditable {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding()
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                } else {
                    TextField(placeholder, text: $text)
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding()
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                }
            } else {
                Text(text.isEmpty ? "Not set" : text)
                    .font(.system(size: 16))
                    .foregroundColor(text.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
            }
        }
    }
}