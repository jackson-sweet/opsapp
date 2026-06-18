//
//  GuidedCatalogSetupFlow.swift
//  OPS
//
//  Full-screen container for Guided Catalog Setup: survey → plan → modules →
//  done. Owns the progress bar, offline banner, exit + draft-resume, phase
//  routing, and the phase-appropriate bottom bar. Self-contained flow styling
//  (steel-blue primaryAccent) — NOT the overlay Wizard System.
//
//  Slice 1 ships the survey, plan, services + goods modules, and done. The
//  assembly and stock modules hand off to the existing flows until their
//  inline modules land (Slices 2-3).
//

import SwiftUI
import SwiftData

struct GuidedCatalogSetupFlow: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @ObservedObject private var permissionStore = PermissionStore.shared
    @StateObject private var model: GuidedCatalogSetupModel
    @Query private var allUnits: [CatalogUnit]

    private var companyUnits: [CatalogUnit] {
        allUnits.filter { $0.companyId == model.companyId && $0.deletedAt == nil }
    }

    @AppStorage("catalog.selectedSegment") private var selectedSegmentRaw: String = "STOCK"

    @State private var showResumePrompt = false

    init(companyId: String, userId: String) {
        _model = StateObject(wrappedValue: GuidedCatalogSetupModel(companyId: companyId, userId: userId))
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            content
        }
        .trackScreen("Catalog.GuidedSetup")
        .onAppear {
            if permissionStore.can("catalog.products.manage") && model.hasDraftToResume {
                showResumePrompt = true
            }
        }
        .confirmationDialog("Pick up where you left off?",
                            isPresented: $showResumePrompt,
                            titleVisibility: .visible) {
            Button("RESUME") { _ = model.restoreIfAvailable() }
            Button("START OVER", role: .destructive) {
                model.clearDraft()
                model.phase = .survey(questionIndex: 0)
                model.profile = nil
                model.productLines = []
                model.savedLines = []
                model.savedAssemblies = []
                model.resetSurvey()
            }
        } message: {
            Text("You have an unfinished catalog setup.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if permissionStore.can("catalog.products.manage") {
            VStack(spacing: 0) {
                topProgress
                if !dataController.isConnected { offlineBanner }
                phaseContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(stageTransition)
                    .animation(flowAnimation, value: phaseKey)
                bottomBar
            }
        } else {
            permissionGate
        }
    }

    // MARK: - Phase routing

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .survey:
            GuidedSetupSurveyView(model: model)
        case .plan:
            GuidedSetupPlanView(model: model)
        case .module:
            moduleContent
        case .done:
            GuidedSetupDoneView(model: model)
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        if let kind = model.currentModule {
            switch kind {
            case .services:
                ProductLineModuleView(model: model, kind: .service, isOnline: dataController.isConnected)
            case .goods:
                ProductLineModuleView(model: model, kind: .good, isOnline: dataController.isConnected)
            case .assembly:
                AssemblyModuleView(model: model, isOnline: dataController.isConnected)
            case .stock:
                handoff(eyebrow: "YOUR STOCK",
                        title: "COUNT YOUR STOCK",
                        body: "Track what's on hand and get a heads-up when it's time to reorder.",
                        actionLabel: "SET UP STOCK") { routeToStock() }
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Progress

    private var phaseKey: String {
        switch model.phase {
        case .survey(let i): return "survey-\(i)"
        case .plan:          return "plan"
        case .module(let i): return "module-\(i)"
        case .done:          return "done"
        }
    }

    private var progressFraction: CGFloat {
        let total = CGFloat(3 + model.modules.count) // survey, plan, modules…, done
        let step: CGFloat
        switch model.phase {
        case .survey:        step = 1
        case .plan:          step = 2
        case .module(let i): step = CGFloat(3 + i)
        case .done:          step = total
        }
        return max(0, min(1, step / total))
    }

    private var topProgress: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(OPSStyle.Colors.secondaryText.opacity(0.20))
                        .frame(height: 3)
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryText)
                        .frame(width: geo.size.width * progressFraction, height: 3)
                        .animation(flowAnimation, value: progressFraction)
                }
            }
            .frame(height: 3)

            HStack {
                if model.canGoBack {
                    Button { goBack() } label: {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                            Text("BACK")
                                .font(OPSStyle.Typography.metadata)
                        }
                        .foregroundColor(model.isSaving ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSaving)
                    .accessibilityLabel("Go back one step")
                }
                Spacer()
                Button { exitFlow() } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "xmark")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        Text("EXIT")
                            .font(OPSStyle.Typography.metadata)
                    }
                    .foregroundColor(model.isSaving ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(.plain)
                .disabled(model.isSaving)
                .accessibilityLabel("Exit catalog setup")
                .accessibilityHint("Closes setup and keeps your progress.")
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    private var offlineBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("// OFFLINE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("Adding pauses until you're back online. Your place is saved.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.surfaceInput)
        .overlay(
            Rectangle()
                .frame(height: OPSStyle.Layout.Border.standard)
                .foregroundColor(OPSStyle.Colors.separator),
            alignment: .bottom
        )
    }

    // MARK: - Bottom bar

    /// Whether the operator has committed anything in the current module — drives
    /// the SKIP vs NEXT label so empty optional modules read as skippable.
    private var currentModuleHasItems: Bool {
        switch model.currentModule {
        case .services: return model.savedLines.contains { $0.kind == .service }
        case .goods:    return model.savedLines.contains { $0.kind == .good }
        case .assembly: return !model.savedAssemblies.isEmpty
        case .stock, .none: return false
        }
    }

    /// FINISH on the last module; otherwise SKIP when nothing's been added, NEXT once it has.
    private func advanceLabel(isLast: Bool) -> String {
        if isLast { return "FINISH" }
        return currentModuleHasItems ? "NEXT" : "SKIP"
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch model.phase {
        case .survey:
            EmptyView()
        case .plan:
            OPSFloatingButtonBar {
                Button { startPlan() } label: { Text("START") }
                    .opsPrimaryButtonStyle()
                    .accessibilityLabel("Start setup")
            }
        case .module(let index):
            let isLast = index >= model.modules.count - 1
            OPSFloatingButtonBar {
                Button { advance() } label: { Text(advanceLabel(isLast: isLast)) }
                    .opsPrimaryButtonStyle()
                    .accessibilityLabel(isLast ? "Finish setup"
                                               : (currentModuleHasItems ? "Next step" : "Skip this step"))
            }
        case .done:
            OPSFloatingButtonBar {
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    Button { viewCatalog() } label: { Text("VIEW CATALOG") }
                        .opsSecondaryButtonStyle()
                    Button { finish() } label: { Text("DONE") }
                        .opsPrimaryButtonStyle()
                }
            }
        }
    }

    // MARK: - Handoff (assembly / stock — interim until inline modules land)

    private func handoff(eyebrow: String, title: String, body: String,
                         actionLabel: String, action: @escaping () -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("// \(eyebrow)")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(title)
                        .font(OPSStyle.Typography.pageTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(body)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button { action() } label: { Text(actionLabel) }
                    .opsPrimaryButtonStyle()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Permission gate

    private var permissionGate: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Text("// ACCESS RESTRICTED")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Text("Catalog setup needs product management access.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
            Button("CLOSE") { dismiss() }
                .opsPrimaryButtonStyle()
                .padding(.horizontal, OPSStyle.Layout.spacing4)
            Spacer()
        }
    }

    // MARK: - Actions

    private func startPlan() {
        if dataController.isConnected {
            model.seedDefaultUnitsIfNeeded(existing: companyUnits, modelContext: modelContext)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(flowAnimation) { model.confirmPlan() }
    }

    private func advance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(flowAnimation) { model.advanceModule() }
    }

    private func viewCatalog() {
        model.clearDraft()
        selectedSegmentRaw = "PRODUCTS"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }

    private func finish() {
        model.clearDraft()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }

    private func routeToStock() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + (reducedMotion ? 0.05 : 0.25)) {
            NotificationCenter.default.post(name: Notification.Name("OpenGuidedStockSetup"), object: nil)
        }
    }

    private func goBack() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(flowAnimation) { model.goBack() }
    }

    private func exitFlow() {
        if case .survey = model.phase {
            model.clearDraft() // nothing worth resuming yet
        } else {
            model.persist()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }

    // MARK: - Animation

    private var flowAnimation: SwiftUI.Animation {
        reducedMotion ? .linear(duration: 0.15) : OPSStyle.Animation.page
    }

    private var stageTransition: AnyTransition {
        reducedMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                          removal: .opacity.combined(with: .move(edge: .leading)))
    }
}
