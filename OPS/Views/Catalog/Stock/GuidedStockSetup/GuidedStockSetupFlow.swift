import SwiftUI

// MARK: - GuidedStockSetupFlow
//
// Full-screen flow container for the guided stock setup wizard.
// Presented via .fullScreenCover by entry points (wired in a later task).
// Owns: progress indicator, offline banner, stage routing, bottom CTA bar,
//       draft-resume confirmation dialog, and haptic orchestration.

struct GuidedStockSetupFlow: View {

    // MARK: - Dependencies

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @ObservedObject private var permissionStore = PermissionStore.shared
    @StateObject private var model: GuidedStockSetupModel
    @State private var showResumePrompt = false

    // MARK: - Init

    init(companyId: String, userId: String) {
        _model = StateObject(wrappedValue: GuidedStockSetupModel(companyId: companyId, userId: userId))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
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
        .background(OPSStyle.Colors.cardBackground)
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
            GuidedStockDoneView(model: model, onClose: { dismiss() })
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        switch model.stage {
        case .prime, .done:
            EmptyView()
        default:
            VStack(spacing: OPSStyle.Layout.spacing2) {
                // Reason line (shown when CTA is disabled)
                if let reasonText = ctaDisabledReason {
                    Text(reasonText)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                }

                HStack(spacing: OPSStyle.Layout.spacing3) {
                    // BACK button
                    Button {
                        withFlowAnimation { model.back() }
                    } label: {
                        Text("BACK")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(minWidth: 72, minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go back to previous step")

                    // Primary CTA
                    Button {
                        ctaAction()
                    } label: {
                        Text(ctaLabel)
                    }
                    .buttonStyle(GuidedFlowCTAButtonStyle(isEnabled: ctaEnabled))
                    .disabled(!ctaEnabled)
                    .accessibilityLabel(ctaLabel)
                    .accessibilityValue(ctaEnabled ? "Ready" : "Locked")
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.backgroundGradient.ignoresSafeArea())
        }
    }

    // MARK: - CTA configuration per stage

    private var ctaLabel: String {
        switch model.stage {
        case .prime:  return ""
        case .capture: return "ORGANIZE →"
        case .structure: return "REVIEW →"
        case .blueprint: return "BUILD IT →"
        case .done:   return ""
        }
    }

    private var ctaEnabled: Bool {
        switch model.stage {
        case .prime, .done: return false
        case .capture: return !model.capturedItems.isEmpty
        case .structure: return true
        case .blueprint: return !model.groups.isEmpty && dataController.isConnected
        }
    }

    private var ctaDisabledReason: String? {
        guard !ctaEnabled else { return nil }
        switch model.stage {
        case .capture:
            return "// ADD AT LEAST ONE ITEM"
        case .blueprint:
            if model.groups.isEmpty {
                return "// NOTHING TO BUILD YET"
            }
            if !dataController.isConnected {
                return "// OFFLINE — BUILD HELD"
            }
            return nil
        default:
            return nil
        }
    }

    private func ctaAction() {
        withFlowAnimation { model.advance() }
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
}

// MARK: - GuidedFlowCTAButtonStyle
//
// Full-width primary CTA: primaryAccent fill, white text, buttonRadius corner.
// Used exclusively in the guided flow bottom bar.

private struct GuidedFlowCTAButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.buttonLabel)
            .textCase(.uppercase)
            .foregroundColor(isEnabled ? .white : OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isEnabled
                ? OPSStyle.Colors.primaryAccent.opacity(configuration.isPressed ? 0.80 : 1.0)
                : OPSStyle.Colors.cardBackground
            )
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(
                        isEnabled ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.separator,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
    }
}
