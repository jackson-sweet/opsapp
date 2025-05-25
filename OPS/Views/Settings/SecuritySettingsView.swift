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
    @State private var showPINSetup = false
    @State private var newPIN = ""
    
    private var pinManager: SimplePINManager {
        dataController.simplePINManager
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
                        // Security section
                        SettingsSectionHeader(title: "APP ACCESS")
                        
                        VStack(spacing: 16) {
                            
                            // PIN toggle
                            HStack {
                                VStack(alignment: .leading){
                                    Text("LOCK IT DOWN")
                                        .font(OPSStyle.Typography.cardTitle)
                                    Text("Require PIN on App Launch")
                                        .font(OPSStyle.Typography.cardBody)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { pinManager.hasPINEnabled },
                                    set: { enabled in
                                        if enabled {
                                            showPINSetup = true
                                        } else {
                                            pinManager.removePIN()
                                        }
                                    }
                                ))
                                .tint(OPSStyle.Colors.primaryAccent)
                            }
                            .padding(20)
                            .background(Color(OPSStyle.Colors.cardBackground))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            
                            if pinManager.hasPINEnabled {
                                Button(action: { showPINSetup = true }) {
                                    Text("CHANGE PIN")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showPINSetup) {
            PINSetupSheet(pinManager: pinManager, isPresented: $showPINSetup)
        }
    }
}

struct PINSetupSheet: View {
    let pinManager: SimplePINManager
    @Binding var isPresented: Bool
    @State private var enteredPIN = ""
    @State private var confirmedPIN = ""
    @State private var showConfirmation = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 24) {
                    if !showConfirmation {
                        // Enter new PIN
                        Text("ENTER NEW 4-DIGIT PIN")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        
                        SecureField("", text: $enteredPIN)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                            .onChange(of: enteredPIN) { _, newValue in
                                if newValue.count > 4 {
                                    enteredPIN = String(newValue.prefix(4))
                                }
                            }
                        
                        Button("NEXT") {
                            if enteredPIN.count == 4 {
                                showConfirmation = true
                                errorMessage = ""
                            } else {
                                errorMessage = "PIN must be 4 digits"
                            }
                        }
                        .buttonStyle(OPSButtonStyle.Primary())
                        .disabled(enteredPIN.count != 4)
                    } else {
                        // Confirm PIN
                        Text("CONFIRM PIN")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        
                        SecureField("", text: $confirmedPIN)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                            .onChange(of: confirmedPIN) { _, newValue in
                                if newValue.count > 4 {
                                    confirmedPIN = String(newValue.prefix(4))
                                }
                            }
                        
                        HStack(spacing: 16) {
                            Button("BACK") {
                                showConfirmation = false
                                confirmedPIN = ""
                                errorMessage = ""
                            }
                            .buttonStyle(OPSButtonStyle.Secondary())
                            
                            Button("SAVE") {
                                if confirmedPIN == enteredPIN {
                                    pinManager.setPIN(enteredPIN)
                                    isPresented = false
                                } else {
                                    errorMessage = "PINs don't match"
                                    confirmedPIN = ""
                                }
                            }
                            .buttonStyle(OPSButtonStyle.Primary())
                            .disabled(confirmedPIN.count != 4)
                        }
                    }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                }
                .padding()
            }
            .navigationBarItems(
                trailing: Button("Cancel") {
                    isPresented = false
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            )
        }
    }
}

#Preview {
    SecuritySettingsView()
        .preferredColorScheme(.dark)
        .environmentObject(DataController())
}
