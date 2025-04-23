//
//  OPSStyle.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// OPSStyle.swift
import SwiftUI

enum OPSStyle {
    // MARK: - Colors
    enum Colors {
        // Brand colors
        static let primaryAccent = Color("AccentPrimary") // Orange
        static let secondaryAccent = Color("AccentSecondary") // Blue for secondary actions
        
        // Background colors
        static let background = Color("Background") // Main background (black)
        static let cardBackground = Color("CardBackground") // Card background (dark gray)
        static let statusBackground = Color("StatusBackground") // Status badge background
        
        // Text colors
        static let primaryText = Color("TextPrimary") // White
        static let secondaryText = Color("TextSecondary") // Light gray
        static let inactiveText = Color("TextInactive") // Dark gray
        
        // Status colors
        static let successStatus = Color("StatusSuccess") // Green
        static let warningStatus = Color("StatusWarning") // Yellow/Orange
        static let errorStatus = Color("StatusError") // Red
        
        // Utility
        static func statusColor(for status: Status) -> Color {
            switch status {
            case .rfq, .estimated:
                return secondaryAccent
            case .accepted:
                return warningStatus
            case .inProgress:
                return primaryAccent
            case .completed:
                return successStatus
            case .closed:
                return inactiveText
            }
        }
    }
    
    // MARK: - Typography
    enum Typography {
        // Title styles
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title = Font.system(size: 28, weight: .bold, design: .default)
        static let subtitle = Font.system(size: 22, weight: .semibold, design: .default)
        
        // Body text
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyBold = Font.system(size: 17, weight: .bold, design: .default)
        
        // Supporting text
        static let caption = Font.system(size: 15, weight: .regular, design: .default)
        static let captionBold = Font.system(size: 15, weight: .bold, design: .default)
        static let smallCaption = Font.system(size: 13, weight: .regular, design: .default)
        
        // Status text
        static let status = Font.system(size: 13, weight: .bold, design: .default).uppercased()
    }
    
    // MARK: - Layout
    enum Layout {
        // Standard spacing
        static let spacing1 = 4.0
        static let spacing2 = 8.0
        static let spacing3 = 16.0
        static let spacing4 = 24.0
        static let spacing5 = 32.0
        
        // Content padding
        static let contentPadding = EdgeInsets(
            top: spacing3,
            leading: spacing3,
            bottom: spacing3,
            trailing: spacing3
        )
        
        // Touch targets - Minimum 44×44 as per Apple HIG, but we go larger for field use
        static let touchTargetMin = 44.0
        static let touchTargetStandard = 56.0
        static let touchTargetLarge = 64.0
        
        // Radius
        static let cornerRadius = 12.0
        static let buttonRadius = 12.0
    }
    
    // MARK: - Animation
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
    }
}

// OPSComponents.swift
import SwiftUI

// MARK: - Buttons
struct PrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(.white)
            .padding()
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
    }
}

struct SecondaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding()
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
            )
    }
}

struct IconActionButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 24))
            .foregroundColor(.white)
            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            .background(Circle().fill(OPSStyle.Colors.primaryAccent))
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: Status
    
    var body: some View {
        Text(status.rawValue.uppercased())
            .font(OPSStyle.Typography.smallCaption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(OPSStyle.Colors.statusColor(for: status))
            .cornerRadius(OPSStyle.Layout.cornerRadius / 2)
    }
}

// MARK: - Cards
struct ProjectCard: View {
    let project: Project
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack {
                    StatusBadge(status: project.status)
                    Spacer()
                    if project.startDate != nil {
                        Text(project.formattedStartDate)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Text(project.title)
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
                
                Text(project.clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(project.address)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }
            .padding(OPSStyle.Layout.contentPadding)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Extension for easy usage
extension View {
    func primaryButtonStyle() -> some View {
        self.modifier(PrimaryButton())
    }
    
    func secondaryButtonStyle() -> some View {
        self.modifier(SecondaryButton())
    }
    
    func iconButtonStyle() -> some View {
        self.modifier(IconActionButton())
    }
}