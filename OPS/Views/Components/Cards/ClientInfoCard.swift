//
//  ClientInfoCard.swift
//  OPS
//
//  Reusable client information display card - built on SectionCard base
//

import SwiftUI

struct ClientInfoCard: View {
    let clientName: String
    let clientEmail: String?
    let clientPhone: String?

    var body: some View {
        SectionCard(
            icon: OPSStyle.Icons.client,
            title: "Client"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Client name
                Text(clientName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                // Contact info
                VStack(alignment: .leading, spacing: 8) {
                    // Email
                    if let email = clientEmail, !email.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: OPSStyle.Icons.envelope)
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Text(email)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .onTapGesture {
                                    if let url = URL(string: "mailto:\(email)") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                        }
                    }

                    // Phone
                    if let phone = clientPhone, !phone.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: OPSStyle.Icons.phone)
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Text(phone)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .onTapGesture {
                                    if let url = URL(string: "tel:\(phone)") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                        }
                    }
                }

                // No contact info message
                if (clientEmail == nil || clientEmail!.isEmpty) &&
                   (clientPhone == nil || clientPhone!.isEmpty) {
                    Text("No contact information available")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
    }
}
