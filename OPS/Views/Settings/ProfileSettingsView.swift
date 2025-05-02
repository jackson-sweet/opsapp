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
            // Background gradient
            OPSStyle.Colors.backgroundGradient
            .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header area with back button and title
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(12)
                        
                        Spacer()
                        
                        Text("Profile Settings")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: {
                            toggleEditing()
                        }) {
                            Text(isEditing ? "Cancel" : "Edit")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .frame(width: 80, height: 44)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    // Profile image section
                    HStack(spacing: 24) {
                        if let profileImage = profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: isEditing ? 2 : 0)
                                )
                        } else {
                            // Default profile circle with initial
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 80, height: 80)
                                
                                Text(getInitials())
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(firstName) \(lastName)")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            
                            if let user = dataController.currentUser {
                                Text(user.role.displayName)
                                    .font(.system(size: 16))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            
                            if isEditing {
                                Button(action: {
                                    showImagePicker = true
                                }) {
                                    Text("Change Photo")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    // Form fields
                    VStack(spacing: 24) {
                        // PERSONAL INFORMATION section
                        sectionHeader("PERSONAL INFORMATION")
                        
                        formField(title: "First Name", text: $firstName, isEditable: isEditing)
                        formField(title: "Last Name", text: $lastName, isEditable: isEditing)
                        
                        // Email - not editable
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            // Email is always shown as non-editable
                            HStack {
                                Text(email.isEmpty ? "Not set" : email)
                                    .font(.system(size: 16))
                                    .foregroundColor(email.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                                
                                Spacer()
                                
                                // Lock icon to indicate non-editable
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        
                        formField(title: "Phone Number", text: $phone, isEditable: isEditing)
                        
                        // CREDENTIALS section
                        sectionHeader("CREDENTIALS")
                        
                        Button(action: {
                            // Reset password action
                        }) {
                            HStack {
                                Text("Reset Password")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .disabled(!isEditing)
                        .opacity(isEditing ? 1.0 : 0.6)
                        
                        // Save button (visible only in edit mode)
                        if isEditing {
                            Button(action: {
                                saveChanges()
                            }) {
                                Text("Save Changes")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(OPSStyle.Colors.primaryAccent)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadUserData()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(
                images: Binding<[UIImage]>(
                    get: { profileImage != nil ? [profileImage!] : [] },
                    set: { images in
                        if let first = images.first {
                            profileImage = first
                        }
                    }
                ), 
                selectionLimit: 1,
                onSelectionComplete: {
                    // Automatically dismiss sheet when selection is complete
                    DispatchQueue.main.async {
                        showImagePicker = false
                    }
                }
            )
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
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 20)
            .padding(.top, 8)
    }
    
    private func formField(title: String, text: Binding<String>, isEditable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            if isEditable {
                TextField("", text: text)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                    )
            } else {
                Text(text.wrappedValue.isEmpty ? "Not set" : text.wrappedValue)
                    .font(.system(size: 16))
                    .foregroundColor(text.wrappedValue.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 20)
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
                email: email, // Email won't actually change as the field is not editable
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
