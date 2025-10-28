//
//  SyncStatusIndicator.swift
//  OPS
//
//  Displays sync status and alerts user about pending syncs
//

import SwiftUI

/// Compact indicator showing pending sync status
struct SyncStatusIndicator: View {
    @EnvironmentObject private var dataController: DataController

    var body: some View {
        if dataController.hasPendingSyncs && !dataController.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.warningStatus)

                Text("\(dataController.pendingSyncCount) pending")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(OPSStyle.Colors.warningStatus.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
            )
        } else if dataController.isSyncing {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    .scaleEffect(0.7)

                Text("Syncing...")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))
            )
        }
    }
}

/// Banner that shows when connection is restored with pending syncs
struct SyncRestoredAlert: View {
    @EnvironmentObject private var dataController: DataController
    @Binding var isPresented: Bool

    @State private var autoDismissTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            if isPresented {
                // Banner content
                HStack(spacing: 12) {
                    // Status icon with indicator
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "wifi")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.successStatus)
                            .frame(width: 32, height: 32)

                        // Pulse indicator
                        Circle()
                            .fill(OPSStyle.Colors.successStatus)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(OPSStyle.Colors.successStatus.opacity(0.3), lineWidth: 2)
                                    .scaleEffect(1.5)
                                    .opacity(0)
                                    .animation(
                                        .easeOut(duration: 1.0)
                                        .repeatForever(autoreverses: false),
                                        value: isPresented
                                    )
                            )
                    }

                    // Text content
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONNECTION RESTORED")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        HStack(spacing: 6) {
                            Text("\(dataController.pendingSyncCount) item\(dataController.pendingSyncCount == 1 ? "" : "s") syncing")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            // Syncing indicator
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                .scaleEffect(0.6)
                        }
                    }

                    Spacer()

                    // Dismiss button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                        autoDismissTimer?.invalidate()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.05))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Rectangle()
                        .fill(OPSStyle.Colors.background)
                        .overlay(
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            OPSStyle.Colors.successStatus.opacity(0.1),
                                            Color.clear
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                )
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.white.opacity(0.1)),
                    alignment: .bottom
                )
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    // Auto-dismiss after 4 seconds
                    autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }
                }
                .onDisappear {
                    autoDismissTimer?.invalidate()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isPresented)
    }
}

#Preview {
    ZStack {
        OPSStyle.Colors.background

        VStack(spacing: 20) {
            SyncStatusIndicator()

            Button("Show Alert") {
                // Preview button
            }
        }
    }
    .environmentObject(DataController())
}
