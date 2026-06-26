import SwiftUI
import DeckKit
import OPSDesignKit

struct OPSDecksRootView: View {
    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing5) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    Text(OPSDecksCopy.statusEyebrow)
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundStyle(OPSStyle.Colors.textMute)

                    Text(OPSDecksCopy.shellTitle)
                        .font(OPSStyle.Typography.screenTitle(for: OPSDecksCopy.shellTitle))
                        .foregroundStyle(OPSStyle.Colors.text)

                    Text(OPSDecksCopy.shellSubtitle)
                        .font(OPSStyle.Typography.body)
                        .foregroundStyle(OPSStyle.Colors.text2)
                }

                VStack(spacing: OPSStyle.Layout.spacing3) {
                    OPSDecksShellButton(
                        title: OPSDecksCopy.primaryActionPlaceholder,
                        variant: .primary
                    )

                    OPSDecksShellButton(
                        title: OPSDecksCopy.secondaryActionPlaceholder,
                        variant: .secondary
                    )
                }
            }
            .padding(OPSStyle.Layout.spacing5)
            .background(OPSStyle.Colors.glassApprox)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                    .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
            .padding(OPSStyle.Layout.spacing4)
        }
    }
}

private struct OPSDecksShellButton: View {
    enum Variant {
        case primary
        case secondary
    }

    let title: String
    let variant: Variant

    var body: some View {
        Button(action: {}) {
            Text(title)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        }
        .buttonStyle(.plain)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(borderColor, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
        .disabled(true)
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:
            OPSStyle.Colors.opsAccent
        case .secondary:
            OPSStyle.Colors.glassApprox
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            OPSStyle.Colors.invertedText
        case .secondary:
            OPSStyle.Colors.text2
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary:
            OPSStyle.Colors.opsAccent
        case .secondary:
            OPSStyle.Colors.line
        }
    }
}

#Preview {
    OPSDecksRootView()
        .preferredColorScheme(.dark)
}
