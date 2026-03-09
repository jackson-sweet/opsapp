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

            VStack(spacing: 0) {
                header
                    .padding(.top, 8)

                if overdueProjects.isEmpty || showAllCaughtUp {
                    allCaughtUpView
                } else {
                    directionHints
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    ProjectReviewCardStack(
                        projects: overdueProjects,
                        hasFinancialAccess: hasFinancialAccess,
                        onSwipe: handleSwipe,
                        onTapCard: { project in
                            selectedProject = project
                            showBio = true
                        }
                    )

                    Spacer()

                    // Counter
                    Text("\(reviewedCount) OF \(overdueProjects.count) REVIEWED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.bottom, 24)
                }
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
                Text("PAYMENT REVIEW")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("\(overdueProjects.count) OVERDUE")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
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
        .clipShape(Capsule())
    }

    // MARK: - All Caught Up

    private var allCaughtUpView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(OPSStyle.Colors.successStatus)
                .scaleEffect(celebrationScale)

            Text("ALL CAUGHT UP")
                .font(.custom("Mohave-Bold", size: 28))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .opacity(celebrationOpacity)

            Text("No projects need payment review")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .opacity(celebrationOpacity)

            Spacer()

            Button(action: { dismiss() }) {
                Text("DONE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .opacity(celebrationOpacity)
        }
        .onAppear {
            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Checkmark scales in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                celebrationScale = 1.0
            }
            // Text and button fade in after delay
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
        case .left:
            break // Skip -- no data changes
        case .up:
            executeSendReminder(project)
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
        reviewedCount += 1
        checkCompletion()
    }

    private func checkCompletion() {
        if reviewedCount >= overdueProjects.count {
            withAnimation(.spring().delay(0.3)) {
                showAllCaughtUp = true
            }
        }
    }
}
