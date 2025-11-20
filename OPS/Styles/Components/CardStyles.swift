import SwiftUI

/// A collection of view modifiers for standardized card styling
struct OPSCardStyle {
    /// Standard card style with dark background and rounded corners
    struct Standard: ViewModifier {
        var cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius
        var padding: CGFloat = 16
        
        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(cornerRadius)
        }
    }
    
    /// Card style with subtle shadow and lighter background
    struct Elevated: ViewModifier {
        var cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius
        var padding: CGFloat = 16
        
        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(cornerRadius)
                .shadow(color: OPSStyle.Colors.shadowColor, radius: 10, x: 0, y: 4)
        }
    }
    
    /// Interactive card style with tap feedback
    struct Interactive: ViewModifier {
        @State private var isPressed: Bool = false
        var cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius
        var padding: CGFloat = 16
        var action: () -> Void
        
        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(isPressed ? 0.4 : 0.6))
                .cornerRadius(cornerRadius)
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPressed = true }
                        .onEnded { _ in
                            isPressed = false
                            action()
                        }
                )
        }
    }
    
    /// Accent card style with colored border
    struct Accent: ViewModifier {
        var accentColor: Color = OPSStyle.Colors.primaryAccent
        var cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius
        var padding: CGFloat = 16
        
        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(accentColor, lineWidth: 2)
                )
        }
    }
}

// Extension to make modifiers easier to use
extension View {
    /// Apply standard card styling
    func opsCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius, padding: CGFloat = 16) -> some View {
        self.modifier(OPSCardStyle.Standard(cornerRadius: cornerRadius, padding: padding))
    }
    
    /// Apply elevated card styling with shadow
    func opsElevatedCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius, padding: CGFloat = 16) -> some View {
        self.modifier(OPSCardStyle.Elevated(cornerRadius: cornerRadius, padding: padding))
    }
    
    /// Apply interactive card styling with tap action
    func opsInteractiveCardStyle(cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius, padding: CGFloat = 16, action: @escaping () -> Void) -> some View {
        self.modifier(OPSCardStyle.Interactive(cornerRadius: cornerRadius, padding: padding, action: action))
    }
    
    /// Apply accent card styling with colored border
    func opsAccentCardStyle(accentColor: Color = OPSStyle.Colors.primaryAccent, cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius, padding: CGFloat = 16) -> some View {
        self.modifier(OPSCardStyle.Accent(accentColor: accentColor, cornerRadius: cornerRadius, padding: padding))
    }
}

// Standard card components using the modifiers
struct OPSCard: View {
    var body: some View {
        content
            .opsCardStyle()
    }
    
    let content: AnyView
    
    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
    }
}

struct OPSElevatedCard: View {
    var body: some View {
        content
            .opsElevatedCardStyle()
    }
    
    let content: AnyView
    
    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.content = AnyView(content())
    }
}

struct OPSInteractiveCard: View {
    var action: () -> Void
    
    var body: some View {
        content
            .opsInteractiveCardStyle(action: action)
    }
    
    let content: AnyView
    
    init<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = AnyView(content())
    }
}

struct OPSAccentCard: View {
    var accentColor: Color = OPSStyle.Colors.primaryAccent
    
    var body: some View {
        content
            .opsAccentCardStyle(accentColor: accentColor)
    }
    
    let content: AnyView
    
    init<Content: View>(accentColor: Color = OPSStyle.Colors.primaryAccent, @ViewBuilder content: () -> Content) {
        self.accentColor = accentColor
        self.content = AnyView(content())
    }
}

struct CardStyles_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Card Styles")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.top, 16)
                
                // Standard Card
                OPSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Standard Card")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Text("Basic card with standard styling")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                // Elevated Card
                OPSElevatedCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Elevated Card")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Text("Card with elevation and shadow")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                // Interactive Card
                OPSInteractiveCard(action: {
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interactive Card")
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Text("Tap me to trigger an action")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                // Accent Cards
                HStack(spacing: 16) {
                    OPSAccentCard {
                        VStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            
                            Text("Primary")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                    
                    OPSAccentCard(accentColor: OPSStyle.Colors.Statuses.success) {
                        VStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(OPSStyle.Colors.Statuses.success)
                            
                            Text("Success")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                    
                    OPSAccentCard(accentColor: OPSStyle.Colors.Statuses.error) {
                        VStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(OPSStyle.Colors.Statuses.error)
                            
                            Text("Error")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Custom implementation with modifiers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Card Implementation")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text("Using the .opsCardStyle() modifier directly")
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .opsCardStyle(cornerRadius: 16, padding: 20)
            }
            .padding()
        }
        .background(OPSStyle.Colors.background)
        .previewLayout(.sizeThatFits)
    }
}