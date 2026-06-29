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
        companyId: String = OPSDecksLibraryBootstrap.localCompanyId,
        accountContext: OPSDecksAccountContext? = nil,
        savedDeckCount: Int? = nil,
        entitlement: DecksEntitlement = .free(savedDeckLimit: 1),
        libraryStore: OPSDecksDeckLibraryStore? = nil,
        remoteClient: OPSDecksRemoteDeckLibraryClient? = nil,
        codeProfiles: [DeckCodeProfile] = [],
        accessTokenProvider: (@Sendable () async throws -> String)? = nil
    ) {
        let bootstrap = Self.makeLibraryBootstrap(
            companyId: companyId,
            accountContext: accountContext,
            savedDeckCount: savedDeckCount,
            libraryStore: libraryStore,
            remoteClient: remoteClient,
            accessTokenProvider: accessTokenProvider
        )
        _session = StateObject(
            wrappedValue: OPSDecksDesignSession(
                companyId: bootstrap.companyId,
                entitlement: entitlement,
                libraryStore: bootstrap.libraryStore,
                codeProfiles: codeProfiles
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
                    availableCodeProfiles: session.availableCodeProfiles,
                    codeProfileResolution: session.codeProfileResolution,
                    onPersist: { drawingData in
                        Task {
                            await session.updateActiveDrawingDataAndSync(drawingData)
                        }
                    },
                    onSelectCodeProfile: session.setCodeProfileJurisdictionId,
                    onClose: session.closeActiveDesign
                )
                .padding(OPSStyle.Layout.spacing4)
            } else {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        shellPanel
                        codeProfilePanel
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
                    Task {
                        _ = await session.deleteDeckAndSync(id: document.id)
                        deckPendingDeletion = nil
                    }
                }
            }
            Button(OPSDecksCopy.cancel, role: .cancel) {}
        } message: {
            Text(OPSDecksCopy.deleteConfirmationMessage)
        }
        .task {
            await session.refreshLibraryFromRemote()
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

    private static func makeLibraryBootstrap(
        companyId: String,
        accountContext: OPSDecksAccountContext?,
        savedDeckCount: Int?,
        libraryStore: OPSDecksDeckLibraryStore?,
        remoteClient: OPSDecksRemoteDeckLibraryClient?,
        accessTokenProvider: (@Sendable () async throws -> String)?
    ) -> OPSDecksLibraryBootstrap {
        if let libraryStore {
            return OPSDecksLibraryBootstrap(
                companyId: accountContext?.companyId ?? companyId,
                libraryStore: libraryStore
            )
        }
        return OPSDecksLibraryBootstrap.make(
            accountContext: accountContext,
            savedDeckCount: savedDeckCount,
            localCompanyId: companyId,
            remoteClient: remoteClient,
            accessTokenProvider: accessTokenProvider
        )
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

    private var codeProfilePanel: some View {
        OPSDecksCodeProfileSettingsPanel(
            availableProfiles: session.availableCodeProfiles,
            resolution: session.codeProfileResolution,
            onSelectJurisdiction: session.setCodeProfileJurisdictionId
        )
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
        Task {
            await session.startNewDeckAndSync()
        }
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
    var fillsWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                .padding(.horizontal, fillsWidth ? 0 : OPSStyle.Layout.spacing3)
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

private struct OPSDecksCodeProfileSettingsPanel: View {
    let availableProfiles: [DeckCodeProfile]
    let resolution: DeckCodeProfileResolution
    let onSelectJurisdiction: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text(OPSDecksCopy.codeProfileEyebrow)
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundStyle(OPSStyle.Colors.textMute)

                    Text(statusMessage)
                        .font(OPSStyle.Typography.body)
                        .foregroundStyle(OPSStyle.Colors.text2)
                }

                Spacer(minLength: OPSStyle.Layout.spacing3)

                statusBadge
            }

            if availableProfiles.isEmpty {
                Text(OPSDecksCopy.codeProfileEmptyMessage)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundStyle(OPSStyle.Colors.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.fillNeutralDim)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(availableProfiles) { profile in
                        profileRow(profile)
                    }
                }
            }

            if resolution.request.jurisdictionId != nil {
                OPSDecksShellButton(
                    title: OPSDecksCopy.codeProfileClear,
                    variant: .secondary,
                    isDisabled: false,
                    fillsWidth: false,
                    action: { onSelectJurisdiction(nil) }
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

    private var statusBadge: some View {
        Text(statusTitle)
            .font(OPSStyle.Typography.badgeCake)
            .foregroundStyle(statusTextColor)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(statusFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(statusLineColor, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
            .accessibilityLabel(OPSDecksCopy.codeProfileEyebrow)
            .accessibilityValue(statusTitle)
    }

    private func profileRow(_ profile: DeckCodeProfile) -> some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(profile.jurisdiction.id)
                    .font(OPSStyle.Typography.section)
                    .foregroundStyle(OPSStyle.Colors.text)

                Text(profile.source?.profileSourceToken ?? OPSDecksCopy.codeProfileSourceFallback)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundStyle(OPSStyle.Colors.text3)
            }

            Spacer(minLength: OPSStyle.Layout.spacing3)

            if selectedProfileId == profile.id {
                Text(OPSDecksCopy.codeProfileAvailable)
                    .font(OPSStyle.Typography.badgeCake)
                    .foregroundStyle(OPSStyle.Colors.oliveTextM)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.oliveFillM)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .stroke(OPSStyle.Colors.oliveLineM, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
            } else {
                OPSDecksShellButton(
                    title: OPSDecksCopy.codeProfileUse,
                    variant: .secondary,
                    isDisabled: false,
                    fillsWidth: false,
                    action: { onSelectJurisdiction(profile.jurisdiction.id) }
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

    private var selectedProfileId: String? {
        resolution.profile?.id
    }

    private var statusTitle: String {
        switch resolution.status {
        case .notConfigured:
            return OPSDecksCopy.codeProfileNotConfigured
        case .available:
            return OPSDecksCopy.codeProfileAvailable
        case .unavailable:
            return OPSDecksCopy.codeProfileUnavailable
        case .failed:
            return OPSDecksCopy.codeProfileFailed
        }
    }

    private var statusMessage: String {
        switch resolution.status {
        case .notConfigured:
            return OPSDecksCopy.codeProfileNotConfiguredMessage
        case .available:
            return OPSDecksCopy.codeProfileAvailableMessage
        case .unavailable:
            return OPSDecksCopy.codeProfileUnavailableMessage
        case .failed:
            return OPSDecksCopy.codeProfileFailedMessage
        }
    }

    private var statusTextColor: Color {
        switch resolution.status {
        case .notConfigured:
            return OPSStyle.Colors.text3
        case .available:
            return OPSStyle.Colors.oliveTextM
        case .unavailable:
            return OPSStyle.Colors.tanTextM
        case .failed:
            return OPSStyle.Colors.roseTextM
        }
    }

    private var statusFillColor: Color {
        switch resolution.status {
        case .notConfigured:
            return OPSStyle.Colors.fillNeutralDim
        case .available:
            return OPSStyle.Colors.oliveFillM
        case .unavailable:
            return OPSStyle.Colors.tanFillM
        case .failed:
            return OPSStyle.Colors.roseFillM
        }
    }

    private var statusLineColor: Color {
        switch resolution.status {
        case .notConfigured:
            return OPSStyle.Colors.nestedBorder
        case .available:
            return OPSStyle.Colors.oliveLineM
        case .unavailable:
            return OPSStyle.Colors.tanLineM
        case .failed:
            return OPSStyle.Colors.roseLineM
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
    let availableCodeProfiles: [DeckCodeProfile]
    let codeProfileResolution: DeckCodeProfileResolution
    let onPersist: (DeckDrawingData) -> Void
    let onSelectCodeProfile: (String?) -> Void
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

            OPSDecksCodeProfileSettingsPanel(
                availableProfiles: availableCodeProfiles,
                resolution: codeProfileResolution,
                onSelectJurisdiction: onSelectCodeProfile
            )

            DeckDrawingEditorView(
                drawingData: activeDesign.document.drawingData,
                runtime: activeDesign.runtime,
                onPersist: onPersist
            )
            .id(activeDesign.editorIdentity)
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
