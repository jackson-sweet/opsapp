//
//  SettingsComponents.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import SwiftUI
import Foundation

// MARK: - Header Components

struct SettingsHeader: View {
    var title: String
    var showEditButton: Bool = false
    var isEditing: Bool = false
    var editButtonText: String? = nil
    var onBackTapped: () -> Void
    var onEditTapped: (() -> Void)? = nil

    var body: some View {
        HStack {
            // Back button — clean, no card background
            Button(action: {
                onBackTapped()
            }) {
                Image(systemName: OPSStyle.Icons.chevronLeft)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(width: 44, height: 44)

            Spacer()

            // Title — centered, bodyBold matching expense form toolbar
            Text(title.uppercased())
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            // Edit button or spacer for balance
            if showEditButton {
                Button(action: {
                    onEditTapped?()
                }) {
                    Text((editButtonText ?? (isEditing ? "Cancel" : "Edit")).uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .frame(height: 44)
            } else {
                // Empty spacer to balance the header
                Spacer()
                    .frame(width: 44)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
    }
}

// MARK: - Tab Components

struct SettingsTabSelector: View {
    enum Tab: String, CaseIterable {
        case settings = "Settings"
        case data = "Data"
    }
    
    @Binding var selectedTab: Tab
    
    var body: some View {
        SegmentedControl(selection: $selectedTab)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }
}

// Legacy implementation kept for reference but simplified
private struct LegacySettingsTabSelector: View {
    @Binding var selectedTab: SettingsTabSelector.Tab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTabSelector.Tab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(OPSStyle.Animation.fast) {
                        selectedTab = tab
                    }
                }) {
                    if selectedTab == tab {
                        ZStack{
                            Rectangle()
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            Text(tab.rawValue)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.invertedText)
                                
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                    } else {
                        Text(tab.rawValue)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                    }
                    
                }
            }
        }
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .padding(.bottom, OPSStyle.Layout.spacing2)
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
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            if showTitle {
                Text(title)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            content
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }
}

struct SettingsSectionHeader: View {
    var title: String
    
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing4)
                .padding(.bottom, OPSStyle.Layout.spacing2)
            Spacer()
        }
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
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(description)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(1.5)
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
        .padding(OPSStyle.Layout.spacing3)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
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
                return OPSStyle.Colors.invertedText
            case .secondary:
                return OPSStyle.Colors.primaryText
            case .destructive:
                return OPSStyle.Colors.primaryText
            }
        }

        var backgroundColor: Color {
            switch self {
            case .primary:
                return OPSStyle.Colors.primaryAccent
            case .secondary:
                return OPSStyle.Colors.surfaceInput
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
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(style.textColor)
                }
                
                Text(title)
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(style.textColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .background(style.backgroundColor)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
        }
    }
}

struct SettingsCategoryButton: View {
    var title: String
    var description: String
    var icon: String
    var action: () -> Void
    
    var body: some View {
        ListItem(
            title: title,
            description: description,
            iconName: icon,
            showChevron: true,
            action: action
        )
    }
}

struct SettingsField: View {
    var title: String
    var placeholder: String = ""
    @Binding var text: String
    var isEditable: Bool = true
    var isSecure: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            if isEditable {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding()
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                } else {
                    TextField(placeholder, text: $text)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .autocorrectionDisabled(true)
                        .padding()
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
            } else {
                Text(text.isEmpty ? "Not set" : text)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(text.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }
}

// MARK: - Security Components

struct SecurityPINOption: View {
    var title: String
    var description: String
    var isSelected: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(title)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .stroke(isSelected ?
                                OPSStyle.Colors.text :
                                OPSStyle.Colors.secondaryText.opacity(0.5),
                                lineWidth: OPSStyle.Layout.Border.thick)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(OPSStyle.Colors.text)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface()
        }
    }
}
