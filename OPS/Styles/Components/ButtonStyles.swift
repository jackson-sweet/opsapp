import SwiftUI

/// A collection of standardized button styles for consistent UI
struct OPSButtonStyle {
    /// Standard primary button style with solid background
    struct Primary: ButtonStyle {
        var isDisabled: Bool = false
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    isDisabled 
                    ? OPSStyle.Colors.primaryAccent.opacity(0.5) 
                    : OPSStyle.Colors.primaryAccent.opacity(configuration.isPressed ? 0.8 : 1)
                )
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    
    /// Secondary button style with outlined appearance
    struct Secondary: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                )
                .opacity(configuration.isPressed ? 0.8 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    
    /// Destructive button style for delete/cancel actions
    struct Destructive: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(OPSStyle.Colors.Statuses.error.opacity(configuration.isPressed ? 0.8 : 1))
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    
    /// Icon button style for circular icon buttons
    struct Icon: ButtonStyle {
        var backgroundColor: Color = OPSStyle.Colors.cardBackgroundDark
        var foregroundColor: Color = OPSStyle.Colors.primaryText
        var size: CGFloat = 44
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(backgroundColor.opacity(configuration.isPressed ? 0.7 : 1.0))
                .cornerRadius(size / 2)
                .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

// Extension to make button styles easier to use
extension View {
    /// Apply the primary button style
    func opsPrimaryButtonStyle(isDisabled: Bool = false) -> some View {
        self.buttonStyle(OPSButtonStyle.Primary(isDisabled: isDisabled))
    }
    
    /// Apply the secondary button style
    func opsSecondaryButtonStyle() -> some View {
        self.buttonStyle(OPSButtonStyle.Secondary())
    }
    
    /// Apply the destructive button style
    func opsDestructiveButtonStyle() -> some View {
        self.buttonStyle(OPSButtonStyle.Destructive())
    }
    
    /// Apply the icon button style
    func opsIconButtonStyle(backgroundColor: Color = OPSStyle.Colors.cardBackgroundDark,
                           foregroundColor: Color = OPSStyle.Colors.primaryText,
                           size: CGFloat = 44) -> some View {
        self.buttonStyle(OPSButtonStyle.Icon(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            size: size
        ))
    }
}

struct ButtonStyles_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Button Styles")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.bottom, 16)
            
            // Primary buttons using style modifiers
            Button(action: {}) {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .font(OPSStyle.Typography.body)
                    Text("Primary Button")
                        .font(OPSStyle.Typography.button)
                }
            }
            .opsPrimaryButtonStyle()
            
            Button(action: {}) {
                HStack {
                    Image(systemName: "xmark.circle")
                        .font(OPSStyle.Typography.body)
                    Text("Disabled Primary")
                        .font(OPSStyle.Typography.button)
                }
            }
            .opsPrimaryButtonStyle(isDisabled: true)
            .disabled(true)
            
            // Secondary button using style modifier
            Button(action: {}) {
                HStack {
                    Image(systemName: "info.circle")
                        .font(OPSStyle.Typography.body)
                    Text("Secondary Button")
                        .font(OPSStyle.Typography.button)
                }
            }
            .opsSecondaryButtonStyle()
            
            // Destructive button using style modifier
            Button(action: {}) {
                HStack {
                    Image(systemName: "trash")
                        .font(OPSStyle.Typography.body)
                    Text("Destructive Button")
                        .font(OPSStyle.Typography.button)
                }
            }
            .opsDestructiveButtonStyle()
            
            // Icon buttons using style modifiers
            HStack(spacing: 16) {
                Button(action: {}) {
                    Image(systemName: "plus")
                }
                .opsIconButtonStyle()
                
                Button(action: {}) {
                    Image(systemName: "pencil")
                }
                .opsIconButtonStyle(foregroundColor: OPSStyle.Colors.primaryAccent)
                
                Button(action: {}) {
                    Image(systemName: "trash")
                }
                .opsIconButtonStyle(foregroundColor: OPSStyle.Colors.Statuses.error)
                
                Button(action: {}) {
                    Image(systemName: "star.fill")
                }
                .opsIconButtonStyle(
                    backgroundColor: OPSStyle.Colors.cardBackground,
                    foregroundColor: .yellow
                )
            }
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .previewLayout(.sizeThatFits)
    }
}