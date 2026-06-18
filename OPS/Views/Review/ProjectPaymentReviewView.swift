//
//  ProjectPaymentReviewView.swift
//  OPS
//

import SwiftUI
import SwiftData

/// Full-screen Tinder-style project payment review.
struct ProjectPaymentReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.wizardStateManager) private var wizardStateManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissionStore: PermissionStore
    @EnvironmentObject var dataController: DataController

    let overdueProjects: [Project]
    let completedProjects: [Project]

    /// Which list is actively being reviewed
    @State private var activeProjects: [Project] = []
    @State private var reviewingCompleted: Bool = false

    @State private var reviewedCount: Int = 0
    @State private var showBio: Bool = false
    @State private var selectedProject: Project? = nil
    @State private var showWriteOffConfirmation: Bool = false
    @State private var pendingWriteOffProject: Project? = nil
    @State private var showAllCaughtUp: Bool = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0

    private var hasFinancialAccess: Bool {
        permissionStore.can("finances.view")
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            // Full-bleed card stack when actively reviewing
            if (!activeProjects.isEmpty || reviewingCompleted) && !showAllCaughtUp {
                ProjectReviewCardStack(
                    projects: activeProjects,
                    hasFinancialAccess: hasFinancialAccess,
                    onSwipe: handleSwipe,
                    onTapCard: { project in
                        selectedProject = project
                        showBio = true
                    }
                )
                .ignoresSafeArea()
            }

            // UI overlay
            VStack(spacing: 0) {
                header
                    .padding(.top, OPSStyle.Layout.spacing2)

                if activeProjects.isEmpty && !reviewingCompleted {
                    if !completedProjects.isEmpty {
                        noOverdueView
                    } else {
                        allCaughtUpView
                    }
                } else if showAllCaughtUp {
                    allCaughtUpView
                } else {
                    Spacer()

                    // Counter
                    Text("\(reviewedCount) OF \(activeProjects.count) REVIEWED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .padding(.bottom, OPSStyle.Layout.spacing2)

                    directionHints
                        .padding(.bottom, OPSStyle.Layout.spacing2)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
            }
        }
        .onAppear {
            // Start with overdue if any
            if !overdueProjects.isEmpty {
                activeProjects = overdueProjects
            }
            // Wizard system: notify payment review opened
            NotificationCenter.default.post(
                name: Notification.Name("WizardPaymentReviewOpened"),
                object: nil
            )
            // Wizard system: auto-skip "tap_review_completed" when overdue exist
            // (card stack is shown immediately, no intermediate screen).
            // Also pass card count for swipe step auto-skip.
            if let mgr = wizardStateManager, mgr.isActive {
                let cardCount = activeProjects.count
                mgr.evaluateStepPrerequisites(
                    paymentReviewCardCount: cardCount,
                    hasOverdueProjects: !overdueProjects.isEmpty
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardEvaluatePrerequisites"))) { _ in
            // Re-evaluate prerequisites when wizard advances to a new step
            if let mgr = wizardStateManager, mgr.isActive {
                let remainingCards = max(0, activeProjects.count - reviewedCount)
                mgr.evaluateStepPrerequisites(
                    paymentReviewCardCount: remainingCards,
                    hasOverdueProjects: !overdueProjects.isEmpty
                )
            }
        }
        .onDisappear {
            // Wizard system: notify payment review dismissed (step 5 completion)
            NotificationCenter.default.post(
                name: Notification.Name("WizardPaymentReviewDismissed"),
                object: nil
            )
            // Wizard system: notify screen dismissed (exit prompt for steps 2-5).
            // Delay so step completion notifications process first — the wizard
            // advances before the dismissal check runs.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(
                    name: Notification.Name("WizardScreenDismissed"),
                    object: nil,
                    userInfo: ["screen": "PaymentReview"]
                )
            }
        }
        .sheet(isPresented: $showBio) {
            if let project = selectedProject {
                ProjectBioSheet(
                    project: project,
                    showFinancialInfo: hasFinancialAccess,
                    onDismiss: { showBio = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Write Off as Bad Debt?", isPresented: $showWriteOffConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingWriteOffProject = nil
                reviewedCount += 1
                checkCompletion()
            }
            Button("Write Off & Close", role: .destructive) {
                if let project = pendingWriteOffProject {
                    executeWriteOff(project)
                    pendingWriteOffProject = nil
                }
            }
        } message: {
            Text("This will close the project and write off the outstanding balance. This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("CLOSE OUT REVIEW")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                if !activeProjects.isEmpty {
                    Text("\(activeProjects.count) \(reviewingCompleted ? "COMPLETED" : "OVERDUE")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Direction Hints

    private var directionHints: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)
            hintPill(icon: "arrow.right", label: "CLOSE", color: OPSStyle.Colors.successStatus)
            if hasFinancialAccess {
                hintPill(icon: "arrow.up", label: "REMIND", color: OPSStyle.Colors.primaryAccent)
                hintPill(icon: "arrow.down", label: "WRITE OFF", color: OPSStyle.Colors.errorStatus)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func hintPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(color)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: - No Overdue (but has completed)

    private var noOverdueView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            // Icon with accent ring
            ZStack {
                Circle()
                    .stroke(OPSStyle.Colors.successStatus.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(OPSStyle.Colors.successStatus)
            }

            Text("NO OVERDUE PROJECTS")
                .font(OPSStyle.Typography.headingLarge)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("You have \(completedProjects.count) completed project\(completedProjects.count == 1 ? "" : "s") to review")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.leading)

            Spacer()

            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Primary CTA
                Button(action: {
                    withAnimation(OPSStyle.Animation.standard) {
                        activeProjects = completedProjects
                        reviewingCompleted = true
                    }
                    // Wizard system: notify completed projects loaded into card stack
                    NotificationCenter.default.post(
                        name: Notification.Name("WizardCompletedProjectsLoaded"),
                        object: nil
                    )
                }) {
                    HStack {
                        Text("REVIEW COMPLETED PROJECTS")
                            .font(OPSStyle.Typography.button)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    }
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .wizardTarget("tap_review_completed")

                // Secondary dismiss
                Button(action: { dismiss() }) {
                    HStack {
                        Text("DISMISS")
                            .font(OPSStyle.Typography.button)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - All Caught Up

    private var allCaughtUpView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            // Icon with accent ring
            ZStack {
                Circle()
                    .stroke(OPSStyle.Colors.successStatus.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                    .scaleEffect(celebrationScale)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .scaleEffect(celebrationScale)
            }

            Text("ALL CAUGHT UP")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .opacity(celebrationOpacity)

            Text("No projects need review")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .opacity(celebrationOpacity)

            Spacer()

            Button(action: { dismiss() }) {
                HStack {
                    Text("DONE")
                        .font(OPSStyle.Typography.button)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                }
                .foregroundColor(OPSStyle.Colors.invertedText)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryText)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .opacity(celebrationOpacity)
        }
        .onAppear {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            withAnimation(celebrationScaleAnimation) {
                celebrationScale = 1.0
            }
            withAnimation(celebrationOpacityAnimation) {
                celebrationOpacity = 1.0
            }
        }
    }

    // MARK: - Motion (spec: one curve, no spring; reduce-motion → near-instant)

    private var celebrationScaleAnimation: Animation {
        reduceMotion
            ? OPSStyle.Animation.hover
            : OPSStyle.Animation.flip
    }

    private var celebrationOpacityAnimation: Animation {
        reduceMotion
            ? OPSStyle.Animation.hover.delay(0.3)
            : .easeOut(duration: 0.4).delay(0.3)
    }

    private var allCaughtUpTransitionAnimation: Animation {
        reduceMotion
            ? OPSStyle.Animation.hover.delay(0.3)
            : OPSStyle.Animation.page.delay(0.3)
    }

    // MARK: - Swipe Handlers

    private func handleSwipe(_ project: Project, _ direction: SwipeDirection) {
        reviewedCount += 1

        switch direction {
        case .right:
            executeClose(project)
            NotificationCenter.default.post(name: Notification.Name("WizardProjectSwipedRight"), object: nil)
        case .left:
            NotificationCenter.default.post(name: Notification.Name("WizardProjectSwipedLeft"), object: nil)
            break // Skip -- no data changes
        case .up:
            executeSendReminder(project)
            NotificationCenter.default.post(name: Notification.Name("WizardProjectSwipedUp"), object: nil)
        case .down:
            // Don't increment yet — confirmation pending
            reviewedCount -= 1
            pendingWriteOffProject = project
            showWriteOffConfirmation = true
            // Wizard notification fires on swipe initiation (user saw the gesture work).
            // The confirmation dialog is a separate UX step, not part of the wizard demo.
            NotificationCenter.default.post(name: Notification.Name("WizardProjectSwipedDown"), object: nil)
        }

        checkCompletion()
    }

    private func executeClose(_ project: Project) {
        // Canonical path — saves context, records SyncOperation, and pushes
        // immediately. Direct mutation was losing every swipe-right because
        // no outbound operation was being recorded.
        Task {
            do {
                try await dataController.updateProjectStatus(project: project, to: .closed)
                await MainActor.run {
                    ToastCenter.shared.present(Feedback.JobBoard.projectClosed)
                }
            } catch {
                print("[PaymentReview] Failed to close project: \(error)")
            }
        }
    }

    private func executeSendReminder(_ project: Project) {
        // Future: send actual reminder. For now, just a note placeholder.
        print("[PaymentReview] Reminder sent for project: \(project.title)")
        ToastCenter.shared.present(Feedback.Invoice.reminderSent)
    }

    private func executeWriteOff(_ project: Project) {
        Task {
            do {
                try await dataController.updateProjectStatus(project: project, to: .closed)
            } catch {
                print("[PaymentReview] Failed to close project for write-off: \(error)")
            }

            // Write off outstanding invoices if user has financial access
            if hasFinancialAccess {
                await writeOffOutstandingInvoices(for: project)
            }

            await MainActor.run {
                ToastCenter.shared.present(Feedback.Invoice.writtenOff)
            }
        }

        reviewedCount += 1
        checkCompletion()
    }

    /// Finds invoices linked to this project with outstanding balances and marks them as written off.
    private func writeOffOutstandingInvoices(for project: Project) async {
        let repo = InvoiceRepository(companyId: project.companyId)
        do {
            let allDTOs = try await repo.fetchAll()
            let outstanding = allDTOs.filter { dto in
                dto.projectId == project.id
                    && (dto.balanceDue ?? 0) > 0
                    && dto.status != InvoiceStatus.void.rawValue
                    && dto.status != InvoiceStatus.writtenOff.rawValue
            }

            for dto in outstanding {
                try await repo.updateStatus(dto.id, status: .writtenOff)
                print("[PaymentReview] Wrote off invoice \(dto.invoiceNumber) for project: \(project.title)")
            }
        } catch {
            print("[PaymentReview] Failed to write off invoices: \(error)")
        }
    }

    private func checkCompletion() {
        if reviewedCount >= activeProjects.count {
            withAnimation(allCaughtUpTransitionAnimation) {
                showAllCaughtUp = true
            }
        }
    }
}
