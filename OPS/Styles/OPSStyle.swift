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

        // Border colors
        static let cardBorder = Color.white.opacity(0.1) // Standard card border
        static let cardBorderSubtle = Color.white.opacity(0.05) // Subtle card border for less prominent cards
        
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

        // Status text colors (for foreground, not background)
        // Reuse existing status asset colors for text as well
        static let errorText = Color("StatusError")     // Same as errorStatus - works for both bg and text
        static let successText = Color("StatusSuccess") // Same as successStatus - works for both bg and text
        static let warningText = Color("StatusWarning") // Same as warningStatus - works for both bg and text

        // UI state colors
        static let disabledText = Color("TextTertiary") // Reuse tertiaryText for disabled state
        static let placeholderText = Color(red: 0.6, green: 0.6, blue: 0.6)  // #999999 (medium gray)

        // Button-specific colors
        static let buttonText = Color.white  // For text on accent backgrounds
        static let invertedText = Color.black  // For light-on-dark inversions

        // Shadows
        static let shadowColor = Color.black.opacity(0.3)  // Standard shadow

        // Separators
        static let separator = Color.white.opacity(0.15)  // For divider lines
        
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
            case .archived:
                return Color("StatusArchived")
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

        // Corner radius variants
        static let cornerRadius = 5.0       // Standard corner radius
        static let buttonRadius = 5.0       // Button corner radius
        static let smallCornerRadius = 2.5  // For badges, small UI elements
        static let cardCornerRadius = 8.0   // For larger cards
        static let largeCornerRadius = 12.0 // For modals, sheets

        // Opacity presets
        enum Opacity {
            static let subtle = 0.1   // Disabled, very light overlays
            static let light = 0.3    // Light overlays
            static let medium = 0.5   // Medium overlays
            static let strong = 0.7   // Strong overlays
            static let heavy = 0.9    // Almost opaque
        }

        // Shadow presets
        enum Shadow {
            static let card = (color: Color.black.opacity(0.1), radius: 4.0, x: 0.0, y: 2.0)
            static let elevated = (color: Color.black.opacity(0.2), radius: 8.0, x: 0.0, y: 4.0)
            static let floating = (color: Color.black.opacity(0.3), radius: 12.0, x: 0.0, y: 6.0)
        }
    }
    
    // MARK: - Animation
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.15)
    }

    // MARK: - Icons
    enum Icons {
        // MARK: - OPS Domain Semantic Icons
        // These are THE standardized icons for core OPS concepts
        // Always use these for their designated purpose to maintain consistency

        // Core entities
        static let project = "folder.fill"                  // THE icon for Projects
        static let task = "checklist"                       // THE icon for Tasks
        static let taskType = "tag.fill"                    // THE icon for Task Types
        static let client = "person.circle.fill"            // THE icon for Clients
        static let subClient = "person.2.fill"              // THE icon for Sub-clients
        static let teamMember = "person.fill"               // THE icon for Team Members
        static let crew = "person.3.fill"                   // THE icon for Crews/Teams

        // Scheduling & Time
        static let schedule = "calendar.badge.clock"        // THE icon for Scheduling
        static let deadline = "calendar.badge.exclamationmark" // THE icon for Deadlines
        static let duration = "clock.fill"                  // THE icon for Duration/Time

        // Location & Site
        static let jobSite = "location.fill"                // THE icon for Job Sites
        static let address = "mappin.and.ellipse"           // THE icon for Addresses

        // Content & Media
        static let notes = "note.text"                      // THE icon for Notes
        static let description = "text.alignleft"           // THE icon for Description
        static let photos = "photo.on.rectangle"            // THE icon for Photos
        static let documents = "doc.text.fill"              // THE icon for Documents

        // Actions
        static let add = "plus.circle.fill"                 // THE icon for Add/Create
        static let edit = "pencil.circle.fill"              // THE icon for Edit
        static let delete = "trash.fill"                    // THE icon for Delete
        static let sync = "arrow.triangle.2.circlepath"     // THE icon for Sync
        static let share = "square.and.arrow.up"            // THE icon for Share
        static let filter = "line.horizontal.3.decrease.circle" // THE icon for Filter
        static let sort = "arrow.up.arrow.down.circle"      // THE icon for Sort

        // Status & State
        static let complete = "checkmark.circle.fill"       // THE icon for Complete
        static let incomplete = "circle"                    // THE icon for Incomplete
        static let inProgress = "clock.arrow.circlepath"    // THE icon for In Progress (if needed)
        static let alert = "exclamationmark.triangle.fill"  // THE icon for Alerts/Warnings
        static let error = "xmark.octagon.fill"             // THE icon for Errors
        static let info = "info.circle.fill"                // THE icon for Information

        // System
        static let settings = "gearshape.fill"              // THE icon for Settings
        static let search = "magnifyingglass"               // THE icon for Search
        static let menu = "line.3.horizontal"               // THE icon for Menu
        static let close = "xmark"                          // THE icon for Close/Dismiss
        static let back = "chevron.left"                    // THE icon for Back navigation
        static let forward = "chevron.right"                // THE icon for Forward navigation

        // MARK: - Legacy SF Symbols (Currently in Use)
        // These are used in existing code - during Track F migration, replace with semantic icons above
        // Example: Replace `OPSStyle.Icons.calendar` with `OPSStyle.Icons.schedule`

        static let calendar = "calendar"
        static let calendarFill = "calendar.fill"
        static let person = "person"
        static let personFill = "person.fill"
        static let personTwo = "person.2"
        static let personTwoFill = "person.2.fill"
        static let personCircle = "person.circle"
        static let personCircleFill = "person.circle.fill"
        static let location = "location"
        static let locationFill = "location.fill"
        static let phone = "phone"
        static let phoneFill = "phone.fill"
        static let envelope = "envelope"
        static let envelopeFill = "envelope.fill"
        static let folder = "folder"
        static let folderFill = "folder.fill"
        static let checklist = "checklist"
        static let checkmark = "checkmark"
        static let checkmarkSquare = "checkmark.square"
        static let checkmarkSquareFill = "checkmark.square.fill"
        static let checkmarkCircle = "checkmark.circle"
        static let checkmarkCircleFill = "checkmark.circle.fill"
        static let square = "square"
        static let squareFill = "square.fill"
        static let xmark = "xmark"
        static let xmarkCircle = "xmark.circle"
        static let xmarkCircleFill = "xmark.circle.fill"
        static let chevronRight = "chevron.right"
        static let chevronLeft = "chevron.left"
        static let chevronUp = "chevron.up"
        static let chevronDown = "chevron.down"
        static let plus = "plus"
        static let plusCircle = "plus.circle"
        static let plusCircleFill = "plus.circle.fill"
        static let minus = "minus"
        static let minusCircle = "minus.circle"
        static let minusCircleFill = "minus.circle.fill"
        static let exclamationmarkTriangle = "exclamationmark.triangle"
        static let exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
        static let gearshape = "gearshape"
        static let gearshapeFill = "gearshape.fill"
        static let house = "house"
        static let houseFill = "house.fill"
        static let map = "map"
        static let mapFill = "map.fill"
        static let ellipsis = "ellipsis"
        static let ellipsisCircle = "ellipsis.circle"
        static let ellipsisCircleFill = "ellipsis.circle.fill"
        static let listBullet = "list.bullet"
        static let trash = "trash"
        static let trashFill = "trash.fill"
        static let pencil = "pencil"
        static let pencilCircle = "pencil.circle"
        static let pencilCircleFill = "pencil.circle.fill"
        static let arrowClockwise = "arrow.clockwise"
        static let arrowCounterclockwise = "arrow.counterclockwise"
        static let magnifyingglass = "magnifyingglass"
        static let magnifyingglassCircle = "magnifyingglass.circle"
        static let magnifyingglassCircleFill = "magnifyingglass.circle.fill"
        static let bellFill = "bell.fill"
        static let photo = "photo"
        static let photoFill = "photo.fill"
        static let camera = "camera"
        static let cameraFill = "camera.fill"
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
