//
//  OPSStyle.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// OPSStyle.swift
import SwiftUI

/// The main styling system for the OPS app
///
/// This file contains the core design system values for the app such as colors,
/// typography, and layout constants. For reusable UI components, see the
/// Styles/Components directory:
///
/// - ButtonStyles.swift - Button styling and components
/// - CardStyles.swift - Card styling and components
/// - CategoryCard.swift - Settings menu category cards
/// - FormInputs.swift - Text inputs and form controls
/// - IconBadge.swift - Icon badge styling
/// - ListItems.swift - List item row styling
/// - OPSComponents.swift - Component documentation and legacy components
/// - ProfileCard.swift - User profile card styling
/// - SettingsHeader.swift - Settings screen headers
/// - StatusBadge.swift - Status indicator badges
///
enum OPSStyle {
    // MARK: - Colors
    enum Colors {
        // Brand colors
        static let primaryAccent = Color("AccentPrimary") // Orange (#FF7733)
        static let secondaryAccent = Color("AccentSecondary") // Blue for secondary actions
        
        // Background colors
        static let background = Color("Background") // Main background (black)
        static let darkBackground = Color("DarkBackground") // Darker background (#090C15)
        static let cardBackground = Color("CardBackground") // Card background (dark gray)
        static let cardBackgroundDark = Color("CardBackgroundDark") // Darker card background (#1F293D)
        static let statusBackground = Color("StatusBackground") // Status badge background
        
        // Text colors
        static let primaryText = Color("TextPrimary") // White
        static let secondaryText = Color("TextSecondary") // Light gray (#AAAAAA)
        static let tertiaryText = Color("TextTertiary") // Darker gray (#777777)
        static let inactiveText = Color("TextInactive") // Dark gray
        
        // Status colors
        static let successStatus = Color("StatusSuccess") // Green (#34C759)
        static let warningStatus = Color("StatusWarning") // Yellow/Orange
        static let errorStatus = Color("StatusError") // Red (#FF3B30)
        static let inactiveStatus = Color("StatusInactive") // Gray (#8E8E93)
        
        // Gradients
        static let backgroundGradient = LinearGradient(
            gradient: Gradient(colors: [Color("BackgroundGradientStart"), Color("BackgroundGradientEnd")]),
            startPoint: .top,
            endPoint: .bottom
        )
        
        // MARK: - Light Theme (Employee Onboarding)
        enum Light {
            // Background colors
            static let background = Color.white
            static let cardBackground = Color(red: 0.95, green: 0.95, blue: 0.97) // Light gray
            static let cardBackgroundDark = Color(red: 0.92, green: 0.92, blue: 0.95) // Slightly darker light gray
            
            // Text colors
            static let primaryText = Color.black
            static let secondaryText = Color(red: 0.4, green: 0.4, blue: 0.4) // Medium gray
            static let tertiaryText = Color(red: 0.6, green: 0.6, blue: 0.6) // Light gray
            
            // Brand colors (keep the same)
            static let primaryAccent = Colors.primaryAccent
            static let secondaryAccent = Colors.secondaryAccent
            
            // Status colors (keep the same)
            static let successStatus = Colors.successStatus
            static let warningStatus = Colors.warningStatus
            static let errorStatus = Colors.errorStatus
            static let inactiveStatus = Colors.inactiveStatus
        }
        
        // Utility
        static func statusColor(for status: Status) -> Color {
            switch status {
            case .rfq:
                return Color("StatusRFQ")
            case .estimated:
                return Color("StatusEstimated")
            case .accepted:
                return Color("StatusAccepted")
            case .inProgress:
                return Color("StatusInProgress")
            case .completed:
                return Color("StatusCompleted")
            case .closed:
                return Color("StatusClosed")
            case .pending:
                return Color("StatusWarning") // Using warning color for pending
            case .archived:
                return Color("StatusInactive") // Using inactive color for archived
            }
        }
    }
    
    // MARK: - Typography
    enum Typography {
        // Title styles
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let subtitle = Font.subtitle
        
        // Body text
        static let body = Font.body
        static let bodyBold = Font.bodyBold
        static let bodyEmphasis = Font.bodyEmphasis
        
        // Supporting text
        static let caption = Font.caption
        static let captionBold = Font.captionBold
        static let smallCaption = Font.smallCaption
        static let smallBody = Font.smallBody
        
        // Cards
        static let cardTitle = Font.cardTitle
        static let cardSubtitle = Font.cardSubtitle
        static let cardBody = Font.cardBody
        
        // Status text
        static let status = Font.status
        
        // Button text
        static let button = Font.button
        static let smallButton = Font.smallButton
        static let smallButtonBold = Font.smallButton.weight(.bold)
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
        static let cornerRadius = 5.0
        static let buttonRadius = 5.0
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
            .font(OPSStyle.Typography.button)
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
            .font(OPSStyle.Typography.button)
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

// Legacy status badge - use the new StatusBadge component for new code
struct LegacyStatusBadge: View {
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

// MARK: - Extension for easy usage (Legacy)
extension View {
    // Deprecated - use opsPrimaryButtonStyle() from ButtonStyles.swift
    func primaryButtonStyle() -> some View {
        self.modifier(PrimaryButton())
    }
    
    // Deprecated - use opsSecondaryButtonStyle() from ButtonStyles.swift 
    func secondaryButtonStyle() -> some View {
        self.modifier(SecondaryButton())
    }
    
    // Deprecated - use opsIconButtonStyle() from ButtonStyles.swift
    func iconButtonStyle() -> some View {
        self.modifier(IconActionButton())
    }
    
    // Deprecated - use opsCardStyle() from CardStyles.swift
    func cardStyle() -> some View {
        self.padding()
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// MARK: - Blur View

struct BlurView: UIViewRepresentable {

    let style: UIBlurEffect.Style

    func makeUIView(context: UIViewRepresentableContext<BlurView>) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        let blurEffect = UIBlurEffect(style: style)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(blurView, at: 0)
        NSLayoutConstraint.activate([
            blurView.heightAnchor.constraint(equalTo: view.heightAnchor),
            blurView.widthAnchor.constraint(equalTo: view.widthAnchor),
        ])
        return view
    }

    func updateUIView(_ uiView: UIView,
                      context: UIViewRepresentableContext<BlurView>) {

    }

}
