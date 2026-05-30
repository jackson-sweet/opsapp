//
//  IntegrationsSettingsView.swift
//  OPS
//
//  Accounting integrations — QuickBooks and Sage connection management.
//

import SwiftUI

struct IntegrationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showQuickBooksAuth = false
    @State private var showSageAuth = false
    @StateObject private var mirrorService = CalendarMirrorService.shared
    @State private var showingMirrorDisconnectConfirm = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Integrations",
                    onBackTapped: { dismiss() }
                )

                ScrollView {
                    VStack(spacing: 24) {
                        // Calendar header (Bug 68123654)
                        Text("CALENDAR")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // iPhone Calendar mirror
                        integrationCard(
                            name: "iPhone Calendar",
                            description: "Sync OPS events to your iPhone Calendar — time off, personal events, and your assigned work.",
                            iconName: "calendar",
                            isConnected: mirrorService.isEnabled && mirrorService.authorizationStatus == .fullAccess,
                            onConnect: { handleMirrorToggle() }
                        )

                        // Accounting header
                        Text("ACCOUNTING")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        // QuickBooks
                        integrationCard(
                            name: "QuickBooks Online",
                            description: "Sync invoices and payments with QuickBooks",
                            iconName: "building.columns.fill",
                            isConnected: false,
                            onConnect: { showQuickBooksAuth = true }
                        )

                        // Sage
                        integrationCard(
                            name: "Sage",
                            description: "Sync invoices and payments with Sage",
                            iconName: "leaf.fill",
                            isConnected: false,
                            onConnect: { showSageAuth = true }
                        )

                        // Info note
                        HStack(alignment: .top, spacing: 12) {
                            Image(OPSStyle.Icons.info)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("Connecting an accounting platform will automatically sync your invoices and payments. You can disconnect at any time.")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .trackScreen("Settings.Integrations")
        .navigationBarHidden(true)
        .sheet(isPresented: $showQuickBooksAuth) {
            oauthPlaceholder(provider: "QuickBooks Online")
        }
        .sheet(isPresented: $showSageAuth) {
            oauthPlaceholder(provider: "Sage")
        }
        .alert("// DISCONNECT iPHONE CALENDAR", isPresented: $showingMirrorDisconnectConfirm) {
            Button("CANCEL", role: .cancel) { }
            Button("DISCONNECT", role: .destructive) {
                Task { await mirrorService.disable() }
            }
        } message: {
            Text("Existing mirrored events will be removed from your iPhone Calendar.")
        }
    }

    private func handleMirrorToggle() {
        if mirrorService.isEnabled {
            showingMirrorDisconnectConfirm = true
        } else {
            Task { try? await mirrorService.enable() }
        }
    }

    // MARK: - Integration Card

    private func integrationCard(
        name: String,
        description: String,
        iconName: String,
        isConnected: Bool,
        onConnect: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if isConnected {
                    HStack(spacing: 4) {
                        Image(OPSStyle.Icons.complete)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("CONNECTED")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.successStatus)
                }
            }

            Button(action: onConnect) {
                Text(isConnected ? "DISCONNECT" : "CONNECT")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(isConnected ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(isConnected ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - OAuth Placeholder

    private func oauthPlaceholder(provider: String) -> some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image("ops.link")
                    .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text("\(provider.uppercased()) OAUTH")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("OAuth authentication will open here when the \(provider) integration is configured on your Supabase backend.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                Button("DISMISS") {
                    showQuickBooksAuth = false
                    showSageAuth = false
                }
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.bottom, 40)
            }
        }
    }
}
