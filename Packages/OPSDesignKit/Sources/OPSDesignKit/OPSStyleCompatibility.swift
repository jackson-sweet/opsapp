import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct PrimaryButton: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .font(OPSStyle.Typography.button)
            .foregroundColor(OPSStyle.Colors.buttonText)
            .padding(OPSStyle.Layout.contentPadding)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
    }
}

public struct SecondaryButton: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .font(OPSStyle.Typography.button)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(OPSStyle.Layout.contentPadding)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.thick)
            )
    }
}

public struct IconActionButton: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .font(OPSStyle.Typography.iconAction)
            .foregroundColor(OPSStyle.Colors.buttonText)
            .frame(
                width: OPSStyle.Layout.touchTargetStandard,
                height: OPSStyle.Layout.touchTargetStandard
            )
            .background(Circle().fill(OPSStyle.Colors.primaryAccent))
    }
}

public struct DisabledButtonStyle: ViewModifier {
    let isDisabled: Bool

    public init(isDisabled: Bool) {
        self.isDisabled = isDisabled
    }

    public func body(content: Content) -> some View {
        content.opacity(isDisabled ? OPSStyle.Layout.Opacity.strong : OPSStyle.Layout.Opacity.full)
    }
}

public extension View {
    func primaryButtonStyle() -> some View {
        modifier(PrimaryButton())
    }

    func secondaryButtonStyle() -> some View {
        modifier(SecondaryButton())
    }

    func iconButtonStyle() -> some View {
        modifier(IconActionButton())
    }

    func disabledButtonStyle(isDisabled: Bool) -> some View {
        modifier(DisabledButtonStyle(isDisabled: isDisabled))
    }

    func cardStyle(
        background: Color = OPSStyle.Colors.cardBackgroundDark,
        borderColor: Color = OPSStyle.Colors.cardBorder,
        borderWidth: CGFloat = OPSStyle.Layout.Border.standard,
        padding: EdgeInsets = OPSStyle.Layout.contentPadding
    ) -> some View {
        self
            .padding(padding)
            .background(background)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
    }
}

#if canImport(UIKit)
public struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    public init(style: UIBlurEffect.Style) {
        self.style = style
    }

    public func makeUIView(context: UIViewRepresentableContext<BlurView>) -> UIView {
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

    public func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<BlurView>) {}
}

public extension OPSStyle {
    static func configureNavigationBarAppearance() {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NavigationBarAppearance.inlineTitleFont,
            .foregroundColor: NavigationBarAppearance.textColor,
        ]
        let largeTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NavigationBarAppearance.largeTitleFont,
            .foregroundColor: NavigationBarAppearance.textColor,
        ]
        let backAttrs: [NSAttributedString.Key: Any] = [
            .font: NavigationBarAppearance.backLabelFont,
            .foregroundColor: NavigationBarAppearance.secondaryTextColor,
            .kern: NavigationBarAppearance.backLabelKern,
        ]

        let backButtonAppearance = UIBarButtonItemAppearance()
        backButtonAppearance.normal.titleTextAttributes = backAttrs
        backButtonAppearance.highlighted.titleTextAttributes = backAttrs
        backButtonAppearance.focused.titleTextAttributes = backAttrs

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundColor = NavigationBarAppearance.scrolledBackgroundColor
        scrolled.backgroundEffect = NavigationBarAppearance.scrolledBackgroundEffect
        scrolled.shadowColor = NavigationBarAppearance.scrolledShadowColor
        scrolled.titleTextAttributes = titleAttrs
        scrolled.largeTitleTextAttributes = largeTitleAttrs
        scrolled.backButtonAppearance = backButtonAppearance

        let atTop = UINavigationBarAppearance()
        atTop.configureWithTransparentBackground()
        atTop.backgroundColor = .clear
        atTop.shadowColor = .clear
        atTop.titleTextAttributes = titleAttrs
        atTop.largeTitleTextAttributes = largeTitleAttrs
        atTop.backButtonAppearance = backButtonAppearance

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = scrolled
        navBar.compactAppearance = scrolled
        navBar.scrollEdgeAppearance = atTop
        navBar.compactScrollEdgeAppearance = atTop
        navBar.tintColor = NavigationBarAppearance.textColor
    }
}
#endif
