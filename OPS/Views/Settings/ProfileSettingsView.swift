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
    @State private var showSaveConfirmation = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var showResetPasswordSheet = false
    @State private var resetEmail = ""
    @State private var passwordResetInProgress = false
    @State private var passwordResetError: String? = nil
    @State private var passwordResetSuccess = false
    @State private var refreshID = UUID()
    @State private var showDeleteAccountSheet = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var deleteError: String? = nil
    
    // Track changes for save button
    @State private var originalFirstName: String = ""
    @State private var originalLastName: String = ""
    @State private var originalPhone: String = ""
    @State private var originalHomeAddress: String = ""
    
    private var hasChanges: Bool {
        firstName != originalFirstName ||
        lastName != originalLastName ||
        phone != originalPhone ||
        homeAddress != originalHomeAddress
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header area with back button and title
                SettingsHeader(
                    title: "Profile Settings",
                    showEditButton: hasChanges,
                    isEditing: hasChanges,
                    editButtonText: "SAVE",
                    onBackTapped: {
                        dismiss()
                    },
                    onEditTapped: {
                        saveChanges()
                    }
                )
                .padding(.bottom, 8)
                
                // Scrollable content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // Profile header - no card background
                        if let user = dataController.currentUser {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top, spacing: 16) {
                                    // User avatar - updated to match app style
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
                                            // Simple circle outline with text - black and white
                                            Circle()
                                                .stroke(Color.white, lineWidth: 2)
                                                .frame(width: 60, height: 60)
                                                .background(Color.black)
                                                .clipShape(Circle())
                                            
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
                                        
                                        // Email - moved out of input fields
                                        if let userEmail = user.email, !userEmail.isEmpty {
                                            Text(userEmail)
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                        
                                        // Phone
                                        if let userPhone = user.phone, !userPhone.isEmpty {
                                            Text(userPhone)
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Form fields - all directly editable
                        VStack(spacing: 24) {
                            // PERSONAL INFORMATION section
                            SettingsSectionHeader(title: "PERSONAL INFORMATION")
                            
                            // Name fields in HStack
                            HStack(spacing: 16) {
                                FormTextField(
                                    title: "First Name",
                                    text: $firstName
                                )
                                
                                FormTextField(
                                    title: "Last Name",
                                    text: $lastName
                                )
                            }
                            .padding(.horizontal, 20)
                            
                            // Phone - directly editable
                            FormTextField(
                                title: "Phone Number",
                                text: $phone,
                                keyboardType: .phonePad
                            )
                            .padding(.horizontal, 20)
                            
                            // Email note
                            Text("You cannot change your email address, it is the foundation of your account")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .italic()
                                .padding(.horizontal, 20)
                                .padding(.top, -16)
                            
                            // Home address - with autocomplete
                            VStack(alignment: .leading, spacing: 8) {
                                Text("HOME ADDRESS")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                AddressAutocompleteField(
                                    address: $homeAddress,
                                    placeholder: "Enter your home address"
                                ) { address, coordinate in
                                    // Optional: Could store coordinates if needed
                                    if let coord = coordinate {
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
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
                            
                            SettingsCategoryButton(
                                title: "Delete Account",
                                description: "Permanently remove your account and data",
                                icon: "trash.circle",
                                action: {
                                    showDeleteAccountSheet = true
                                }
                            )
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 40)
                    }
                    .padding(.top, 12)
                    .tabBarPadding() // Add padding for tab bar
                }
                
            }
            .navigationBarBackButtonHidden(true)
            .swipeBackGesture() // Add swipe-back gesture
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
                        if resetEmail.isEmpty, let userEmail = dataController.currentUser?.email {
                            resetEmail = userEmail
                        }
                    }
            }
            .sheet(isPresented: $showDeleteAccountSheet) {
                deleteAccountSheet
            }
        }
    }
    
    // Password reset sheet view (unchanged)
    private var resetPasswordSheet: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Text("Reset Password")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                    .padding(.top, 24)
                
                if !passwordResetSuccess {
                    VStack(spacing: 16) {
                        Text("Enter your email address to receive a password reset link.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        
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
                        
                        if let error = passwordResetError {
                            Text(error)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 16) {
                            Button(action: {
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
    
    // Delete account sheet view
    private var deleteAccountSheet: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                // Header
                HStack {
                    Spacer()
                    Button(action: {
                        showDeleteAccountSheet = false
                        deleteConfirmationText = ""
                        deleteError = nil
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // Icon
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 60))
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .padding(.top, 10)
                VStack(spacing: 4){
                    // Title
                    Text("DELETE ACCOUNT")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    // Warning message
                    VStack(spacing: 16) {
                        Text("PERMANENT ACTION")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                    
                    Spacer()
                    
                    Text("This action cannot be undone. All your data, projects, and settings will be permanently deleted.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Confirmation input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type \"confirm delete\" to proceed")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        TextField("", text: $deleteConfirmationText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(deleteConfirmationText.lowercased() == "confirm delete" ?
                                            OPSStyle.Colors.errorStatus :
                                                OPSStyle.Colors.tertiaryText.opacity(0.3),
                                            lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Error message
                    if let error = deleteError {
                        Text(error)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                
                Spacer()
                
                // Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        deleteAccount()
                    }) {
                        if isDeletingAccount {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.errorStatus)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        } else {
                            Text("Delete My Account")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.errorStatus)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    .disabled(deleteConfirmationText.lowercased() != "confirm delete" || isDeletingAccount)
                    .opacity(deleteConfirmationText.lowercased() == "confirm delete" && !isDeletingAccount ? 1.0 : 0.6)
                    
                    Button(action: {
                        showDeleteAccountSheet = false
                        deleteConfirmationText = ""
                        deleteError = nil
                    }) {
                        Text("Cancel")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
    
    // Email validation
    private var isEmailValid: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return !resetEmail.isEmpty && emailPredicate.evaluate(with: resetEmail)
    }
    
    // Request password reset function (unchanged)
    private func requestPasswordReset() {
        passwordResetError = nil
        passwordResetInProgress = true
        
        if resetEmail.isEmpty, let userEmail = dataController.currentUser?.email {
            resetEmail = userEmail
        }
        
        guard isEmailValid else {
            passwordResetError = "Please enter a valid email address"
            passwordResetInProgress = false
            return
        }
        
        
        Task {
            let (success, errorMessage) = await dataController.requestPasswordReset(email: resetEmail)
            
            await MainActor.run {
                passwordResetInProgress = false
                
                if success {
                    passwordResetSuccess = true
                } else {
                    print("ProfileSettingsView: Password reset request failed: \(errorMessage ?? "Unknown error")")
                    passwordResetError = errorMessage ?? "Failed to send reset link. Please try again."
                }
            }
        }
    }
    
    // Reset password fields (unchanged)
    private func resetPasswordFields() {
        resetEmail = ""
        passwordResetError = nil
        passwordResetSuccess = false
        passwordResetInProgress = false
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
            firstName = user.firstName
            lastName = user.lastName
            email = user.email ?? ""
            phone = user.phone ?? ""
            homeAddress = user.homeAddress ?? ""
            
            // Store original values to track changes
            originalFirstName = firstName
            originalLastName = lastName
            originalPhone = phone
            originalHomeAddress = homeAddress
            
            // Load profile image if available
            if let profileImageURL = user.profileImageURL {
                Task {
                    
                    if let _ = ImageCache.shared.get(forKey: profileImageURL) {
                        return
                    }
                    
                    if await loadImage(from: profileImageURL) != nil {
                    } else {
                        print("ProfileSettingsView: Failed to load image from URL")
                    }
                }
            } else {
            }
        }
    }
    
    private func loadImage(from urlString: String) async -> UIImage? {
        if urlString.starts(with: "local://") {
            if let imageBase64 = UserDefaults.standard.string(forKey: urlString),
               let imageData = Data(base64Encoded: imageBase64),
               let image = UIImage(data: imageData) {
                ImageCache.shared.set(image, forKey: urlString)
                return image
            }
            return nil
        }
        
        var imageURL = urlString
        if imageURL.starts(with: "//") {
            imageURL = "https:" + imageURL
        }
        
        guard let url = URL(string: imageURL) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                ImageCache.shared.set(image, forKey: urlString)
                return image
            }
        } catch {
            print("Failed to load image: \(error.localizedDescription)")
        }
        
        return nil
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
                phone: phone,
                homeAddress: homeAddress
            )
            
            await MainActor.run {
                if success {
                    // Update original values to reflect successful save
                    originalFirstName = firstName
                    originalLastName = lastName
                    originalPhone = phone
                    originalHomeAddress = homeAddress
                } else {
                    saveErrorMessage = "Failed to save profile changes. Please try again."
                    showSaveError = true
                    print("ProfileSettingsView: Failed to save profile changes")
                }
            }
        }
    }
    
    private func deleteAccount() {
        guard deleteConfirmationText.lowercased() == "confirm delete" else { return }
        
        isDeletingAccount = true
        deleteError = nil
        
        Task {
            do {
                // Get current user ID
                guard let userId = dataController.currentUser?.id else {
                    await MainActor.run {
                        deleteError = "Unable to find user ID"
                        isDeletingAccount = false
                    }
                    return
                }
                
                
                // Call API to delete user
                let success = await dataController.deleteUserAccount(userId: userId)
                
                if success {
                    
                    await MainActor.run {
                        // Clear all UserDefaults to ensure clean state
                        if let bundleID = Bundle.main.bundleIdentifier {
                            UserDefaults.standard.removePersistentDomain(forName: bundleID)
                        }
                        UserDefaults.standard.synchronize()
                        
                        // The deleteUserAccount already logged out, which cleared auth state
                        // This will automatically trigger ContentView to show LoginView (signup page)
                        isDeletingAccount = false
                        showDeleteAccountSheet = false
                        
                        // Dismiss all presented views to ensure clean navigation
                        dismiss()
                    }
                } else {
                    await MainActor.run {
                        deleteError = "Failed to delete account. Please try again or contact support."
                        isDeletingAccount = false
                    }
                }
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
                    isDeletingAccount = false
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
