//
//  PermissionChangeOverlay.swift
//  OPS
//
//  Full-screen blocking overlay displayed when a user's permission scope
//  contracts (e.g., "all" -> "assigned"). The user must acknowledge the
//  change and tap "Refresh App" to purge non-permitted data and re-sync.
//

import SwiftUI

struct PermissionChangeOverlay: View {
    @EnvironmentObject private var dataController: DataController
    @Binding var isPresented: Bool
    var onRefresh: () -> Void

    var body: some View {
        ZStack {
            // Full-screen dark background
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: OPSStyle.Layout.spacing4) {
                Spacer()

                // OPS logo
                Image("LogoWhite")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 48)
                    .padding(.bottom, OPSStyle.Layout.spacing3)

                // Title
                Text("YOUR PERMISSIONS HAVE BEEN UPDATED")
                    .font(OPSStyle.Typography.headingBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)

                // Body text
                Text("Your access level has changed. If you believe this is an error, contact your admin.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing5)

                // Admin contact card
                adminContactCard
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .padding(.top, OPSStyle.Layout.spacing2)

                Spacer()

                // Refresh button
                Button(action: {
                    onRefresh()
                }) {
                    Text("REFRESH APP")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing4)
                .padding(.bottom, OPSStyle.Layout.spacing5)
            }
        }
    }

    // MARK: - Admin Contact Card

    @ViewBuilder
    private var adminContactCard: some View {
        if let company = dataController.getCurrentUserCompany(),
           let adminId = company.getAdminIds().first,
           let admin = dataController.getUser(id: adminId) {

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("\(admin.firstName) \(admin.lastName)")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("ADMINISTRATOR")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                // Contact buttons row
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    if let email = admin.email, !email.isEmpty {
                        Button(action: {
                            if let url = URL(string: "mailto:\(email)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                Text("EMAIL")
                                    .font(OPSStyle.Typography.captionBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .nestedCard()
                        }
                    }

                    if let phone = admin.phone, !phone.isEmpty {
                        Button(action: {
                            if let url = URL(string: "tel://\(phone)") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                Text("CALL")
                                    .font(OPSStyle.Typography.captionBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .nestedCard()
                        }
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing1)
            }
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface()
        }
    }
}
