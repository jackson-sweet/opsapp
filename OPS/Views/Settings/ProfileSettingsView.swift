//
//  ProfileSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI
import UIKit

struct ProfileSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var showImagePicker = false
    @State private var profileImage: UIImage?
    @State private var isEditing = false
    @State private var showSaveConfirmation = false
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    // Header
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        
                        Text("Profile Settings")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Spacer()
                        
                        Button(action: {
                            toggleEditing()
                        }) {
                            Text(isEditing ? "Cancel" : "Edit")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding()
                    
                    // Profile image section
                    VStack {
                        if let profileImage = profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                                )
                        } else {
                            // Default profile circle with initial
                            Circle()
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Text(getInitials())
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(.white)
                                )
                        }
                        
                        if isEditing {
                            Button(action: {
                                showImagePicker = true
                            }) {
                                Text("Change Photo")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    
                    // Form fields
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // PERSONAL INFORMATION section
                        Text("PERSONAL INFORMATION")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal)
                        
                        formField(title: "First Name", text: $firstName, isEditable: isEditing)
                        formField(title: "Last Name", text: $lastName, isEditable: isEditing)
                        formField(title: "Email", text: $email, isEditable: isEditing)
                        formField(title: "Phone", text: $phone, isEditable: isEditing)
                        
                        // CREDENTIALS section
                        Text("CREDENTIALS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.top, OPSStyle.Layout.spacing3)
                            .padding(.horizontal)
                        
                        Button(action: {
                            // Reset password action
                        }) {
                            HStack {
                                Text("Reset Password")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .padding(.horizontal)
                        .disabled(!isEditing)
                        .opacity(isEditing ? 1.0 : 0.6)
                        
                        // Save button (visible only in edit mode)
                        if isEditing {
                            Button(action: {
                                saveChanges()
                            }) {
                                Text("Save Changes")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(OPSStyle.Colors.primaryAccent)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            .padding(.horizontal)
                            .padding(.top, OPSStyle.Layout.spacing4)
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadUserData()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $profileImage)
                .presentationDetents([.medium, .large])
        }
        .alert("Save Changes", isPresented: $showSaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                performSave()
            }
        } message: {
            Text("Save your profile changes?")
        }
    }
    
    private func formField(title: String, text: Binding<String>, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            if isEditable {
                TextField("", text: text)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding()
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            } else {
                Text(text.wrappedValue.isEmpty ? "Not set" : text.wrappedValue)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(text.wrappedValue.isEmpty ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.primaryText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(.horizontal)
    }
    
    private func getInitials() -> String {
        if let firstInitial = firstName.first, let lastInitial = lastName.first {
            return "\(firstInitial)\(lastInitial)".uppercased()
        } else if let firstInitial = firstName.first {
            return String(firstInitial).uppercased()
        } else if let lastInitial = lastName.first {
            return String(lastInitial).uppercased()
        }
        return "U"
    }
    
    private func loadUserData() {
        if let user = dataController.currentUser {
            // Split name into first and last
            let nameParts = user.fullName.split(separator: " ")
            if nameParts.count > 0 {
                firstName = String(nameParts[0])
            }
            if nameParts.count > 1 {
                lastName = nameParts[1...].joined(separator: " ")
            }
            
            email = user.email ?? ""
            phone = user.phone ?? ""
            
            // Load profile image if available
            // This would need to be implemented based on your data model
        }
    }
    
    private func toggleEditing() {
        if isEditing {
            // Cancel editing - restore original values
            loadUserData()
        }
        isEditing.toggle()
    }
    
    private func saveChanges() {
        showSaveConfirmation = true
    }
    
    private func performSave() {
        Task {
            let success = await dataController.updateUserProfile(
                firstName: firstName,
                lastName: lastName,
                email: email,
                phone: phone
            )
            
            await MainActor.run {
                if success {
                    isEditing = false
                }
            }
        }
    }
}

#Preview {
    ProfileSettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
