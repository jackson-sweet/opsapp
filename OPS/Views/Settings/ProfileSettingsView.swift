//
//  ProfileSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI
import UIKit

// Use standardized components directly (internal modules don't need import)

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
    // Password reset states
    @State private var showResetPasswordSheet = false
    @State private var resetEmail = ""
    @State private var passwordResetInProgress = false
    @State private var passwordResetError: String? = nil
    @State private var passwordResetSuccess = false
    // Private state ID to force view refresh when needed
    @State private var refreshID = UUID()
    
    var body: some View {
        // View content, refreshes when necessary based on state changes
        ZStack {
            // Background gradient
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header area with back button and title - fixed, not part of scroll view
                SettingsHeader(
                    title: "Profile Settings",
                    showEditButton: true,
                    isEditing: isEditing,
                    onBackTapped: {
                        dismiss()
                    },
                    onEditTapped: {
                        toggleEditing()
                    }
                )
                .padding(.bottom, 8)
                
                // Scrollable content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // Profile card - implemented directly to avoid ambiguity
                        if let user = dataController.currentUser {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top, spacing: 16) {
                                    // User avatar
                                    ZStack {
                                        if let profileURL = user.profileImageURL, 
                                            !profileURL.isEmpty,
                                           let cachedImage = ImageCache.shared.get(forKey: profileURL) {
                                            Image(uiImage: cachedImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 60, height: 60)
                                                .clipShape(Circle())
                                        } else {
                                            // Default profile circle with initial
                                            Circle()
                                                .fill(OPSStyle.Colors.primaryAccent)
                                                .frame(width: 60, height: 60)
                                            
                                            Text(getInitials())
                                                .font(OPSStyle.Typography.bodyBold)
                                                .foregroundColor(.white)
                                        }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        // Name and role
                                        HStack(spacing: 8) {
                                            Text(user.fullName)
                                                .font(OPSStyle.Typography.bodyBold)
                                                .foregroundColor(.white)
                                            
                                            Text("| \(user.role.displayName)")
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                        
                                        // Email
                                        if let email = user.email, !email.isEmpty {
                                            Text(email)
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                        
                                        // Phone
                                        if let phone = user.phone, !phone.isEmpty {
                                            Text(phone)
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .padding(16)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }
                        
                        // Form fields
                        VStack(spacing: 24) {
                            // PERSONAL INFORMATION section
                            SettingsSectionHeader(title: "PERSONAL INFORMATION")
                            
                            // Name fields in HStack
                            HStack(spacing: 16) {
                                // First name
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("First Name")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    
                                    if isEditing {
                                        TextField("", text: $firstName)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(OPSStyle.Colors.cardBackgroundDark)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                            )
                                    } else {
                                        Text(firstName.isEmpty ? "Not set" : firstName)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(firstName.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(OPSStyle.Colors.cardBackgroundDark)
                                            .cornerRadius(12)
                                    }
                                }
                                
                                // Last name
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Last Name")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    
                                    if isEditing {
                                        TextField("", text: $lastName)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(OPSStyle.Colors.cardBackgroundDark)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                            )
                                    } else {
                                        Text(lastName.isEmpty ? "Not set" : lastName)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(lastName.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(OPSStyle.Colors.cardBackgroundDark)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Contact fields
                            HStack(spacing: 16) {
                                // Email - not editable
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Email Address")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    
                                    Text(email.isEmpty ? "Not set" : email)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(email.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(OPSStyle.Colors.cardBackgroundDark)
                                        .cornerRadius(12)
                                }
                                
                                // Phone
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Phone Number")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    
                                    if isEditing {
                                        TextField("", text: $phone)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(OPSStyle.Colors.cardBackgroundDark)
                                            .cornerRadius(12)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                            )
                                            .keyboardType(.phonePad)
                                    } else {
                                        Text(phone.isEmpty ? "Not set" : phone)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(phone.isEmpty ? OPSStyle.Colors.tertiaryText : .white)
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(OPSStyle.Colors.cardBackgroundDark)
                                            .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Home address
                            formField(title: "Home Address", text: $homeAddress, isEditable: isEditing)
                            
                            // CREDENTIALS section
                            SettingsSectionHeader(title: "CREDENTIALS")
                            
                            SettingsCategoryButton(
                                title: "Reset Password",
                                description: "Change your account password",
                                icon: "lock.shield",
                                action: {
                                    showResetPasswordSheet = true
                                }
                            )
                            .padding(.horizontal, 20)
                            .disabled(!isEditing)
                            .opacity(isEditing ? 1.0 : 0.6)
                            
                            // Save button (visible only in edit mode)
                            if isEditing {
                                SettingsButton(
                                    title: "Save Changes",
                                    icon: "checkmark.circle",
                                    style: .primary,
                                    action: saveChanges
                                )
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .onAppear(perform: loadUserData)
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
            .sheet(isPresented: $showResetPasswordSheet, onDismiss: {
                resetPasswordFields()
            }) {
                resetPasswordSheet
                    .onAppear {
                        // Pre-populate with current user's email when sheet appears
                        if resetEmail.isEmpty, let userEmail = dataController.currentUser?.email {
                            resetEmail = userEmail
                        }
                    }
            }
        }
    }
    // Password reset sheet view
    private var resetPasswordSheet: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                Text("Reset Password")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                    .padding(.top, 24)
                
                if !passwordResetSuccess {
                    VStack(spacing: 16) {
                        // Description
                        Text("Enter your email address to receive a password reset link.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        
                        // Email field with OPSStyle
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            TextField("", text: $resetEmail)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(.white)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 20)
                        
                        // Error message
                        if let error = passwordResetError {
                            Text(error)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }
                        
                        Spacer()
                        
                        // Action buttons with consistent styling
                        HStack(spacing: 16) {
                            // Cancel button
                            Button(action: {
                                // Clear fields and dismiss
                                resetPasswordFields()
                                showResetPasswordSheet = false
                            }) {
                                Text("Cancel")
                                    .font(OPSStyle.Typography.button)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(12)
                            }
                            
                            // Send reset button
                            Button(action: {
                                requestPasswordReset()
                            }) {
                                if passwordResetInProgress {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(OPSStyle.Colors.primaryAccent)
                                        .cornerRadius(12)
                                } else {
                                    Text("Send Reset Link")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(OPSStyle.Colors.primaryAccent)
                                        .cornerRadius(12)
                                }
                            }
                            .disabled(passwordResetInProgress || !isEmailValid)
                            .opacity(isEmailValid ? 1.0 : 0.6)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                } else {
                    // Success view with consistent styling
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(OPSStyle.Typography.largeTitle)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.top, 20)
                        
                        Text("Reset Link Sent!")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        
                        Text("We've sent a password reset link to your email. Please check your inbox and follow the instructions to reset your password.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        Spacer()
                        
                        Button(action: {
                            resetPasswordFields()
                            showResetPasswordSheet = false
                        }) {
                            Text("Close")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    // Email validation
    private var isEmailValid: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return !resetEmail.isEmpty && emailPredicate.evaluate(with: resetEmail)
    }
    
    // Request password reset function
    private func requestPasswordReset() {
        // Clear any previous errors
        passwordResetError = nil
        passwordResetInProgress = true
        
        // Pre-populate email field with the user's email if available
        if resetEmail.isEmpty, let userEmail = dataController.currentUser?.email {
            resetEmail = userEmail
        }
        
        // Validate email format
        guard isEmailValid else {
            passwordResetError = "Please enter a valid email address"
            passwordResetInProgress = false
            return
        }
        
        print("ProfileSettingsView: Requesting password reset for email: \(resetEmail)")
        
        // Call the data controller to request a password reset
        Task {
            let (success, errorMessage) = await dataController.requestPasswordReset(email: resetEmail)
            
            await MainActor.run {
                passwordResetInProgress = false
                
                if success {
                    print("ProfileSettingsView: Password reset request successful")
                    passwordResetSuccess = true
                } else {
                    print("ProfileSettingsView: Password reset request failed: \(errorMessage ?? "Unknown error")")
                    passwordResetError = errorMessage ?? "Failed to send reset link. Please try again."
                }
            }
        }
    }
    
    // Reset password fields
    private func resetPasswordFields() {
        resetEmail = ""
        passwordResetError = nil
        passwordResetSuccess = false
        passwordResetInProgress = false
    }
    
    // sectionHeader function removed in favor of standardized OPSSectionHeader component
    
    private func formField(title: String, text: Binding<String>, isEditable: Bool) -> some View {
        // Use a direct implementation instead of a component reference
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            if isEditable {
                TextField("", text: text)
                    .font(OPSStyle.Typography.body)
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
                    .font(OPSStyle.Typography.body)
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
        // Load user data from data controller
        
        if let user = dataController.currentUser {
            // Load first and last name directly from user model
            firstName = user.firstName
            lastName = user.lastName
            
            email = user.email ?? ""
            phone = user.phone ?? ""
            homeAddress = user.homeAddress ?? ""
            
            // Load profile image if available from URL
            if let profileImageURL = user.profileImageURL {
                // Load image asynchronously
                Task {
                    print("ProfileSettingsView: Attempting to load image from URL: \(profileImageURL)")
                    
                    // First check if it's already in the image cache
                    if let _ = ImageCache.shared.get(forKey: profileImageURL) {
                        print("ProfileSettingsView: Image already in cache")
                        return
                    }
                    
                    // Otherwise load from URL
                    if await loadImage(from: profileImageURL) != nil {
                        print("ProfileSettingsView: Successfully loaded image from URL")
                        // The image is now cached in the ImageCache
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
            
            // Update profile information (no try/catch needed since method returns Bool)
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
        }
    }
}


#Preview {
    ProfileSettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
