import SwiftUI
import DeckKit
import OPSDesignKit

enum OPSDecksCreateState: Equatable {
    case canCreate
    case lockedAtFreeLimit
}

struct OPSDecksRootView: View {
    @StateObject private var session: OPSDecksDesignSession
    @State private var deckPendingDeletion: OPSDecksDeckDocument?

    init(
        companyId: String = "ops-decks-local-company",
        savedDeckCount: Int? = nil,
        entitlement: DecksEntitlement = .free(savedDeckLimit: 1),
        libraryStore: OPSDecksDeckLibraryStore? = nil
    ) {
        let resolvedStore = libraryStore ?? Self.makeLibraryStore(
            companyId: companyId,
            savedDeckCount: savedDeckCount
        )
        _session = StateObject(
            wrappedValue: OPSDecksDesignSession(
                companyId: companyId,
                entitlement: entitlement,
                libraryStore: resolvedStore
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
                    onPersist: session.updateActiveDrawingData,
                    onClose: session.closeActiveDesign
                )
                .padding(OPSStyle.Layout.spacing4)
            } else {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        shellPanel
                        libraryPanel
                        DecksUpgradeSurface()
                    }
                    .padding(OPSStyle.Layout.spacing4)
                }
            }
        }
        .confirmationDialog(
            OPSDecksCopy.deleteConfirmationTitle,
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let document = deckPendingDeletion {
                Button(OPSDecksCopy.deleteDeck, role: .destructive) {
                    _ = session.deleteDeck(id: document.id)
                    deckPendingDeletion = nil
                }
            }
            Button(OPSDecksCopy.cancel, role: .cancel) {}
        } message: {
            Text(OPSDecksCopy.deleteConfirmationMessage)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deckPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    deckPendingDeletion = nil
                }
            }
        )
    }

    private static func makeLibraryStore(
        companyId: String,
        savedDeckCount: Int?
    ) -> OPSDecksDeckLibraryStore {
        if let savedDeckCount {
            return OPSDecksInMemoryDeckLibraryStore(
                seedCount: savedDeckCount,
                companyId: companyId
            )
        }
        do {
            return try OPSDecksFileDeckLibraryStore.appStore()
        } catch {
            return OPSDecksUnavailableDeckLibraryStore(error: error)
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

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text(OPSDecksCopy.libraryEyebrow)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundStyle(OPSStyle.Colors.textMute)

            if session.libraryError != nil {
                OPSDecksStatusPanel(
                    title: OPSDecksCopy.storageErrorStatus,
                    message: OPSDecksCopy.storageErrorMessage,
                    variant: .attention
                )
            }

            if session.savedDecks.isEmpty {
                OPSDecksEmptyLibraryView()
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(session.savedDecks) { document in
                        OPSDecksLibraryRow(
                            document: document,
                            onOpen: { _ = session.openDeck(id: document.id) },
                            onDelete: { deckPendingDeletion = document }
                        )
                    }
                }
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
        case destructive
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
        .opacity(isDisabled ? OPSStyle.Layout.Opacity.strong : OPSStyle.Layout.Opacity.full)
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:
            OPSStyle.Colors.opsAccent
        case .secondary:
            OPSStyle.Colors.glassApprox
        case .attention:
            OPSStyle.Colors.tanFillM
        case .destructive:
            OPSStyle.Colors.roseFillM
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
        case .destructive:
            OPSStyle.Colors.roseTextM
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
        case .destructive:
            OPSStyle.Colors.roseLineM
        }
    }
}

private struct OPSDecksEmptyLibraryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(OPSDecksCopy.emptyLibraryTitle)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundStyle(OPSStyle.Colors.text2)

            Text(OPSDecksCopy.emptyLibraryBody)
                .font(OPSStyle.Typography.body)
                .foregroundStyle(OPSStyle.Colors.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.glassApprox)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
    }
}

private struct OPSDecksStatusPanel: View {
    enum Variant {
        case attention
    }

    let title: String
    let message: String
    let variant: Variant

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundStyle(titleColor)

            Text(message)
                .font(OPSStyle.Typography.body)
                .foregroundStyle(OPSStyle.Colors.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(borderColor, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
    }

    private var titleColor: Color {
        switch variant {
        case .attention:
            OPSStyle.Colors.tanTextM
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .attention:
            OPSStyle.Colors.tanFillM
        }
    }

    private var borderColor: Color {
        switch variant {
        case .attention:
            OPSStyle.Colors.tanLineM
        }
    }
}

private struct OPSDecksLibraryRow: View {
    let document: OPSDecksDeckDocument
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(document.title)
                        .font(OPSStyle.Typography.section)
                        .foregroundStyle(OPSStyle.Colors.text)

                    Text(updatedLabel)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundStyle(OPSStyle.Colors.text3)
                }

                Spacer(minLength: OPSStyle.Layout.spacing3)

                Text(OPSDecksCopy.localStatus)
                    .font(OPSStyle.Typography.badgeCake)
                    .foregroundStyle(OPSStyle.Colors.text2)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.glassApprox)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                OPSDecksShellButton(
                    title: OPSDecksCopy.openDeck,
                    variant: .secondary,
                    isDisabled: false,
                    action: onOpen
                )

                OPSDecksShellButton(
                    title: OPSDecksCopy.deleteDeck,
                    variant: .destructive,
                    isDisabled: false,
                    action: onDelete
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.glassApprox)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
    }

    private var updatedLabel: String {
        let formatted = document.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return OPSDecksCopy.updatedLabel(formatted)
    }
}

private struct OPSDecksDesignerSessionView: View {
    let activeDesign: OPSDecksActiveDesign
    let onPersist: (DeckDrawingData) -> Void
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

            DeckDrawingEditorView(
                drawingData: activeDesign.document.drawingData,
                runtime: activeDesign.runtime,
                onPersist: onPersist
            )
            .id(activeDesign.document.id)
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
