//
//  ContactDetailSheet.swift
//  OPS
//
//  Created for displaying client and team member contact details
//

import SwiftUI

struct ContactDetailSheet: View {
    let name: String
    let role: String
    let email: String?
    let phone: String?
    let isClient: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingCallConfirmation = false
    @State private var showingMessageOptions = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .fill(OPSStyle.Colors.secondaryText.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, OPSStyle.Layout.spacing2)
                .padding(.bottom, OPSStyle.Layout.spacing3_5)
            
            // Profile section
            VStack(spacing: OPSStyle.Layout.spacing3) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isClient ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: isClient ? "building.2" : "person.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                // Name and role
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(name)
                        .font(OPSStyle.Typography.pageTitle)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text)
                    
                    Text(role)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            // Contact actions
            VStack(spacing: OPSStyle.Layout.spacing3) {
                if let phone = phone {
                    ContactActionRow(
                        icon: "phone.fill",
                        title: "Call",
                        subtitle: phone,
                        action: {
                            showingCallConfirmation = true
                        }
                    )
                }
                
                if let phone = phone {
                    ContactActionRow(
                        icon: "message.fill",
                        title: "Message",
                        subtitle: phone,
                        action: {
                            showingMessageOptions = true
                        }
                    )
                }
                
                if let email = email {
                    ContactActionRow(
                        icon: "envelope.fill",
                        title: "Email",
                        subtitle: email,
                        action: {
                            openEmail(email)
                        }
                    )
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            
            Spacer()
            
            // Note for V2
            if !isClient {
                Text("Projects with \(name.components(separatedBy: " ").first ?? "this member") coming in v2")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.bottom, 40)
            } else {
                Text("Client project history coming in v2")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .glassDense()
        .confirmationDialog("Call \(name)?", isPresented: $showingCallConfirmation) {
            if let phone = phone {
                Button("Call") {
                    callNumber(phone)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Message \(name)", isPresented: $showingMessageOptions) {
            if let phone = phone {
                Button("Send SMS") {
                    sendSMS(to: phone)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    private func callNumber(_ number: String) {
        let cleanedNumber = number.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "tel://\(cleanedNumber)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func sendSMS(to number: String) {
        let cleanedNumber = number.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if let url = URL(string: "sms:\(cleanedNumber)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openEmail(_ email: String) {
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }
}

struct ContactActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.background)
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(subtitle)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.background.opacity(0.5))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}
