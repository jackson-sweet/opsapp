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
            RoundedRectangle(cornerRadius: 2.5)
                .fill(OPSStyle.Colors.secondaryText.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)
            
            // Profile section
            VStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isClient ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryAccent)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: isClient ? "building.2" : "person.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
                
                // Name and role
                VStack(spacing: 4) {
                    Text(name)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(role)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            // Contact actions
            VStack(spacing: 16) {
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
            .padding(.horizontal, 20)
            
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
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(20, corners: [.topLeft, .topRight])
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
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
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
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.background.opacity(0.5))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}
