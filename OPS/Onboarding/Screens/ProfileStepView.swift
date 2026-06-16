//
//  ProfileStepView.swift
//  OPS
//
//  Onboarding rebuild P5 — S6c (Profile): the crew-path POST-JOIN profile screen.
//  The worker has just committed the crew JOIN (S5c) and lands here to set up the
//  identity their crew will see — name, phone, and an OPTIONAL photo. This is the
//  first screen behind the join, so there is NO back-edge (`profile.backEdge=nil`);
//  SIGN OUT is the escape.
//
//  Design spec §4.2 S6c:
//    • Title intent "SET UP YOUR PROFILE" (ops-copywriter).
//    • First + last name PREFILLED from `formData` (editable), phone — all REQUIRED.
//    • An OPTIONAL profile photo.
//    • CTA gated on first + last + phone non-empty; the photo never gates.
//
//  AVATAR — NEVER SILENT (R7). The legacy employee-profile path uploaded the avatar
//  through `OnboardingManager.uploadAvatarDuringOnboarding`, which CATCHES the error
//  and only `print`s it — a failed upload was invisible. This rebuild surfaces it:
//  on selection the screen uploads via the boundary with a VISIBLE progress state;
//  on FAILURE it shows a retry-able inline error (NOT a silent print). Because the
//  photo is optional, a worker can knowingly proceed after a failure (CONTINUE stays
//  live — the gate is name + phone, never the photo).
//
//  SAVE/UPLOAD CONTRACT — the screen owns NO data logic and reaches NO singletons.
//  Both operations funnel through an injected `ProfileBoundary`:
//    • `uploadAvatar(imageData:)` → `AvatarUploadOutcome` (`.uploaded(url:)` / `.failed`).
//      The live boundary calls the Supabase Storage upload + `UserRepository`
//      `updateProfileImageUrl` in a way that THROWS, so failure is real (the legacy
//      manager method that swallows the error is left untouched for its legacy caller).
//    • `saveProfile(firstName:lastName:phone:)` → `ProfileSaveOutcome` (`.saved` /
//      `.failed`). The live boundary wraps `OnboardingManager.saveEmployeeProfile`
//      (profile-only; emergency fields are S7c's job).
//  On CONTINUE → save → persist into `formData` → `onContinue()` (the gateway advances
//  to `.emergencyContact`). Medium commit haptic on CONTINUE.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, ZERO shadows. Accent (`opsAccent`) appears
//      ONLY on the one primary CTA (via the shared component). The avatar ring, fields,
//      and error lines are neutral / rose — never accent.
//    • Built on the shared components — `OPSOnboardingField`, `OnboardingStepHeader`,
//      `OnboardingPrimaryCTA`. The avatar reuses the house geometry + initial-circle
//      fallback.
//    • One easing curve; honored only when Reduce Motion is off. Medium-impact haptic
//      on CONTINUE; light selection tick on opening the photo picker; error
//      notification on a failed upload.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI
import PhotosUI

// MARK: - Profile boundary (the testable seam)

/// What an avatar upload resolved to. The screen branches on these; the gateway
/// produces them from the live `OnboardingManager` storage path. Never thrown —
/// a failure maps to `.failed` so the screen always has an outcome to surface.
enum AvatarUploadOutcome: Equatable {
    /// The image uploaded + the user row's `profile_image_url` was written.
    /// `url` is the public URL (rendered immediately so the worker sees their photo).
    case uploaded(url: String)

    /// The upload (or the row write) failed (network / storage / server). Surface an
    /// inline retry-able error — NEVER silent. `message` is the bare phrase the view
    /// prefixes with `// ERROR — ` and uppercases.
    case failed(message: String)
}

/// What the profile save resolved to. The screen branches on these; never thrown.
enum ProfileSaveOutcome: Equatable {
    /// Name + phone written (server + local). The gateway advances to
    /// `.emergencyContact`.
    case saved

    /// The save failed. Surface inline, retry-able, never silent. `message` is the
    /// bare phrase the view prefixes + uppercases.
    case failed(message: String)
}

/// The async boundary S6c funnels BOTH its operations through: the OPTIONAL avatar
/// upload, and the required name/phone save. Implemented live by the gateway (over
/// `OnboardingManager`); stubbed in tests. `@MainActor` because the live manager is
/// main-actor isolated.
@MainActor
protocol ProfileBoundary {
    /// Upload the selected avatar (JPEG bytes) to storage and write the user row's
    /// `profile_image_url`. Returns `.uploaded(url:)` on success, `.failed(message:)`
    /// on any error — the failure is REAL (surfaced + retry-able), never swallowed.
    func uploadAvatar(imageData: Data) async -> AvatarUploadOutcome

    /// Persist the worker's first/last name + phone (profile only — emergency contact
    /// is S7c). Returns `.saved` on success, `.failed(message:)` on any error.
    func saveProfile(firstName: String, lastName: String, phone: String) async -> ProfileSaveOutcome
}

// MARK: - S6c screen

struct ProfileStepView: View {

    /// The async boundary. Injected so the screen never touches storage / an RPC.
    let boundary: ProfileBoundary

    /// Persist a collected field into the coordinator's form data. The gateway wires
    /// this to `coordinator.update`. Persists name/phone (resume after a kill) and the
    /// `hasSelectedAvatar` flag (the image bytes are never persisted).
    let onUpdateFormData: (@escaping (inout OnboardingFormData) -> Void) -> Void

    /// Save committed → the gateway advances to `.emergencyContact`.
    let onContinue: () -> Void

    /// SIGN OUT escape (profile has no back-edge — the join is committed). The gateway
    /// wires its real sign-out handler.
    let onSignOut: () -> Void

    // MARK: Init

    init(
        boundary: ProfileBoundary,
        prefillFirstName: String? = nil,
        prefillLastName: String? = nil,
        prefillPhone: String? = nil,
        onUpdateFormData: @escaping (@escaping (inout OnboardingFormData) -> Void) -> Void,
        onContinue: @escaping () -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.boundary = boundary
        self.onUpdateFormData = onUpdateFormData
        self.onContinue = onContinue
        self.onSignOut = onSignOut
        _firstName = State(initialValue: prefillFirstName ?? "")
        _lastName = State(initialValue: prefillLastName ?? "")
        _phone = State(initialValue: prefillPhone ?? "")
    }

    #if DEBUG
    /// Snapshot/preview seam — seeds the visual `@State` so a renderer can capture the
    /// default / avatar-uploading / avatar-error / saving / save-error states a
    /// renderer can't otherwise drive. DEBUG-only; never used by the live gateway.
    init(
        boundary: ProfileBoundary,
        previewFirstName: String = "",
        previewLastName: String = "",
        previewPhone: String = "",
        previewDidAttemptSubmit: Bool = false,
        previewAvatarStatus: AvatarStatus = .none,
        previewSaveError: String? = nil,
        previewIsSaving: Bool = false
    ) {
        self.boundary = boundary
        self.onUpdateFormData = { _ in }
        self.onContinue = {}
        self.onSignOut = {}
        _firstName = State(initialValue: previewFirstName)
        _lastName = State(initialValue: previewLastName)
        _phone = State(initialValue: previewPhone)
        _didAttemptSubmit = State(initialValue: previewDidAttemptSubmit)
        _avatarStatus = State(initialValue: previewAvatarStatus)
        _saveError = State(initialValue: previewSaveError)
        _isSaving = State(initialValue: previewIsSaving)
        _hasAppeared = State(initialValue: true) // settle the entrance for snapshots
    }
    #endif

    // MARK: Field state

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""

    /// The avatar lifecycle: none → uploading → uploaded(image) / failed(image,message).
    /// Carries the selected `UIImage` so a failed upload still shows the chosen photo
    /// behind the retry affordance.
    @State private var avatarStatus: AvatarStatus = .none

    /// True once the user has tried to submit — gates whether the required-field errors
    /// render (the form is clean before the first attempt).
    @State private var didAttemptSubmit = false

    /// A surfaced save failure — rendered inline above the CTA, never silent. Cleared
    /// on the next attempt.
    @State private var saveError: String?

    /// True while the profile save is in flight — drives the CTA spinner + gate.
    @State private var isSaving = false

    @State private var showPhotoPicker = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                scrollContent
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            OnboardingHaptics.prepare()
            runEntrance()
        }
        .sheet(isPresented: $showPhotoPicker) {
            ProfilePhotoPickerSheet(onPicked: { image in handlePicked(image) })
        }
    }

    /// The full vertical stack. Extracted so the DEBUG snapshot harness can render it
    /// WITHOUT the enclosing `ScrollView` (`ImageRenderer` reports zero intrinsic size
    /// for a `ScrollView`). The live screen always wraps this in the scroll view.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            subline
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            avatarBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            fieldsBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            ctaBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
        .padding(.bottom, OPSStyle.Layout.spacing5)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: (hasAppeared || reduceMotion) ? 0 : OPSStyle.Layout.spacing3)
    }

    #if DEBUG
    /// A render of the screen with no `ScrollView`, for the snapshot harness only.
    /// Top-aligned on the canvas so the captured frame matches the live layout.
    var snapshotBody: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            scrollContent
        }
    }
    #endif

    // MARK: - Header (no Back — join committed; SIGN OUT is the escape)

    private var header: some View {
        OnboardingStepHeader(
            title: "Set up your profile",
            onSignOut: onSignOut
        )
    }

    // MARK: - Subline

    private var subline: some View {
        Text("Your crew sees this.")
            .font(OPSStyle.Typography.body) // Mohave 16pt
            .foregroundColor(OPSStyle.Colors.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Your crew sees this")
    }

    // MARK: - Avatar (optional — never silent on failure)

    private var avatarBlock: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ProfileAvatarPicker(
                status: avatarStatus,
                onTap: {
                    OnboardingHaptics.selection()
                    showPhotoPicker = true
                }
            )
            .frame(maxWidth: .infinity)

            // R7 — a failed upload surfaces inline (NEVER a silent print) with a
            // retry-able affordance directly beneath the avatar.
            if case .failed(_, let message) = avatarStatus {
                Button {
                    OnboardingHaptics.selection()
                    retryAvatarUpload()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1 + 2) {
                        Text("// ERROR — \(message.uppercased())")
                            .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                            .tracking(1.4)
                            .foregroundColor(OPSStyle.Colors.rose)
                        Image(systemName: OPSStyle.Icons.arrowClockwise)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.rose)
                        Text("RETRY")
                            .font(OPSStyle.Typography.miniLabel) // JetBrains Mono 10pt
                            .tracking(1.4)
                            .foregroundColor(OPSStyle.Colors.rose)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin) // 44pt tap target
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo didn't upload. Retry.")
            }
        }
    }

    // MARK: - Name + phone fields (all required)

    private var fieldsBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            OPSOnboardingField(
                label: "First name",
                text: $firstName,
                placeholder: "First",
                kind: .name,
                error: effectiveFirstNameError,
                submitLabel: .next
            )
            .onChange(of: firstName) { _, newValue in persistFirstName(newValue) }

            OPSOnboardingField(
                label: "Last name",
                text: $lastName,
                placeholder: "Last",
                kind: .name,
                error: effectiveLastNameError,
                submitLabel: .next
            )
            .onChange(of: lastName) { _, newValue in persistLastName(newValue) }

            OPSOnboardingField(
                label: "Phone",
                text: $phone,
                placeholder: "Your number",
                kind: .phone,
                error: effectivePhoneError,
                submitLabel: .done,
                onSubmit: { attemptContinue() }
            )
            .onChange(of: phone) { _, newValue in persistPhone(newValue) }
        }
    }

    // MARK: - CTA

    private var ctaBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            if let saveError {
                Text("// ERROR — \(saveError.uppercased())")
                    .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                    .tracking(1.4)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error. \(saveError)")
            }

            OnboardingPrimaryCTA(
                title: "Continue",
                isEnabled: isFormValid,
                isLoading: isSaving
            ) {
                attemptContinue()
            }
        }
    }

    // MARK: - Validation

    /// The pure validator for the required name + phone gate.
    var validation: ProfileValidation {
        ProfileValidation(firstName: firstName, lastName: lastName, phone: phone)
    }

    /// The CTA is live only when first + last + phone are all present. The optional
    /// photo never gates (a save-after-upload-failure is allowed — the worker proceeds
    /// knowingly).
    var isFormValid: Bool { validation.isFormValid }

    /// Each field's error renders only after a submit attempt (the form is clean
    /// before the first attempt).
    var effectiveFirstNameError: String? { didAttemptSubmit ? validation.firstNameError : nil }
    var effectiveLastNameError: String? { didAttemptSubmit ? validation.lastNameError : nil }
    var effectivePhoneError: String? { didAttemptSubmit ? validation.phoneError : nil }

    // MARK: - Avatar actions

    /// A picked image → upload immediately with a visible progress state. The bytes
    /// are JPEG-encoded once here; a failure keeps the image so RETRY re-uses it.
    private func handlePicked(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            avatarStatus = .failed(image: image, message: "couldn't read photo")
            OnboardingHaptics.error()
            return
        }
        onUpdateFormData { $0.hasSelectedAvatar = true }
        uploadAvatar(image: image, data: data)
    }

    /// Re-attempt the upload for the already-selected (failed) image.
    private func retryAvatarUpload() {
        guard case .failed(let image, _) = avatarStatus else { return }
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        uploadAvatar(image: image, data: data)
    }

    /// Drive the avatar upload through the boundary, surfacing every state. A failure
    /// fires the error haptic + an inline retry-able error — never a silent print.
    private func uploadAvatar(image: UIImage, data: Data) {
        avatarStatus = .uploading(image: image)

        Task { @MainActor in
            let outcome = await boundary.uploadAvatar(imageData: data)
            switch outcome {
            case .uploaded(let url):
                avatarStatus = .uploaded(image: image, url: url)
            case .failed(let message):
                avatarStatus = .failed(image: image, message: message)
                OnboardingHaptics.error()
            }
        }
    }

    // MARK: - Continue (the profile save)

    /// The profile commit. Lights the required-field errors, gates on name + phone,
    /// then funnels the save through the boundary. `.saved` → onContinue (gateway
    /// advances to `.emergencyContact`); `.failed` → inline error, NO nav.
    func attemptContinue() {
        didAttemptSubmit = true
        saveError = nil
        guard isFormValid else { return }
        guard !isSaving else { return }

        let fn = validation.trimmedFirstName
        let ln = validation.trimmedLastName
        let ph = validation.trimmedPhone

        persistFirstName(fn)
        persistLastName(ln)
        persistPhone(ph)

        isSaving = true
        OnboardingHaptics.commit() // medium impact ON TAP

        Task { @MainActor in
            let outcome = await boundary.saveProfile(firstName: fn, lastName: ln, phone: ph)
            isSaving = false
            handle(outcome)
        }
    }

    /// Route a save outcome. `.saved` is the only navigation — delegated to the pure
    /// `ProfileSaveOutcomeRouter` so it is unit-testable; the error case sets local
    /// state here.
    func handle(_ outcome: ProfileSaveOutcome) {
        let navigated = ProfileSaveOutcomeRouter.route(outcome, onContinue: onContinue)
        guard !navigated else { return }

        if case .failed(let message) = outcome {
            saveError = message
        }
    }

    // MARK: - Entrance

    private func runEntrance() {
        guard !hasAppeared else { return }
        if reduceMotion {
            hasAppeared = true
        } else {
            withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
        }
    }

    // MARK: - Form-data persistence (trimmed → nil-if-blank)

    private func persistFirstName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdateFormData { $0.firstName = trimmed.isEmpty ? nil : trimmed }
    }

    private func persistLastName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdateFormData { $0.lastName = trimmed.isEmpty ? nil : trimmed }
    }

    private func persistPhone(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdateFormData { $0.phone = trimmed.isEmpty ? nil : trimmed }
    }
}

// MARK: - Avatar status (the avatar lifecycle, unit-testable)

/// The avatar's visible lifecycle. Carries the selected image so the uploading /
/// failed states still render the chosen photo. `Equatable` for tests (compares on
/// case + url/message; `UIImage` identity is not part of equality).
enum AvatarStatus: Equatable {
    case none
    case uploading(image: UIImage)
    case uploaded(image: UIImage, url: String)
    case failed(image: UIImage, message: String)

    /// The selected image, if one exists in this state.
    var image: UIImage? {
        switch self {
        case .none: return nil
        case .uploading(let image), .uploaded(let image, _), .failed(let image, _): return image
        }
    }

    /// True while an upload is in flight (drives the spinner overlay).
    var isUploading: Bool { if case .uploading = self { return true } else { return false } }

    /// True once an upload has succeeded (the photo is committed).
    var isUploaded: Bool { if case .uploaded = self { return true } else { return false } }

    /// The surfaced failure message, if this state is a failure.
    var failureMessage: String? { if case .failed(_, let message) = self { return message } else { return nil } }

    static func == (lhs: AvatarStatus, rhs: AvatarStatus) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.uploading, .uploading): return true
        case (.uploaded(_, let l), .uploaded(_, let r)): return l == r
        case (.failed(_, let l), .failed(_, let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Pure save-outcome routing (no SwiftUI, fully unit-testable)

/// Routes the ONE host-navigating outcome (`.saved`) and reports whether it handled
/// the outcome. The error case is local-state-only and returns `false` so the caller
/// applies it to `@State`. The house pattern (see `ConfirmCompanyOutcomeRouter`).
enum ProfileSaveOutcomeRouter {
    /// - Returns: `true` when the outcome was the host-navigation effect (and the
    ///   `onContinue` closure was invoked); `false` for the local-state-only error case.
    @discardableResult
    static func route(_ outcome: ProfileSaveOutcome, onContinue: () -> Void) -> Bool {
        switch outcome {
        case .saved:
            onContinue()
            return true
        case .failed:
            return false
        }
    }
}

// MARK: - Pure validation (no SwiftUI, fully unit-testable)

/// The complete validation surface for S6c, derived purely from the typed fields.
/// Name + phone are REQUIRED; the photo is optional and never appears here. Error
/// strings are the bare phrase (the field renders the `// ERROR — ` prefix). Copy
/// locked via ops-copywriter.
struct ProfileValidation: Equatable {
    let firstName: String
    let lastName: String
    let phone: String

    var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedLastName: String { lastName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedPhone: String { phone.trimmingCharacters(in: .whitespacesAndNewlines) }

    var firstNameError: String? { trimmedFirstName.isEmpty ? "enter your first name" : nil }
    var lastNameError: String? { trimmedLastName.isEmpty ? "enter your last name" : nil }
    var phoneError: String? { trimmedPhone.isEmpty ? "enter your phone number" : nil }

    /// The CTA gate — first + last + phone all present. The optional photo never gates.
    var isFormValid: Bool {
        !trimmedFirstName.isEmpty && !trimmedLastName.isEmpty && !trimmedPhone.isEmpty
    }
}

// MARK: - Avatar picker (optional photo, with progress + failure surfacing)

/// The tappable avatar. A neutral hairline-ringed circle with an ADD PHOTO empty
/// state; once a photo is selected it renders the image, with an UPLOADING spinner
/// overlay while in flight and a rose ring on failure (the retry affordance lives
/// beneath, owned by the screen). NO accent — the ring is neutral / rose only.
private struct ProfileAvatarPicker: View {
    let status: AvatarStatus
    let onTap: () -> Void

    private let side: CGFloat = 112

    private var ringColor: Color {
        switch status {
        case .failed: return OPSStyle.Colors.rose
        default: return OPSStyle.Colors.line
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image = status.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.surfaceInput)
                        .frame(width: side, height: side)
                        .overlay(
                            VStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: OPSStyle.Icons.camera)
                                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .regular))
                                    .foregroundColor(OPSStyle.Colors.text2)
                                Text("ADD PHOTO")
                                    .font(OPSStyle.Typography.miniLabel) // JetBrains Mono 10pt
                                    .tracking(1.4)
                                    .foregroundColor(OPSStyle.Colors.text3)
                            }
                        )
                }

                // Uploading scrim + spinner overlay.
                if status.isUploading {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: side, height: side)
                    VStack(spacing: OPSStyle.Layout.spacing1) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.text))
                            .controlSize(.small)
                        Text("UPLOADING")
                            .font(OPSStyle.Typography.microLabel) // JetBrains Mono micro
                            .tracking(1.4)
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }
            }
            .frame(width: side, height: side)
            .overlay(
                Circle().stroke(ringColor, lineWidth: OPSStyle.Layout.Border.thick)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        switch status {
        case .none: return "Add a profile photo, optional"
        case .uploading: return "Uploading photo"
        case .uploaded: return "Profile photo added"
        case .failed: return "Photo upload failed, tap to choose again"
        }
    }
}

// MARK: - PHPicker wrapper (single image)

/// A minimal single-image `PHPicker` sheet. Hands the chosen `UIImage` back on the
/// main actor; dismisses itself. Mirrors the legacy employee-profile picker.
private struct ProfilePhotoPickerSheet: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

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

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ProfilePhotoPickerSheet
        init(_ parent: ProfilePhotoPickerSheet) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                guard let image = image as? UIImage else { return }
                DispatchQueue.main.async { self.parent.onPicked(image) }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
/// A preview/stub boundary — no network. Returns fixed outcomes.
private struct PreviewProfileBoundary: ProfileBoundary {
    var uploadOutcome: AvatarUploadOutcome = .uploaded(url: "https://example.com/p.jpg")
    var saveOutcome: ProfileSaveOutcome = .saved
    func uploadAvatar(imageData: Data) async -> AvatarUploadOutcome { uploadOutcome }
    func saveProfile(firstName: String, lastName: String, phone: String) async -> ProfileSaveOutcome { saveOutcome }
}

#Preview("ProfileStepView — default") {
    ProfileStepView(
        boundary: PreviewProfileBoundary(),
        prefillFirstName: "Jack",
        prefillLastName: "Sweet",
        onUpdateFormData: { _ in },
        onContinue: {},
        onSignOut: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("ProfileStepView — required errors") {
    ProfileStepView(
        boundary: PreviewProfileBoundary(),
        previewDidAttemptSubmit: true
    )
    .preferredColorScheme(.dark)
}
#endif
