import SwiftUI

/// Standardized button styles — spec v2 (2026-04-17).
///
/// Primary is **outlined at rest, fills on press** — accent is a quiet promise, not a shout.
/// Secondary / Ghost lighten on press — text brightens from `text-2` to `text`, never changes hue.
/// Destructive uses the earth-tone `rose` family (bg `roseSoft`, text `rose`, border `roseLine`).
/// All buttons are 56pt tall for glove-friendly mobile use; text is Cake Mono Light uppercase.
struct OPSButtonStyle {

    /// Primary button — outlined at rest, fills with `opsAccent` on press.
    struct Primary: ButtonStyle {
        var isDisabled: Bool = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(OPSStyle.Typography.buttonLabel)
                .textCase(.uppercase)
                .foregroundColor(foreground(pressed: configuration.isPressed))
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(background(pressed: configuration.isPressed))
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(border, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
        }

        private func foreground(pressed: Bool) -> Color {
            if isDisabled { return OPSStyle.Colors.textMute }
            return pressed ? .black : OPSStyle.Colors.opsAccent
        }
        private func background(pressed: Bool) -> Color {
            if isDisabled { return .clear }
            return pressed ? OPSStyle.Colors.opsAccent : .clear
        }
        private var border: Color {
            isDisabled ? OPSStyle.Colors.line : OPSStyle.Colors.opsAccent
        }
    }

    /// Secondary button — transparent with hairline border, brightens on press.
    /// No accent color anywhere.
    struct Secondary: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(OPSStyle.Typography.buttonLabel)
                .textCase(.uppercase)
                .foregroundColor(configuration.isPressed ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(configuration.isPressed ? OPSStyle.Colors.surfaceHover : Color.clear)
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.line, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
        }
    }

    /// Destructive button — earth-tone rose treatment (soft fill, rose text, rose-line border).
    /// Brick is reserved for destructive borders/dots only, never text.
    struct Destructive: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(OPSStyle.Typography.buttonLabel)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.rose)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(
                    configuration.isPressed
                        ? OPSStyle.Colors.rose.opacity(0.20)
                        : OPSStyle.Colors.roseSoft
                )
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.roseLine, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
        }
    }

    /// Icon button — circular touch target, `surface-hover` bg on press.
    /// No accent by default; pass an explicit `foregroundColor` for status-colored icon buttons.
    struct Icon: ButtonStyle {
        var backgroundColor: Color = OPSStyle.Colors.surfaceInput
        var foregroundColor: Color = OPSStyle.Colors.text
        var size: CGFloat = OPSStyle.Layout.touchTargetMin

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(configuration.isPressed ? OPSStyle.Colors.surfaceHover : backgroundColor)
                .clipShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
                .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
        }
    }
}

// MARK: - View extensions

extension View {
    /// Apply the primary button style (outlined at rest, fills on press).
    func opsPrimaryButtonStyle(isDisabled: Bool = false) -> some View {
        self.buttonStyle(OPSButtonStyle.Primary(isDisabled: isDisabled))
    }

    /// Apply the secondary button style (hairline border, brightens on press).
    func opsSecondaryButtonStyle() -> some View {
        self.buttonStyle(OPSButtonStyle.Secondary())
    }

    /// Apply the destructive button style (rose earth-tone).
    func opsDestructiveButtonStyle() -> some View {
        self.buttonStyle(OPSButtonStyle.Destructive())
    }

    /// Apply the circular icon button style.
    func opsIconButtonStyle(backgroundColor: Color = OPSStyle.Colors.surfaceInput,
                            foregroundColor: Color = OPSStyle.Colors.text,
                            size: CGFloat = OPSStyle.Layout.touchTargetMin) -> some View {
        self.buttonStyle(OPSButtonStyle.Icon(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            size: size
        ))
    }
}

// MARK: - Previews

struct ButtonStyles_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("BUTTON STYLES")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.bottom, 16)

            Button { } label: {
                HStack {
                    Image(OPSStyle.Icons.checkmark)
                    Text("Primary")
                }
            }
            .opsPrimaryButtonStyle()

            Button { } label: {
                HStack {
                    Image(OPSStyle.Icons.close)
                    Text("Disabled Primary")
                }
            }
            .opsPrimaryButtonStyle(isDisabled: true)
            .disabled(true)

            Button { } label: {
                HStack {
                    Image(OPSStyle.Icons.info)
                    Text("Secondary")
                }
            }
            .opsSecondaryButtonStyle()

            Button { } label: {
                HStack {
                    Image(OPSStyle.Icons.delete)
                    Text("Destructive")
                }
            }
            .opsDestructiveButtonStyle()

            HStack(spacing: 16) {
                Button { } label: { Image(OPSStyle.Icons.plus) }
                    .opsIconButtonStyle()

                Button { } label: { Image(OPSStyle.Icons.edit) }
                    .opsIconButtonStyle(foregroundColor: OPSStyle.Colors.opsAccent)

                Button { } label: { Image(OPSStyle.Icons.delete) }
                    .opsIconButtonStyle(foregroundColor: OPSStyle.Colors.rose)

                Button { } label: { Image(OPSStyle.Icons.favorite) }
                    .opsIconButtonStyle(foregroundColor: OPSStyle.Colors.tan)
            }
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .previewLayout(.sizeThatFits)
    }
}
