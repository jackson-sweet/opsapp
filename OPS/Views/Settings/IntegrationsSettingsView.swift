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

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Integrations",
                    onBackTapped: { dismiss() }
                )

                ScrollView {
                    VStack(spacing: 24) {
                        // Accounting header
                        Text("ACCOUNTING")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

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
                            Image(systemName: OPSStyle.Icons.info)
                                .font(.system(size: 16))
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
        .navigationBarHidden(true)
        .sheet(isPresented: $showQuickBooksAuth) {
            oauthPlaceholder(provider: "QuickBooks Online")
        }
        .sheet(isPresented: $showSageAuth) {
            oauthPlaceholder(provider: "Sage")
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
                    .font(.system(size: 24))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 40, height: 40)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
                    .cornerRadius(10)

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
                        Image(systemName: OPSStyle.Icons.complete)
                            .font(.system(size: 14))
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
                            .stroke(isConnected ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryAccent, lineWidth: 1)
                    )
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - OAuth Placeholder

    private func oauthPlaceholder(provider: String) -> some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "link.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

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
