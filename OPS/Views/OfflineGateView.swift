//
//  OfflineGateView.swift
//  OPS
//
//  Full-screen view shown when the user has no connectivity AND is not
//  authenticated. Makes clear that OPS works offline for everything
//  EXCEPT first-time account setup.
//

import SwiftUI

struct OfflineGateView: View {
    @EnvironmentObject var dataController: DataController
    let cachedUserName: String?
    let onCachedLogin: (() -> Void)?

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            // Starburst behind content — centered, fills available space
            StarburstView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.6)

            VStack(spacing: 0) {
                Spacer()

                // OPS Logo
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 40)

                // Messaging card
                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Text("NO CONNECTION")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                        .tracking(2)

                    Text("OPS works offline for everything except first-time account setup. Connect to Wi-Fi or cellular to get started.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(OPSStyle.Layout.spacing3_5)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.line, lineWidth: 1)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing4)

                Spacer().frame(height: 24)

                // Cached account login button (only if a previous account exists)
                if let name = cachedUserName, let onLogin = onCachedLogin {
                    Button(action: onLogin) {
                        Text("LOG IN AS \(name.uppercased())")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing3)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing4)

                    Spacer().frame(height: 16)
                }

                Text("Checking connection...")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Spacer()
            }
        }
    }
}
