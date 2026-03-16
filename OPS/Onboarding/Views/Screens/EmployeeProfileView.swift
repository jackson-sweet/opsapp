//
//  EmployeeProfileView.swift
//  OPS
//
//  Profile setup for employees joining a crew.
//  Collects avatar, name, and phone.
//  All fields are optional — user can skip entirely.
//

import SwiftUI
import PhotosUI

struct EmployeeProfileView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isLoading = false
    @State private var errorMessage = ""


    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack(alignment: .bottom) {
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .padding(.bottom, 8)
                        Text("OPS")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()

                        // Skip button
                        Button(action: onSkip) {
                            Text("SKIP")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                    }
                    .padding(.leading, 4)

                    Spacer().frame(height: 40)

                    // Headline
                    HStack {
                        Text("SET UP YOUR PROFILE")
                            .font(OPSStyle.Typography.heading)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                    }

                    HStack {
                        Text("Your crew will see this info.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                    }
                    .padding(.top, 8)

                    Spacer().frame(height: 32)

                    // Avatar picker
                    avatarSection

                    Spacer().frame(height: 32)

                    // Name fields
                    VStack(spacing: 24) {
                        underlineField("First Name", text: $firstName, contentType: .givenName)
                        underlineField("Last Name", text: $lastName, contentType: .familyName)
                        underlineField("Phone", text: $phone, contentType: .telephoneNumber, keyboard: .phonePad)
                    }

                    Spacer().frame(height: 32)

                    // Error
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .padding(.bottom, 12)
                    }

                    // Continue button
                    Button(action: saveProfile) {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                            } else {
                                HStack {
                                    Text("CONTINUE")
                                        .font(OPSStyle.Typography.bodyBold)
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                                }
                            }
                        }
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .disabled(isLoading)

                    Spacer().frame(height: 20)
                }
                .padding(40)
            }
        }
        .onAppear { OnboardingSupabaseAnalytics.shared.trackStepView("profile") }
        .sheet(isPresented: $showImagePicker) {
            PHPickerSheet(image: $selectedImage)
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        Button { showImagePicker = true } label: {
            ZStack {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Circle()
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                Text("ADD PHOTO")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        )
                }
            }
        }
    }

    // MARK: - Underline Field

    private func underlineField(
        _ placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType? = nil,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(spacing: 8) {
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(OPSStyle.Colors.secondaryText))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .autocapitalization(keyboard == .phonePad ? .none : .words)

            Rectangle()
                .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Save

    private func saveProfile() {
        isLoading = true
        errorMessage = ""

        Task { @MainActor in
            do {
                let fn = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                let ln = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

                if !fn.isEmpty || !ln.isEmpty || !phone.isEmpty {
                    try await onboardingManager.saveEmployeeProfile(
                        firstName: fn.isEmpty ? (dataController.currentUser?.firstName ?? "") : fn,
                        lastName: ln.isEmpty ? (dataController.currentUser?.lastName ?? "") : ln,
                        phone: phone.isEmpty ? nil : phone,
                        emergencyContactName: nil,
                        emergencyContactPhone: nil,
                        emergencyContactRelationship: nil
                    )
                }

                // Upload avatar if selected
                if let image = selectedImage {
                    await uploadAvatar(image)
                }

                isLoading = false
                onComplete()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func uploadAvatar(_ image: UIImage) async {
        guard let userId = dataController.currentUser?.id else { return }
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        do {
            let fileName = "\(userId)/profile.jpg"
            try await SupabaseService.shared.client.storage
                .from("profile-images")
                .upload(
                    path: fileName,
                    file: imageData,
                    options: .init(contentType: "image/jpeg", upsert: true)
                )

            let publicURL = try SupabaseService.shared.client.storage
                .from("profile-images")
                .getPublicURL(path: fileName)

            let userRepo = UserRepository(companyId: dataController.currentUser?.companyId ?? "")
            try await userRepo.updateProfileImageUrl(userId: userId, url: publicURL.absoluteString)

            dataController.currentUser?.profileImageURL = publicURL.absoluteString
            dataController.currentUser?.profileImageData = imageData
            try? dataController.modelContext?.save()
        } catch {
            print("[EMPLOYEE_PROFILE] Avatar upload failed: \(error)")
        }
    }
}

// MARK: - PHPicker Wrapper (single image)

private struct PHPickerSheet: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerSheet
        init(_ parent: PHPickerSheet) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    self.parent.image = image as? UIImage
                }
            }
        }
    }
}
