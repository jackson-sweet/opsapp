import SwiftUI

// MARK: - GuidedStockSetupFlow
//
// Full-screen flow container for the guided stock setup wizard.
// Presented via .fullScreenCover by entry points.
// Owns: progress indicator, offline banner, stage routing, bottom CTA bar,
//       draft-resume confirmation dialog, haptic orchestration, and commit wiring (P6).

struct GuidedStockSetupFlow: View {

    // MARK: - Dependencies

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @ObservedObject private var permissionStore = PermissionStore.shared
    @StateObject private var model: GuidedStockSetupModel
    @State private var showResumePrompt = false
    @State private var isBuilding = false

    // MARK: - Init

    init(companyId: String, userId: String) {
        _model = StateObject(wrappedValue: GuidedStockSetupModel(companyId: companyId, userId: userId))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            content
        }
        .onAppear {
            if permissionStore.can("catalog.manage") && model.hasDraftToResume {
                showResumePrompt = true
            }
        }
        .confirmationDialog(
            "Pick up where you left off?",
            isPresented: $showResumePrompt,
            titleVisibility: .visible
        ) {
            Button("RESUME") {
                _ = model.restoreIfAvailable()
            }
            Button("START OVER", role: .destructive) {
                model.clearDraft()
                model.stage = .prime
                model.capturedItems = []
                model.groups = []
                model.committedGroupIds = []
            }
        } message: {
            Text("You have an unfinished stock setup.")
        }
        .onChange(of: model.commitProgress) { _, newValue in
            if case .complete(let summary) = newValue {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                postCompletionNotification(summary)
                withAnimation(flowAnimation) {
                    model.stage = .done
                }
            }
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if !permissionStore.can("catalog.manage") {
            permissionGate
        } else {
            VStack(spacing: 0) {
                topProgress
                bannerStack
                stageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(stageTransition)
                    .animation(flowAnimation, value: model.stage)
                bottomBar
            }
        }
    }

    // MARK: - Permission gate (defensive — entry points also gate)

    private var permissionGate: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("// ACCESS RESTRICTED")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)

            Text("You don't have permission to set up stock.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)

            Button("CLOSE") {
                dismiss()
            }
            .opsPrimaryButtonStyle()
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress indicator

    private var stageIndex: Int {
        GuidedStockStage.allCases.firstIndex(of: model.stage) ?? 0
    }

    private var topProgress: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(OPSStyle.Colors.secondaryText.opacity(0.20))
                        .frame(height: 3)
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryText)
                        .frame(
                            width: geo.size.width * CGFloat(stageIndex + 1) / CGFloat(GuidedStockStage.allCases.count),
                            height: 3
                        )
                        .animation(flowAnimation, value: model.stage)
                }
            }
            .frame(height: 3)

            // Step label
            HStack {
                Text("STEP \(stageIndex + 1) / \(GuidedStockStage.allCases.count)")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .monospacedDigit()
                Spacer()
                Button {
                    exitFlow()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "xmark")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        Text("EXIT")
                            .font(OPSStyle.Typography.metadata)
                    }
                    .foregroundColor(isBuildRunning ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(.plain)
                .disabled(isBuildRunning)
                .accessibilityLabel("Exit guided setup")
                .accessibilityHint("Closes guided setup and keeps the current draft.")
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    // MARK: - Offline banner

    @ViewBuilder
    private var bannerStack: some View {
        if !dataController.isConnected {
            offlineBanner
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("// OFFLINE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(model.stage == .blueprint
                     ? "Build is held until you reconnect."
                     : "Changes are saved. Build requires a connection.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.fillNeutral)
        .overlay(
            Rectangle()
                .frame(height: OPSStyle.Layout.Border.standard)
                .foregroundColor(OPSStyle.Colors.separator),
            alignment: .bottom
        )
    }

    // MARK: - Stage content

    @ViewBuilder
    private var stageContent: some View {
        switch model.stage {
        case .prime:
            GuidedStockPrimeView(onStart: {
                withFlowAnimation { model.advance() }
            })
        case .capture:
            GuidedStockCaptureView(model: model)
        case .structure:
            GuidedStockStructureView(model: model)
        case .blueprint:
            GuidedStockBlueprintView(model: model)
        case .done:
            let summary: GuidedStockSummary = {
                if case .complete(let s) = model.commitProgress { return s }
                return GuidedStockSummary()
            }()
            GuidedStockDoneView(
                summary: summary,
                onDone: {
                    dismiss()
                },
                onRefineInAdvanced: {
                    dismiss()
                    NotificationCenter.default.post(
                        name: Notification.Name("OpenCatalogSetup"),
                        object: nil
                    )
                },
                onAddMore: {
                    withAnimation(flowAnimation) {
                        model.resetForAddMore()
                    }
                }
            )
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        switch model.stage {
        case .prime, .done, .structure:
            // .structure owns its own BACK + CTA; the container suppresses its chrome entirely.
            EmptyView()
        case .blueprint:
            blueprintBottomBar
        default:
            standardBottomBar
        }
    }

    // MARK: Blueprint bottom bar (commit-aware)

    @ViewBuilder
    private var blueprintBottomBar: some View {
        OPSFloatingButtonBar {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                // Partial error line
                if case .partial(let failedIds) = model.commitProgress {
                    Text("// ERROR - COULDN'T BUILD \(failedIds.count) \(failedIds.count == 1 ? "FAMILY" : "FAMILIES")")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.errorText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let reasonText = blueprintDisabledReason {
                    Text(reasonText)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: OPSStyle.Layout.spacing3) {
                    // BACK button — hidden while building
                    if !isBuildRunning {
                        Button {
                            withFlowAnimation { model.back() }
                        } label: {
                            Text("BACK")
                        }
                        .opsSecondaryButtonStyle()
                        .accessibilityLabel("Go back to previous step")
                    }

                    // Primary CTA — adapts to commit state
                    if case .partial = model.commitProgress {
                        Button {
                            runBuild()
                        } label: {
                            Text("RETRY")
                        }
                        .opsDestructiveButtonStyle()
                        .accessibilityLabel("Retry failed families")
                    } else {
                        Button {
                            if !isBuildRunning {
                                runBuild()
                            }
                        } label: {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                if isBuildRunning, case .running(let done, let total) = model.commitProgress {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.tertiaryText))
                                        .scaleEffect(0.75)
                                    Text("BUILDING \(done) OF \(total)")
                                } else {
                                    Text("BUILD IT")
                                }
                            }
                        }
                        .opsPrimaryButtonStyle(isDisabled: !buildCTAEnabled)
                        .disabled(!buildCTAEnabled)
                        .accessibilityLabel(isBuildRunning ? "Building" : "Build it")
                        .accessibilityValue(buildCTAEnabled ? "Ready" : "Locked")
                    }
                }
            }
        }
    }

    private var isBuildRunning: Bool {
        if case .running = model.commitProgress { return true }
        return isBuilding
    }

    private var buildCTAEnabled: Bool {
        guard !isBuildRunning else { return false }
        guard case .partial = model.commitProgress else {
            return !model.groups.isEmpty && dataController.isConnected
        }
        return false // partial uses RETRY button, not BUILD IT
    }

    private var blueprintDisabledReason: String? {
        guard !isBuildRunning else { return nil }
        if case .partial = model.commitProgress { return nil } // handled by error line
        if model.groups.isEmpty { return "// NOTHING TO BUILD YET" }
        if !dataController.isConnected { return "// OFFLINE — BUILD HELD" }
        return nil
    }

    // MARK: Standard bottom bar (capture stage)

    private var standardBottomBar: some View {
        OPSFloatingButtonBar {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if let reasonText = ctaDisabledReason {
                    Text(reasonText)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: OPSStyle.Layout.spacing3) {
                    Button {
                        withFlowAnimation { model.back() }
                    } label: {
                        Text("BACK")
                    }
                    .opsSecondaryButtonStyle()
                    .accessibilityLabel("Go back to previous step")

                    Button {
                        ctaAction()
                    } label: {
                        Text(ctaLabel)
                    }
                    .opsPrimaryButtonStyle(isDisabled: !ctaEnabled)
                    .disabled(!ctaEnabled)
                    .accessibilityLabel(ctaLabel)
                    .accessibilityValue(ctaEnabled ? "Ready" : "Locked")
                }
            }
        }
    }

    // MARK: - CTA configuration (non-blueprint stages)

    private var ctaLabel: String {
        switch model.stage {
        case .prime:     return ""
        case .capture:   return "ORGANIZE →"
        case .structure: return "REVIEW →"
        case .blueprint: return "BUILD IT →"
        case .done:      return ""
        }
    }

    private var ctaEnabled: Bool {
        switch model.stage {
        case .prime, .done:  return false
        case .capture:       return model.capturableItemCount > 0
        case .structure:     return true
        case .blueprint:     return !model.groups.isEmpty && dataController.isConnected
        }
    }

    private var ctaDisabledReason: String? {
        guard !ctaEnabled else { return nil }
        switch model.stage {
        case .capture:
            return "// ADD AT LEAST ONE ITEM"
        default:
            return nil
        }
    }

    private func ctaAction() {
        withFlowAnimation { model.advance() }
    }

    // MARK: - Commit orchestration

    private func runBuild() {
        guard !isBuilding else { return }
        isBuilding = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let capabilities = await CatalogSchemaCapabilityGate.refresh(companyId: model.companyId)
            let service = CatalogSetupCommitService(
                companyId: model.companyId,
                modelContext: modelContext,
                capabilities: capabilities,
                requestCatalogResync: { [dataController] in
                    Task { await dataController.syncEngine.triggerSync() }
                }
            )
            let resolver = GuidedStockUnitResolver(companyId: model.companyId, modelContext: modelContext)
            await model.commitAll(
                service: service,
                resolveUnitId: { try await resolver.resolveUnitId(for: $0) },
                isOnline: dataController.isConnected
            )
            isBuilding = false
        }
    }

    // MARK: - §14 completion notification

    private func postCompletionNotification(_ summary: GuidedStockSummary) {
        let userId = dataController.currentUser?.id ?? ""
        let companyId = model.companyId
        guard !userId.isEmpty, !companyId.isEmpty else { return }
        let body = GuidedStockSetupModel.summaryLine(summary)
        Task {
            try? await NotificationRepository.shared.createNotification(.init(
                userId: userId,
                companyId: companyId,
                type: "standard",
                title: "STOCK SYSTEM BUILT",
                body: body,
                deepLinkType: "catalog_stock",
                persistent: false,
                actionUrl: "/catalog?segment=stock",
                actionLabel: "VIEW STOCK"
            ))
            NotificationCenter.default.post(name: .notificationReceived, object: nil)
        }
    }

    // MARK: - Animation helpers

    private var flowAnimation: SwiftUI.Animation {
        reducedMotion
            ? .linear(duration: 0.15)
            : OPSStyle.Animation.page
    }

    private var stageTransition: AnyTransition {
        reducedMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            )
    }

    private func withFlowAnimation(_ body: () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(flowAnimation) {
            body()
        }
    }

    private func exitFlow() {
        model.persist()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
}

// MARK: - GuidedFlowCTAButtonStyle
//
// Full-width primary CTA: primaryAccent fill (or custom tint), white text, buttonRadius corner.
// Used exclusively in the guided flow bottom bar.

private struct GuidedFlowCTAButtonStyle: ButtonStyle {
    let isEnabled: Bool
    var tint: Color = OPSStyle.Colors.primaryAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.buttonLabel)
            .textCase(.uppercase)
            .foregroundColor(isEnabled ? .white : OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isEnabled
                ? tint.opacity(configuration.isPressed ? 0.80 : 1.0)
                : OPSStyle.Colors.fillNeutralDim
            )
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isEnabled ? tint : OPSStyle.Colors.separator,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
    }
}
