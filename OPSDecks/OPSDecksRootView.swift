import SwiftUI
import DeckKit
import OPSDesignKit

enum OPSDecksCreateState: Equatable {
    case canCreate
    case lockedAtFreeLimit
}

struct OPSDecksRootView: View {
    @StateObject private var session: OPSDecksDesignSession

    init(
        companyId: String = "ops-decks-local-company",
        savedDeckCount: Int = 0,
        entitlement: DecksEntitlement = .free(savedDeckLimit: 1)
    ) {
        _session = StateObject(
            wrappedValue: OPSDecksDesignSession(
                companyId: companyId,
                savedDeckCount: savedDeckCount,
                entitlement: entitlement
            )
        )
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            if let activeDesign = session.activeDesign {
                OPSDecksDesignerSessionView(
                    activeDesign: activeDesign,
                    onClose: session.closeActiveDesign
                )
                .padding(OPSStyle.Layout.spacing4)
            } else {
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    shellPanel
                    DecksUpgradeSurface()
                }
                .padding(OPSStyle.Layout.spacing4)
            }
        }
    }

    private var shellPanel: some View {
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

                if createState == .lockedAtFreeLimit {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text(OPSDecksCopy.freeLimitStatus)
                            .font(OPSStyle.Typography.panelTitle)
                            .foregroundStyle(OPSStyle.Colors.tanTextM)

                        Text(OPSDecksCopy.freeLimitMessage)
                            .font(OPSStyle.Typography.body)
                            .foregroundStyle(OPSStyle.Colors.text2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.tanFillM)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.tanLineM, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                }
            }

            VStack(spacing: OPSStyle.Layout.spacing3) {
                OPSDecksShellButton(
                    title: primaryActionTitle,
                    variant: primaryActionVariant,
                    isDisabled: createState == .lockedAtFreeLimit,
                    action: primaryAction
                )

                OPSDecksShellButton(
                    title: OPSDecksCopy.secondaryActionPlaceholder,
                    variant: .secondary,
                    isDisabled: true,
                    action: {}
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
    }

    private var createState: OPSDecksCreateState {
        session.createState
    }

    private var primaryActionTitle: String {
        switch createState {
        case .canCreate:
            return OPSDecksCopy.primaryActionPlaceholder
        case .lockedAtFreeLimit:
            return OPSDecksCopy.proActionPlaceholder
        }
    }

    private var primaryActionVariant: OPSDecksShellButton.Variant {
        switch createState {
        case .canCreate:
            return .primary
        case .lockedAtFreeLimit:
            return .attention
        }
    }

    private func primaryAction() {
        _ = session.startNewDeck()
    }
}

private struct OPSDecksShellButton: View {
    enum Variant {
        case primary
        case secondary
        case attention
    }

    let title: String
    let variant: Variant
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
        .disabled(isDisabled)
        .opacity(isDisabled ? OPSStyle.Layout.Opacity.strong : 1.0)
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:
            OPSStyle.Colors.opsAccent
        case .secondary:
            OPSStyle.Colors.glassApprox
        case .attention:
            OPSStyle.Colors.tanFillM
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            OPSStyle.Colors.invertedText
        case .secondary:
            OPSStyle.Colors.text2
        case .attention:
            OPSStyle.Colors.tanTextM
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary:
            OPSStyle.Colors.opsAccent
        case .secondary:
            OPSStyle.Colors.line
        case .attention:
            OPSStyle.Colors.tanLineM
        }
    }
}

private struct OPSDecksDesignerSessionView: View {
    let activeDesign: OPSDecksActiveDesign
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text(OPSDecksCopy.workspaceEyebrow)
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundStyle(OPSStyle.Colors.textMute)

                    Text(activeDesign.document.title)
                        .font(OPSStyle.Typography.screenTitle(for: activeDesign.document.title))
                        .foregroundStyle(OPSStyle.Colors.text)
                }

                Spacer(minLength: OPSStyle.Layout.spacing3)

                Button(action: onClose) {
                    Text(OPSDecksCopy.closeWorkspace)
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundStyle(OPSStyle.Colors.text2)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                .buttonStyle(.plain)
                .background(OPSStyle.Colors.glassApprox)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
            }

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text(OPSDecksCopy.workspaceStatus)
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundStyle(OPSStyle.Colors.opsAccent)

                Text(OPSDecksCopy.workspaceRuntime)
                    .font(OPSStyle.Typography.caption)
                    .foregroundStyle(OPSStyle.Colors.text2)

                Text(OPSDecksCopy.workspaceProject)
                    .font(OPSStyle.Typography.caption)
                    .foregroundStyle(OPSStyle.Colors.textMute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.glassApprox)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                    .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))

            Spacer(minLength: OPSStyle.Layout.spacing4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    OPSDecksRootView()
        .preferredColorScheme(.dark)
}

#Preview("Free Limit") {
    OPSDecksRootView(savedDeckCount: 1)
        .preferredColorScheme(.dark)
}
