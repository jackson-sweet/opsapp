//
//  ProjectPaymentReviewView.swift
//  OPS
//

import SwiftUI
import SwiftData

/// Full-screen project closeout and payment review.
struct ProjectPaymentReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.wizardStateManager) private var wizardStateManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var permissionStore: PermissionStore
    @EnvironmentObject var dataController: DataController

    private let overdueProjectIDs: Set<String>
    private let repository = PaymentReviewRepository()

    @State private var session: ProjectReviewSession
    @State private var isPreparing = true
    @State private var financialLoadFailed = false
    @State private var reviewingProjects = false
    @State private var financialsByProjectID: [String: PaymentReviewFinancialSummary] = [:]
    @State private var showBio = false
    @State private var selectedProject: Project?
    @State private var showWriteOffConfirmation = false
    @State private var pendingWriteOffProject: Project?
    @State private var pendingWriteOffResolution: ((Bool) -> Void)?
    @State private var writeOffIdempotencyKeys: [String: String] = [:]
    @State private var showAllCaughtUp = false
    @State private var celebrationScale: CGFloat = 0
    @State private var celebrationOpacity: Double = 0

    init(overdueProjects: [Project], completedProjects: [Project]) {
        overdueProjectIDs = Set(overdueProjects.map(\.id))
        _session = State(initialValue: ProjectReviewSession(
            overdueProjects: overdueProjects,
            completedProjects: completedProjects
        ))
    }

    private var accessPolicy: PaymentReviewAccessPolicy {
        PaymentReviewAccessPolicy(
            currentUserID: dataController.currentUser?.id,
            projectEditScope: ReviewPermissionScope(
                permissionStore.scope(for: "projects.edit")
            ),
            canViewInvoices: permissionStore.hasFullAccess("invoices.view")
                && permissionStore.hasFullAccess("finances.view"),
            canSendInvoices: permissionStore.hasFullAccess("invoices.send"),
            canEditInvoices: permissionStore.hasFullAccess("invoices.edit")
        )
    }

    private var currentProject: Project? {
        guard session.projects.indices.contains(session.reviewedCount) else { return nil }
        return session.projects[session.reviewedCount]
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            if isPreparing {
                ProgressView()
                    .tint(OPSStyle.Colors.primaryText)
                    .accessibilityLabel("Loading project review")
            } else if !financialLoadFailed && reviewingProjects && !showAllCaughtUp {
                ProjectReviewCardStack(
                    projects: session.projects,
                    financialsByProjectID: financialsByProjectID,
                    accessPolicy: accessPolicy,
                    onSwipe: handleSwipe,
                    onAdvance: finishReview,
                    onTapCard: { project in
                        selectedProject = project
                        showBio = true
                    }
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header
                    .padding(.top, OPSStyle.Layout.spacing2)

                if !isPreparing {
                    if financialLoadFailed {
                        financialLoadFailureView
                    } else if session.projects.isEmpty {
                        emptyStateView
                    } else if showAllCaughtUp {
                        allCaughtUpView
                    } else if !reviewingProjects {
                        noOverdueView
                    } else {
                        Spacer()

                        Text("\(session.reviewedCount) OF \(session.totalCount) REVIEWED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .background(Color.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                            .accessibilityLabel("\(session.reviewedCount) of \(session.totalCount) projects reviewed")

                        directionHints
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                    }
                }
            }
        }
        .task { await prepareReview() }
        .onAppear {
            NotificationCenter.default.post(
                name: Notification.Name("WizardPaymentReviewOpened"),
                object: nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("WizardEvaluatePrerequisites")
        )) { _ in
            wizardStateManager?.evaluateStepPrerequisites(
                paymentReviewCardCount: session.remainingCount,
                hasOverdueProjects: !overdueProjectIDs.isEmpty
            )
        }
        .onDisappear {
            NotificationCenter.default.post(
                name: Notification.Name("WizardPaymentReviewDismissed"),
                object: nil
            )
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
                    showFinancialInfo: accessPolicy.canViewInvoices,
                    financialSummary: financialsByProjectID[project.id],
                    onDismiss: { showBio = false }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Write Off Outstanding Balance?", isPresented: $showWriteOffConfirmation) {
            Button("Keep Balance", role: .cancel) { cancelWriteOff() }
            Button("Write Off & Close", role: .destructive) {
                guard let project = pendingWriteOffProject,
                      let resolution = pendingWriteOffResolution else {
                    cancelWriteOff()
                    return
                }
                executeWriteOff(project, resolution: resolution)
            }
        } message: {
            if let project = pendingWriteOffProject,
               let summary = financialsByProjectID[project.id] {
                Text("This writes off \(BooksFormat.exact(summary.outstandingBalance, code: summary.currencyCode)) and closes the project. This cannot be undone.")
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(
                        width: OPSStyle.Layout.touchTargetMin,
                        height: OPSStyle.Layout.touchTargetMin
                    )
            }
            .accessibilityLabel("Close project review")

            Spacer()

            VStack(spacing: OPSStyle.Layout.spacing1) {
                Text("CLOSE OUT REVIEW")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                if !session.projects.isEmpty {
                    Text("\(session.totalCount) PROJECT\(session.totalCount == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()
            Color.clear.frame(
                width: OPSStyle.Layout.touchTargetMin,
                height: OPSStyle.Layout.touchTargetMin
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private var directionHints: some View {
        let allowed = currentProject.map(allowedDirections) ?? []
        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            if allowed.contains(.left) {
                hintPill(icon: "arrow.left", label: "SKIP", color: OPSStyle.Colors.tertiaryText)
            }
            if allowed.contains(.right) {
                hintPill(icon: "arrow.right", label: "CLOSE", color: OPSStyle.Colors.successStatus)
            }
            if allowed.contains(.up) {
                hintPill(icon: "arrow.up", label: "QUEUE", color: OPSStyle.Colors.primaryAccent)
            }
            if allowed.contains(.down) {
                hintPill(icon: "arrow.down", label: "WRITE OFF", color: OPSStyle.Colors.errorStatus)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .accessibilityHidden(true)
    }

    private func hintPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .bold))
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
        }
        .foregroundColor(color)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    private var noOverdueView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(
                        OPSStyle.Colors.successStatus.opacity(0.15),
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
                    .frame(
                        width: OPSStyle.Layout.touchTargetLarge,
                        height: OPSStyle.Layout.touchTargetLarge
                    )
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.xxl, weight: .light))
                    .foregroundColor(OPSStyle.Colors.successStatus)
            }

            Text("NO OVERDUE PROJECTS")
                .font(OPSStyle.Typography.headingLarge)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("\(session.totalCount) completed project\(session.totalCount == 1 ? "" : "s") ready to close out")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.leading)

            Spacer()

            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                reviewCompletedButton
                Button(action: { dismiss() }) {
                    actionRow(label: "DISMISS", foreground: OPSStyle.Colors.primaryText)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(
                                    OPSStyle.Colors.buttonBorder,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        )
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing5)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
    }

    private var reviewCompletedButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) {
                reviewingProjects = true
            }
            NotificationCenter.default.post(
                name: Notification.Name("WizardCompletedProjectsLoaded"),
                object: nil
            )
        } label: {
            actionRow(
                label: "REVIEW COMPLETED PROJECTS",
                foreground: OPSStyle.Colors.invertedText
            )
            .background(OPSStyle.Colors.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
        .wizardTarget("tap_review_completed")
    }

    private func actionRow(label: String, foreground: Color) -> some View {
        HStack {
            Text(label).font(OPSStyle.Typography.button)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
        }
        .foregroundColor(foreground)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity)
        .frame(height: OPSStyle.Layout.touchTargetStandard)
    }

    private var emptyStateView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl, weight: .light))
                .foregroundColor(OPSStyle.Colors.successStatus)
            Text("NO PROJECTS TO REVIEW")
                .font(OPSStyle.Typography.headingLarge)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
        }
    }

    private var financialLoadFailureView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl, weight: .light))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            Text("BALANCE DATA UNAVAILABLE")
                .font(OPSStyle.Typography.headingLarge)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Project actions stay locked until invoice balances are confirmed.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                Task { await prepareReview() }
            } label: {
                actionRow(
                    label: "RETRY",
                    foreground: OPSStyle.Colors.invertedText
                )
                .background(OPSStyle.Colors.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
            .padding(.horizontal, OPSStyle.Layout.spacing5)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
        .accessibilityElement(children: .contain)
    }

    private var allCaughtUpView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(
                        OPSStyle.Colors.successStatus.opacity(0.15),
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
                    .frame(
                        width: OPSStyle.Layout.touchTargetLarge,
                        height: OPSStyle.Layout.touchTargetLarge
                    )
                    .scaleEffect(celebrationScale)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.xxl, weight: .light))
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .scaleEffect(celebrationScale)
            }

            Text("REVIEW COMPLETE")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .opacity(celebrationOpacity)
            Text("\(session.totalCount) project\(session.totalCount == 1 ? "" : "s") checked")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .opacity(celebrationOpacity)
            Spacer()

            Button(action: { dismiss() }) {
                actionRow(label: "DONE", foreground: OPSStyle.Colors.invertedText)
                    .background(OPSStyle.Colors.primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
            .padding(.horizontal, OPSStyle.Layout.spacing5)
            .padding(.bottom, OPSStyle.Layout.spacing5)
            .opacity(celebrationOpacity)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if reduceMotion {
                celebrationScale = 1
                withAnimation(OPSStyle.Animation.hover) {
                    celebrationOpacity = 1
                }
            } else {
                withAnimation(OPSStyle.Animation.flip) { celebrationScale = 1 }
                withAnimation(OPSStyle.Animation.panel.delay(OPSStyle.Animation.durationStagger)) {
                    celebrationOpacity = 1
                }
            }
        }
    }

    @MainActor
    private func prepareReview() async {
        isPreparing = true
        financialLoadFailed = false

        let permitted = session.projects.filter { project in
            accessPolicy.canClose(projectTeamMemberIDs: projectAccessIDs(project))
        }
        guard accessPolicy.projectEditScope != nil else {
            isPreparing = false
            session = ProjectReviewSession(projects: [])
            ToastCenter.shared.present(
                Toast(label: "// PROJECT EDIT ACCESS REQUIRED", tone: .warning)
            )
            return
        }

        session = ProjectReviewSession(projects: permitted)
        reviewingProjects = permitted.contains { overdueProjectIDs.contains($0.id) }

        wizardStateManager?.evaluateStepPrerequisites(
            paymentReviewCardCount: reviewingProjects ? session.totalCount : 0,
            hasOverdueProjects: reviewingProjects
        )

        guard accessPolicy.canViewInvoices, !permitted.isEmpty else {
            isPreparing = false
            return
        }
        do {
            financialsByProjectID = try await repository.fetchFinancialSummaries(
                projectIDs: permitted.map(\.id),
                companyID: dataController.currentUser?.companyId
            )
            isPreparing = false
        } catch {
            presentFinancialLoadFailure()
        }
    }

    private func handleSwipe(
        _ project: Project,
        _ direction: SwipeDirection,
        _ resolution: @escaping (Bool) -> Void
    ) {
        switch direction {
        case .left:
            NotificationCenter.default.post(
                name: Notification.Name("WizardProjectSwipedLeft"),
                object: nil
            )
            resolution(true)
        case .right:
            executeClose(project, resolution: resolution)
        case .up:
            executeSendReminder(project, resolution: resolution)
        case .down:
            pendingWriteOffProject = project
            pendingWriteOffResolution = resolution
            showWriteOffConfirmation = true
        }
    }

    private func executeClose(
        _ project: Project,
        resolution: @escaping (Bool) -> Void
    ) {
        Task {
            do {
                _ = try await repository.closeProject(project.id)
                await MainActor.run {
                    guard applyAuthoritativeClose(project) else {
                        presentCloseReconciliationFailure()
                        resolution(false)
                        return
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(Feedback.JobBoard.projectClosed)
                    NotificationCenter.default.post(
                        name: Notification.Name("WizardProjectSwipedRight"),
                        object: nil
                    )
                    resolution(true)
                }
            } catch {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    ToastCenter.shared.present(
                        Toast(
                            label: "// CLOSE FAILED — SWIPE TO RETRY",
                            tone: .error,
                            autoDismissAfter: 0
                        )
                    )
                    resolution(false)
                }
            }
        }
    }

    private func executeSendReminder(
        _ project: Project,
        resolution: @escaping (Bool) -> Void
    ) {
        Task {
            do {
                let result = try await repository.queueReminder(project.id)
                await MainActor.run {
                    let label = result.queuedCount > 0
                        ? "// REMINDER QUEUED FOR APPROVAL"
                        : "// REMINDER ALREADY QUEUED"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    ToastCenter.shared.present(Toast(label: label, tone: .success))
                    NotificationCenter.default.post(
                        name: Notification.Name("WizardProjectSwipedUp"),
                        object: nil
                    )
                    resolution(true)
                }
            } catch PaymentReviewRepositoryError.noReminderDue {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    ToastCenter.shared.present(
                        Toast(label: "// NO REMINDER DUE — SKIP OR CLOSE", tone: .warning)
                    )
                    resolution(false)
                }
            } catch PaymentReviewRepositoryError.reminderBlocked(let reason) {
                await MainActor.run {
                    let label: String
                    switch reason {
                    case .mailboxRequired:
                        label = "// CONNECT COMPANY MAILBOX TO QUEUE"
                    case .clientEmailRequired:
                        label = "// ADD CLIENT EMAIL TO QUEUE"
                    case .remindersDisabled:
                        label = "// PAYMENT REMINDERS DISABLED"
                    case .featureDisabled:
                        label = "// PAYMENT REMINDERS NOT ENABLED"
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    ToastCenter.shared.present(
                        Toast(label: label, tone: .warning, autoDismissAfter: 0)
                    )
                    resolution(false)
                }
            } catch {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    ToastCenter.shared.present(
                        Toast(
                            label: "// REMINDER QUEUE FAILED — SWIPE TO RETRY",
                            tone: .error,
                            autoDismissAfter: 0
                        )
                    )
                    resolution(false)
                }
            }
        }
    }

    private func executeWriteOff(
        _ project: Project,
        resolution: @escaping (Bool) -> Void
    ) {
        showWriteOffConfirmation = false
        let idempotencyKey = writeOffIdempotencyKeys[project.id]
            ?? UUID().uuidString.lowercased()
        writeOffIdempotencyKeys[project.id] = idempotencyKey
        Task {
            do {
                _ = try await repository.writeOffProject(
                    project.id,
                    idempotencyKey: idempotencyKey
                )
                await MainActor.run {
                    guard applyAuthoritativeClose(project) else {
                        pendingWriteOffProject = nil
                        pendingWriteOffResolution = nil
                        presentCloseReconciliationFailure()
                        resolution(false)
                        return
                    }
                    if let summary = financialsByProjectID[project.id] {
                        financialsByProjectID[project.id] = .empty(
                            currencyCode: summary.currencyCode
                        )
                    }
                    pendingWriteOffProject = nil
                    pendingWriteOffResolution = nil
                    writeOffIdempotencyKeys[project.id] = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(Feedback.Invoice.writtenOff)
                    NotificationCenter.default.post(
                        name: Notification.Name("WizardProjectSwipedDown"),
                        object: nil
                    )
                    resolution(true)
                }
            } catch {
                await MainActor.run {
                    pendingWriteOffProject = nil
                    pendingWriteOffResolution = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    ToastCenter.shared.present(
                        Toast(
                            label: "// WRITE-OFF FAILED — SWIPE TO RETRY",
                            tone: .error,
                            autoDismissAfter: 0
                        )
                    )
                    resolution(false)
                }
            }
        }
    }

    private func cancelWriteOff() {
        pendingWriteOffResolution?(false)
        pendingWriteOffProject = nil
        pendingWriteOffResolution = nil
        showWriteOffConfirmation = false
    }

    @MainActor
    private func applyAuthoritativeClose(_ project: Project) -> Bool {
        guard dataController.syncEngine?.supersedeProjectStatus(
            entityID: project.id,
            with: Status.closed.rawValue
        ) == true else {
            return false
        }
        project.status = .closed
        project.updatedAt = Date()
        project.needsSync = false
        do {
            try modelContext.save()
        } catch {
            print("[PAYMENT_REVIEW] Server close committed; local save awaits realtime: \(error)")
        }
        dataController.notifyReviewSourcesChanged()
        return true
    }

    private func presentCloseReconciliationFailure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        ToastCenter.shared.present(
            Toast(
                label: "// SERVER UPDATED — LOCAL SYNC NEEDS RETRY",
                tone: .error,
                autoDismissAfter: 0
            )
        )
    }

    private func finishReview(_ project: Project) {
        guard session.markReviewed(projectID: project.id) else { return }
        wizardStateManager?.evaluateStepPrerequisites(
            paymentReviewCardCount: session.remainingCount,
            hasOverdueProjects: !overdueProjectIDs.isEmpty
        )
        if session.isComplete {
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.page) {
                showAllCaughtUp = true
            }
        }
    }

    private func projectAccessIDs(_ project: Project) -> [String] {
        project.getTeamMemberIds() + project.tasks.flatMap { $0.getTeamMemberIds() }
    }

    private func allowedDirections(_ project: Project) -> Set<SwipeDirection> {
        accessPolicy.allowedDirections(
            projectTeamMemberIDs: projectAccessIDs(project),
            financials: financialsByProjectID[project.id]
        )
    }

    private func presentFinancialLoadFailure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        financialLoadFailed = true
        isPreparing = false
    }
}
