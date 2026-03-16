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
                    VStack(spacing: 16) {
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
                                .padding(.vertical, 16)
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
                    // Normal loading state
                    TacticalLoadingBarAnimated(
                        barCount: 8,
                        barWidth: 3,
                        barHeight: 8,
                        spacing: 5,
                        emptyColor: OPSStyle.Colors.inputFieldBorder,
                        fillColor: OPSStyle.Colors.primaryAccent
                    )
                    .opacity(loadingOpacity)

                    Spacer()
                        .frame(height: 24)

                    // Current sync phase message
                    Text(syncPhase)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .tracking(2)
                        .opacity(messageOpacity)
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
        // Phase 1: Fade in logo
        withAnimation(.easeIn(duration: 0.6)) {
            logoOpacity = 1.0
        }

        // Phase 2: Fade in loading bar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeIn(duration: 0.4)) {
                loadingOpacity = 1.0
            }
        }

        // Phase 3: Show first message
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

                // Phase 2: Full sync
                syncPhase = "SYNCING YOUR DATA"
                guard let engine = dataController.syncEngine else {
                    throw NSError(domain: "SyncGate", code: 1, userInfo: [NSLocalizedDescriptionKey: "SyncEngine not initialized"])
                }

                syncPhase = "SYNCING YOUR PROJECTS"
                await engine.fullSync()

                syncPhase = "ALMOST READY"
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Success
                manager.completeOnboarding()

            } catch {
                failureCount += 1
                syncFailed = true
                syncPhase = "SYNC FAILED"
                print("[SYNC_GATE] Sync failed (attempt \(failureCount)): \(error)")
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
