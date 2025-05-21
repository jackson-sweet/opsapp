//
//  SecuritySettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI

struct SecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    // Security preferences
    @AppStorage("securityLevel") private var securityLevel = SecurityLevel.noBarriers
    @AppStorage("pinCode") private var pinCode = ""
    @State private var newPinCode = ""
    @State private var confirmPinCode = ""
    @State private var showPinSetup = false
    @State private var pinError = ""
    
    // Security levels
    enum SecurityLevel: String, CaseIterable {
        case noBarriers = "No barriers"
        case askForPin = "Ask for my PIN"
        case lockItDown = "Lock it down"
        
        var description: String {
            switch self {
            case .noBarriers:
                return "On this device, people can access the app without verification steps."
            case .askForPin:
                return "We'll ask for your PIN before you sign in or change settings."
            case .lockItDown:
                return "You'll need to authorize all actions using your PIN."
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Security",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Security Levels
                        SettingsSectionHeader(title: "SIGN-IN & SECURITY PREFERENCES")
                        
                        VStack(spacing: 16) {
                            ForEach(SecurityLevel.allCases, id: \.self) { level in
                                SecurityPINOption(
                                    title: level.rawValue,
                                    description: level.description,
                                    isSelected: securityLevel == level,
                                    action: {
                                        if level != .noBarriers && pinCode.isEmpty {
                                            // Need to set a PIN first
                                            showPinSetup = true
                                            securityLevel = level
                                        } else {
                                            securityLevel = level
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // PIN setup/change button
                        if securityLevel != .noBarriers {
                            SettingsButton(
                                title: pinCode.isEmpty ? "Set PIN" : "Change PIN",
                                icon: "lock",
                                style: .secondary,
                                action: {
                                    showPinSetup = true
                                }
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Reset security settings
                        SettingsButton(
                            title: "Reset Security Settings",
                            icon: "arrow.clockwise",
                            style: .secondary,
                            action: {
                                resetSecuritySettings()
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 32)
                    }
                    .padding(.vertical, 24)
                }
            }
            
            // PIN setup sheet
            if showPinSetup {
                OPSStyle.Colors.cardBackgroundDark
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        // Dismiss if tapped outside
                        showPinSetup = false
                    }
                
                VStack(spacing: 20) {
                    // Title
                    Text(pinCode.isEmpty ? "Set PIN" : "Change PIN")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    // PIN fields
                    VStack(spacing: 16) {
                        SettingsField(
                            title: "New PIN",
                            placeholder: "Enter a 4-digit PIN",
                            text: $newPinCode,
                            isSecure: true
                        )
                        
                        SettingsField(
                            title: "Confirm PIN",
                            placeholder: "Confirm your PIN",
                            text: $confirmPinCode,
                            isSecure: true
                        )
                    }
                    .padding(.horizontal, 16)
                    
                    // Error text
                    if !pinError.isEmpty {
                        Text(pinError)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .padding(.horizontal, 16)
                    }
                    
                    // Actions
                    HStack(spacing: 16) {
                        Button(action: {
                            showPinSetup = false
                            newPinCode = ""
                            confirmPinCode = ""
                            pinError = ""
                            
                            // If this was first-time PIN setup and it was cancelled,
                            // revert to no barriers
                            if pinCode.isEmpty {
                                securityLevel = .noBarriers
                            }
                        }) {
                            Text("Cancel")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(12)
                        }
                        
                        Button(action: {
                            validateAndSavePIN()
                        }) {
                            Text("Save")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                )
                .frame(width: 320)
                .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
                .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private func validateAndSavePIN() {
        // Validate the PIN
        if newPinCode.isEmpty || confirmPinCode.isEmpty {
            pinError = "Please enter a PIN"
            return
        }
        
        if newPinCode.count < 4 {
            pinError = "PIN must be at least 4 digits"
            return
        }
        
        if newPinCode != confirmPinCode {
            pinError = "PINs do not match"
            return
        }
        
        // Save the PIN
        pinCode = newPinCode
        
        // Close the sheet
        showPinSetup = false
        newPinCode = ""
        confirmPinCode = ""
        pinError = ""
    }
    
    private func resetSecuritySettings() {
        securityLevel = .noBarriers
        pinCode = ""
    }
}

#Preview {
    SecuritySettingsView()
        .preferredColorScheme(.dark)
        .environmentObject(DataController())
}