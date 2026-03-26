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
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissionStore: PermissionStore

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
                    .padding(.top, 8)

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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .padding(.bottom, 8)

                    directionHints
                        .padding(.bottom, 8)
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
        }
        .onDisappear {
            // Wizard system: notify payment review dismissed
            NotificationCenter.default.post(
                name: Notification.Name("WizardPaymentReviewDismissed"),
                object: nil
            )
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
                Text("COMPLETION REVIEW")
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
        .padding(.horizontal, 16)
    }

    // MARK: - Direction Hints

    private var directionHints: some View {
        HStack(spacing: 12) {
            hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)
            hintPill(icon: "arrow.right", label: "CLOSE", color: OPSStyle.Colors.successStatus)
            if hasFinancialAccess {
                hintPill(icon: "arrow.up", label: "REMIND", color: OPSStyle.Colors.primaryAccent)
                hintPill(icon: "arrow.down", label: "WRITE OFF", color: OPSStyle.Colors.errorStatus)
            }
        }
        .padding(.horizontal, 16)
    }

    private func hintPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: - No Overdue (but has completed)

    private var noOverdueView: some View {
        VStack(spacing: 16) {
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
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                // Primary CTA
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        activeProjects = completedProjects
                        reviewingCompleted = true
                    }
                }) {
                    HStack {
                        Text("REVIEW COMPLETED PROJECTS")
                            .font(OPSStyle.Typography.button)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    }
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }

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
                    .padding(.horizontal, 20)
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
        VStack(spacing: 16) {
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
                .padding(.horizontal, 20)
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

            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                celebrationScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                celebrationOpacity = 1.0
            }
        }
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
            // Don't increment yet -- confirmation pending
            reviewedCount -= 1
            pendingWriteOffProject = project
            showWriteOffConfirmation = true
        }

        checkCompletion()
    }

    private func executeClose(_ project: Project) {
        guard project.modelContext != nil else { return }
        project.status = .closed
        project.needsSync = true
    }

    private func executeSendReminder(_ project: Project) {
        // Future: send actual reminder. For now, just a note placeholder.
        print("[PaymentReview] Reminder sent for project: \(project.title)")
    }

    private func executeWriteOff(_ project: Project) {
        guard project.modelContext != nil else { return }
        project.status = .closed
        project.needsSync = true

        // Write off outstanding invoices if user has financial access
        if hasFinancialAccess {
            Task {
                await writeOffOutstandingInvoices(for: project)
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
                    && dto.balanceDue > 0
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
            withAnimation(.spring().delay(0.3)) {
                showAllCaughtUp = true
            }
        }
    }
}
