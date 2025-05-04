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
    @State private var homeAddress: String = ""
    @State private var isEditing = false
    @State private var showSaveConfirmation = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var refreshID = UUID()
    
    var body: some View {
        // Force view to refresh when refreshID changes
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
                        // Profile avatar - will load from profileImageURL when available
                        if let user = dataController.currentUser, let profileURL = user.profileImageURL, 
                           !profileURL.isEmpty, let cachedImage = ImageCache.shared.get(forKey: profileURL) {
                            // Show the cached image if available
                            Image(uiImage: cachedImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 0)
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
                            
                            // Removed button to change profile photo
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
                        
                        formField(title: "Home Address", text: $homeAddress, isEditable: isEditing)
                        
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
        // Image picker removed
        .alert("Save Changes", isPresented: $showSaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                performSave()
            }
        } message: {
            Text("Save your profile changes?")
        }
        .alert("Error", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
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
        // Create a new UUID to force refresh profile image
        self.refreshID = UUID()
        
        if let user = dataController.currentUser {
            // Load first and last name directly from user model
            firstName = user.firstName
            lastName = user.lastName
            
            email = user.email ?? ""
            phone = user.phone ?? ""
            homeAddress = user.homeAddress ?? ""
            
            // Profile images are now only loaded from server, not from local data
            
            // Load profile image if available from URL
            if let profileImageURL = user.profileImageURL {
                // Load image asynchronously
                Task {
                    print("ProfileSettingsView: Attempting to load image from URL: \(profileImageURL)")
                    
                    // First check if it's already in the image cache
                    if let _ = ImageCache.shared.get(forKey: profileImageURL) {
                        print("ProfileSettingsView: Image already in cache")
                        // Force refresh UI
                        self.refreshID = UUID()
                        return
                    }
                    
                    // Otherwise load from URL
                    if let image = await loadImage(from: profileImageURL) {
                        print("ProfileSettingsView: Successfully loaded image from URL")
                        // The image is now cached, just force refresh UI
                        self.refreshID = UUID()
                    } else {
                        print("ProfileSettingsView: Failed to load image from URL")
                    }
                }
            } else {
                print("ProfileSettingsView: No profile image URL available")
            }
        }
    }
    
    private func loadImage(from urlString: String) async -> UIImage? {
        // Check if it's a local URL
        if urlString.starts(with: "local://") {
            if let imageBase64 = UserDefaults.standard.string(forKey: urlString),
               let imageData = Data(base64Encoded: imageBase64),
               let image = UIImage(data: imageData) {
                // Cache the loaded image
                ImageCache.shared.set(image, forKey: urlString)
                return image
            }
            return nil
        }
        
        // Handle remote URL
        var imageURL = urlString
        
        // Fix for URLs starting with //
        if imageURL.starts(with: "//") {
            imageURL = "https:" + imageURL
        }
        
        guard let url = URL(string: imageURL) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                // Cache the loaded image
                ImageCache.shared.set(image, forKey: urlString)
                return image
            }
        } catch {
            print("Failed to load image: \(error.localizedDescription)")
        }
        
        return nil
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
            // Print debug info about the profile update
            print("ProfileSettingsView: Saving profile information")
            
            do {
                // First update basic profile information
                let success = await dataController.updateUserProfile(
                    firstName: firstName,
                    lastName: lastName,
                    email: email, // Email won't actually change as the field is not editable
                    phone: phone,
                    homeAddress: homeAddress
                )
                
                // Update UI based on result
                await MainActor.run {
                    if success {
                        isEditing = false
                        print("ProfileSettingsView: Successfully saved profile changes")
                    } else {
                        // Show error alert
                        saveErrorMessage = "Failed to save profile changes. Please try again."
                        showSaveError = true
                        print("ProfileSettingsView: Failed to save profile changes")
                    }
                }
            } catch {
                // Handle any errors
                await MainActor.run {
                    saveErrorMessage = "Error: \(error.localizedDescription)"
                    showSaveError = true
                    print("ProfileSettingsView: Error saving profile: \(error.localizedDescription)")
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
