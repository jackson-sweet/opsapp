//
//  AppSetupScreen.swift
//  OPS
//
//  Full-screen loading screen shown while the app is being set up.
//  Used at end of onboarding (after all steps complete) and during login
//  when syncing user data. Performs real data sync (permissions + full
//  entity sync) before allowing the user into the main app.
//

import SwiftUI

struct AppSetupScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    // Visual fade-in state
    @State private var messageOpacity: Double = 0
    @State private var logoOpacity: Double = 0
    @State private var loadingOpacity: Double = 0

    // Sync state
    @State private var syncPhase: String = "SETTING UP YOUR WORKSPACE"
    @State private var syncFailed = false
    @State private var failureCount = 0

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // OPS Logo
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .opacity(logoOpacity)

                Spacer()
                    .frame(height: 48)

                if syncFailed {
                    // Error state
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        Text("SYNC FAILED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .tracking(2)

                        Button {
                            syncFailed = false
                            performRealSync()
                        } label: {
                            Text("TAP TO RETRY")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, OPSStyle.Layout.spacing3)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .padding(.horizontal, 48)

                        if failureCount >= 3 {
                            Button {
                                manager.completeOnboarding()
                            } label: {
                                Text("CONTINUE ANYWAY")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .underline()
                            }
                        }
                    }
                    .opacity(loadingOpacity)
                } else {
                    // Sweep progress bar — thin line with a glowing accent segment
                    SyncSweepBar()
                        .opacity(loadingOpacity)

                    Spacer()
                        .frame(height: 24)

                    // Current sync phase message
                    Text(syncPhase)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .tracking(2)
                        .opacity(messageOpacity)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.4), value: syncPhase)
                        .id("setup-message-\(syncPhase)")
                }

                Spacer()
            }
        }
        .onAppear {
            startFadeInSequence()
            performRealSync()
        }
    }

    // MARK: - Visual Fade-In

    private func startFadeInSequence() {
        withAnimation(.easeIn(duration: 0.6)) {
            logoOpacity = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.4)) {
                loadingOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.4)) {
                messageOpacity = 1.0
            }
        }
    }

    // MARK: - Real Sync

    private func performRealSync() {
        Task {
            do {
                // Phase 1: Permissions
                syncPhase = "LOADING YOUR PERMISSIONS"
                let userId = UserDefaults.standard.string(forKey: "currentUserId") ?? ""
                await PermissionStore.shared.fetchPermissions(userId: userId)

                // Phase 2: Full sync with per-entity progress
                guard let engine = dataController.syncEngine else {
                    throw NSError(domain: "SyncGate", code: 1, userInfo: [NSLocalizedDescriptionKey: "SyncEngine not initialized"])
                }

                syncPhase = "SYNCING YOUR DATA"

                // Start fullSync and poll statusText for entity-specific messages
                let syncTask = Task {
                    await engine.fullSync()
                }

                // Poll engine.statusText and map to friendly messages
                while !syncTask.isCancelled {
                    let status = engine.statusText
                    let friendlyPhase = mapEntityToPhase(status)
                    if friendlyPhase != syncPhase {
                        syncPhase = friendlyPhase
                    }
                    if status.contains("complete") || status.contains("error") {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }

                await syncTask.value

                syncPhase = "ALMOST READY"
                try? await Task.sleep(nanoseconds: 500_000_000)

                manager.completeOnboarding()

            } catch {
                failureCount += 1
                syncFailed = true
                syncPhase = "SYNC FAILED"
                print("[SYNC_GATE] Sync failed (attempt \(failureCount)): \(error)")
            }
        }
    }

    /// Maps SyncEngine statusText to human-friendly phase messages.
    private func mapEntityToPhase(_ statusText: String) -> String {
        let lower = statusText.lowercased()
        if lower.contains("project") && !lower.contains("note") { return "SYNCING YOUR PROJECTS" }
        if lower.contains("projecttask") || lower.contains("task") { return "SYNCING YOUR SCHEDULE" }
        if lower.contains("user") { return "SYNCING YOUR TEAM" }
        if lower.contains("client") { return "SYNCING YOUR CLIENTS" }
        if lower.contains("company") { return "SYNCING YOUR COMPANY" }
        if lower.contains("tasktype") { return "SYNCING TASK TYPES" }
        if lower.contains("note") { return "SYNCING PROJECT NOTES" }
        if lower.contains("annotation") || lower.contains("photo") { return "SYNCING PHOTOS" }
        if lower.contains("linking") { return "LINKING YOUR DATA" }
        if lower.contains("complete") { return "ALMOST READY" }
        if lower.contains("pushing") { return "PUSHING LOCAL CHANGES" }
        if lower.contains("error") { return "SYNC ERROR" }
        return syncPhase // Keep current phase if no match
    }
}

// MARK: - Sync Sweep Bar

/// A thin horizontal bar with a glowing accent segment that sweeps left-to-right.
/// Conforms to the interface-design system: monochromatic base, accent used sparingly,
/// ultra-thin lines, smooth easing.
private struct SyncSweepBar: View {
    @State private var sweepPhase: CGFloat = 0

    private let trackWidth: CGFloat = 120
    private let trackHeight: CGFloat = 2

    var body: some View {
        ZStack(alignment: .leading) {
            // Base track — ultra-thin, barely visible
            RoundedRectangle(cornerRadius: 1)
                .fill(OPSStyle.Colors.surfaceActive)
                .frame(width: trackWidth, height: trackHeight)

            // Sweep segment — accent color
            RoundedRectangle(cornerRadius: 1)
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: trackWidth * 0.3, height: trackHeight)
                .offset(x: sweepPhase * trackWidth * 0.7)
        }
        .frame(width: trackWidth, height: trackHeight)
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.4)
                .repeatForever(autoreverses: true)
            ) {
                sweepPhase = 1.0
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)

    return AppSetupScreen(manager: manager)
        .environmentObject(dataController)
}
