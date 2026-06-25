@_exported import OPSDesignKit

import SwiftUI
import UIKit

extension OPSStyle.Colors {
    static func pipelineStageColor(for stage: PipelineStage) -> Color {
        switch stage {
        case .newLead:     return Color(hex: "#6A7A8A")!
        case .qualifying:  return Color(hex: "#6F94B0")!
        case .quoting:     return Color(hex: "#7CA5B8")!
        case .quoted:      return Color(hex: "#BFAE8A")!
        case .followUp:    return Color(hex: "#C4A868")!
        case .negotiation: return Color(hex: "#CA9670")!
        case .won:         return Color(hex: "#9DB582")!
        case .lost:        return Color(hex: "#B58289")!
        case .discarded:   return Color(hex: "#5A5E66")!
        }
    }

    static func statusColor(for status: Status) -> Color {
        switch status {
        case .rfq:
            return OPSStyle.Colors.statusRFQ
        case .estimated:
            return OPSStyle.Colors.statusEstimated
        case .accepted:
            return OPSStyle.Colors.statusAccepted
        case .inProgress:
            return OPSStyle.Colors.statusInProgress
        case .completed:
            return OPSStyle.Colors.statusCompleted
        case .closed:
            return OPSStyle.Colors.statusClosed
        case .archived:
            return OPSStyle.Colors.statusArchived
        }
    }
}

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

struct DisabledButtonStyle: ViewModifier {
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isDisabled ? 0.7 : 1.0)
    }
}

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

    func disabledButtonStyle(isDisabled: Bool) -> some View {
        self.modifier(DisabledButtonStyle(isDisabled: isDisabled))
    }

    func cardStyle(
        background: Color = OPSStyle.Colors.cardBackgroundDark,
        borderColor: Color = OPSStyle.Colors.cardBorder,
        borderWidth: CGFloat = 1,
        padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
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

    func updateUIView(_ uiView: UIView, context: UIViewRepresentableContext<BlurView>) {}
}

extension OPSStyle {
    static func configureNavigationBarAppearance() {
        let textColor = UIColor(named: "TextPrimary") ?? .white
        let secondaryColor = UIColor(named: "TextSecondary") ?? textColor

        let inlineTitleFont = UIFont(name: "CakeMono-Light", size: 18)
            ?? .systemFont(ofSize: 18, weight: .light)
        let largeTitleFont = UIFont(name: "CakeMono-Light", size: 28)
            ?? .systemFont(ofSize: 28, weight: .light)
        let backFont = UIFont(name: "JetBrainsMono-Regular", size: 13)
            ?? .systemFont(ofSize: 13)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: inlineTitleFont,
            .foregroundColor: textColor,
        ]
        let largeTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: largeTitleFont,
            .foregroundColor: textColor,
        ]
        let backAttrs: [NSAttributedString.Key: Any] = [
            .font: backFont,
            .foregroundColor: secondaryColor,
            .kern: 0.6,
        ]
        let backButtonAppearance = UIBarButtonItemAppearance()
        backButtonAppearance.normal.titleTextAttributes = backAttrs
        backButtonAppearance.highlighted.titleTextAttributes = backAttrs
        backButtonAppearance.focused.titleTextAttributes = backAttrs

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.backgroundColor = UIColor(white: 10.0 / 255.0, alpha: 0.80)
        scrolled.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        scrolled.shadowColor = UIColor(white: 1.0, alpha: 0.10)
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
        navBar.tintColor = textColor
    }
}
