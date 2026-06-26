import SwiftUI
import DeckKit
import OPSDesignKit

enum OPSDecksCreateState: Equatable {
    case canCreate
    case lockedAtFreeLimit
}

struct OPSDecksRootView: View {
    private let savedDeckCount: Int
    private let entitlement: DecksEntitlement

    init(
        savedDeckCount: Int = 0,
        entitlement: DecksEntitlement = .free(savedDeckLimit: 1)
    ) {
        self.savedDeckCount = savedDeckCount
        self.entitlement = entitlement
    }

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
                        variant: primaryActionVariant
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

    private var createState: OPSDecksCreateState {
        let gate = DecksEntitlementGate(entitlement: entitlement)
        switch gate.decision(savedDeckCount: savedDeckCount) {
        case .allowSave:
            return .canCreate
        case .requiresPro:
            return .lockedAtFreeLimit
        }
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
}

private struct OPSDecksShellButton: View {
    enum Variant {
        case primary
        case secondary
        case attention
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

#Preview {
    OPSDecksRootView()
        .preferredColorScheme(.dark)
}

#Preview("Free Limit") {
    OPSDecksRootView(savedDeckCount: 1)
        .preferredColorScheme(.dark)
}
