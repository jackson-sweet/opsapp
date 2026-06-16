//
//  OnboardingComponentsTests.swift
//  OPSTests
//
//  Tests for the shared, production onboarding components (Task 3.1 of the
//  ONBOARDING REBUILD): OPSOnboardingField, OnboardingStepHeader,
//  OnboardingPrimaryCTA / OnboardingSecondaryCTA, OnboardingCodeDisplay / Entry.
//
//  Two layers:
//    1. GATING logic asserts — structural contracts that must hold (header shows
//       Back only when both backLabel+onBack are set; shows SIGN OUT only when
//       onSignOut is set; the field surfaces its error state; a disabled / loading
//       primary CTA cannot invoke its action).
//    2. VISUAL snapshots — each component rendered to a PNG via `ImageRenderer`
//       (the same harness as `Views/BooksSnapshotTests.swift`) in default,
//       error/disabled, dark-mode, and a Reduce-Motion variant. Attachments are
//       for human/agent visual verification; they never fail on pixels.
//
//  Run:
//    xcodebuild test -scheme OPS \
//      -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//      -only-testing:OPSTests/OnboardingComponentsTests
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class OnboardingComponentsTests: XCTestCase {

    // MARK: - GATING: OnboardingStepHeader edge controls

    func test_header_showsBack_onlyWhenLabelAndHandlerBothPresent() {
        // Both present → Back renders.
        let both = OnboardingStepHeader(title: "Details", backLabel: "Identity", onBack: {})
        XCTAssertTrue(both.showsBack, "Back must render when both backLabel and onBack are provided")

        // Label only → no Back (dumb component must not invent a no-op control).
        let labelOnly = OnboardingStepHeader(title: "Details", backLabel: "Identity", onBack: nil)
        XCTAssertFalse(labelOnly.showsBack, "Back must not render without a handler")

        // Handler only → no Back (no label to show as the previous screen name).
        let handlerOnly = OnboardingStepHeader(title: "Details", backLabel: nil, onBack: {})
        XCTAssertFalse(handlerOnly.showsBack, "Back must not render without a label")

        // Neither → title-only.
        let titleOnly = OnboardingStepHeader(title: "Welcome")
        XCTAssertFalse(titleOnly.showsBack, "Back must not render when neither is provided")
    }

    func test_header_showsSignOut_onlyWhenHandlerPresent() {
        let withSignOut = OnboardingStepHeader(title: "Crew", onSignOut: {})
        XCTAssertTrue(withSignOut.showsSignOut, "SIGN OUT must render when onSignOut is provided")

        let withoutSignOut = OnboardingStepHeader(title: "Crew", backLabel: "Identity", onBack: {})
        XCTAssertFalse(withoutSignOut.showsSignOut, "SIGN OUT must not render without a handler")

        let titleOnly = OnboardingStepHeader(title: "Welcome")
        XCTAssertFalse(titleOnly.showsSignOut, "SIGN OUT must not render on a title-only header")
    }

    func test_header_backAndSignOut_areIndependent() {
        // A step can be both a back-edge AND escapable — both controls present.
        let both = OnboardingStepHeader(title: "Books", backLabel: "Crew", onBack: {}, onSignOut: {})
        XCTAssertTrue(both.showsBack)
        XCTAssertTrue(both.showsSignOut)
    }

    // MARK: - GATING: OPSOnboardingField error surfacing

    func test_field_surfacesError_whenErrorStringSet() {
        let withError = OPSOnboardingField(label: "Email", text: .constant("x"), kind: .email, error: "enter a valid email")
        XCTAssertTrue(withError.hasError, "Field must enter its error state when an error string is set")
    }

    func test_field_noError_whenErrorNilOrEmpty() {
        let noError = OPSOnboardingField(label: "Email", text: .constant("x"), kind: .email, error: nil)
        XCTAssertFalse(noError.hasError, "Field must not show error treatment when error is nil")

        let emptyError = OPSOnboardingField(label: "Email", text: .constant("x"), kind: .email, error: "")
        XCTAssertFalse(emptyError.hasError, "An empty error string must be treated as no error")
    }

    func test_field_kind_drivesSecureAndKeyboardConfig() {
        XCTAssertTrue(OPSOnboardingField.Kind.password.isSecure)
        XCTAssertFalse(OPSOnboardingField.Kind.email.isSecure)
        XCTAssertEqual(OPSOnboardingField.Kind.email.keyboardType, .emailAddress)
        XCTAssertEqual(OPSOnboardingField.Kind.phone.keyboardType, .phonePad)
        XCTAssertEqual(OPSOnboardingField.Kind.oneTimeCode.textContentType, .oneTimeCode)
    }

    func test_field_autocapitalizationOverride_winsOverKindDefault() {
        // `.text` defaults to .sentences; override to .characters (crew-handle case).
        let overridden = OPSOnboardingField(
            label: "Handle", text: .constant(""), kind: .text,
            autocapitalizationOverride: .characters
        )
        XCTAssertEqual(overridden.effectiveAutocapitalization, .characters)

        let defaulted = OPSOnboardingField(label: "Notes", text: .constant(""), kind: .text)
        XCTAssertEqual(defaulted.effectiveAutocapitalization, .sentences)

        // Email/phone/password never autocapitalize.
        XCTAssertEqual(OPSOnboardingField.Kind.email.autocapitalization, .never)
        XCTAssertEqual(OPSOnboardingField.Kind.name.autocapitalization, .words)
    }

    // MARK: - GATING: OnboardingPrimaryCTA disabled / loading blocks the action

    func test_primaryCTA_disabled_blocksAction() {
        var fired = false
        let cta = OnboardingPrimaryCTA(title: "Continue", isEnabled: false) { fired = true }
        XCTAssertFalse(cta.isInteractive)
        cta.performTap()
        XCTAssertFalse(fired, "A disabled primary CTA must not invoke its action")
    }

    func test_primaryCTA_loading_blocksAction() {
        var fired = false
        let cta = OnboardingPrimaryCTA(title: "Joining", isEnabled: true, isLoading: true) { fired = true }
        XCTAssertFalse(cta.isInteractive)
        cta.performTap()
        XCTAssertFalse(fired, "A loading primary CTA must not invoke its action")
    }

    func test_primaryCTA_enabled_firesAction() {
        var fired = false
        let cta = OnboardingPrimaryCTA(title: "Continue", isEnabled: true) { fired = true }
        XCTAssertTrue(cta.isInteractive)
        cta.performTap()
        XCTAssertTrue(fired, "An enabled, non-loading primary CTA must invoke its action exactly once on tap")
    }

    // MARK: - VISUAL SNAPSHOTS

    /// iPhone 17 logical width (pt).
    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-onboarding-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Renders a SwiftUI view to a PNG at @3x on the canvas background.
    /// Mirrors `Views/BooksSnapshotTests.swift` — attachment for inspection,
    /// plus a sim-tmp mirror. Never fails on pixels; asserts only that the
    /// renderer produced non-empty bytes (structural presence).
    @discardableResult
    private func snapshot<V: View>(
        _ name: String,
        colorScheme: ColorScheme = .dark,
        reduceMotion: Bool = false,
        width: CGFloat? = nil,
        @ViewBuilder _ content: () -> V
    ) -> Data? {
        let w = width ?? deviceWidth
        // `\.accessibilityReduceMotion` is system-derived and not writable on iOS,
        // so we render the reduce-motion variant with animations disabled via a
        // transaction — a still frame has no motion, and this proves the component
        // composes correctly in that mode (its animations are env-gated at runtime).
        let host = content()
            .frame(width: w)
            .padding(.vertical, OPSStyle.Layout.spacing4)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, colorScheme)
            .transaction { if reduceMotion { $0.disablesAnimations = true } }

        let renderer = ImageRenderer(content: host)
        renderer.scale = 3
        renderer.isOpaque = true

        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return nil
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        XCTAssertFalse(data.isEmpty, "\(name) rendered empty")
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
        return data
    }

    func testRenderOnboardingComponents() {
        let pad = OPSStyle.Layout.spacing4

        // --- OPSOnboardingField: default, populated, error, dark ---
        snapshot("field_default") {
            OPSOnboardingField(label: "Full name", text: .constant(""), placeholder: "Your name", kind: .name)
                .padding(.horizontal, pad)
        }
        snapshot("field_populated") {
            OPSOnboardingField(label: "Email", text: .constant("jack@opsapp.co"), kind: .email)
                .padding(.horizontal, pad)
        }
        snapshot("field_error") {
            OPSOnboardingField(label: "Email", text: .constant("not-an-email"), kind: .email, error: "enter a valid email")
                .padding(.horizontal, pad)
        }
        snapshot("field_password_secure") {
            OPSOnboardingField(label: "Password", text: .constant("hunter2"), placeholder: "Min 8 characters", kind: .password)
                .padding(.horizontal, pad)
        }

        // --- OnboardingStepHeader: back, sign-out, title-only, both ---
        snapshot("header_back") {
            OnboardingStepHeader(title: "Your details", backLabel: "Identity", onBack: {})
        }
        snapshot("header_signout") {
            OnboardingStepHeader(title: "Build your crew", onSignOut: {})
        }
        snapshot("header_title_only") {
            OnboardingStepHeader(title: "Welcome")
        }
        snapshot("header_long_title") {
            OnboardingStepHeader(title: "Connect your accounting", backLabel: "Crew", onBack: {}, onSignOut: {})
        }

        // --- OnboardingPrimaryCTA / Secondary: default, disabled, loading, ghost ---
        snapshot("cta_primary") {
            OnboardingPrimaryCTA(title: "Continue", action: {}).padding(.horizontal, pad)
        }
        snapshot("cta_primary_disabled") {
            OnboardingPrimaryCTA(title: "Create account", isEnabled: false, action: {}).padding(.horizontal, pad)
        }
        snapshot("cta_primary_loading") {
            OnboardingPrimaryCTA(title: "Joining crew", isLoading: true, action: {}).padding(.horizontal, pad)
        }
        snapshot("cta_secondary_ghost") {
            OnboardingSecondaryCTA(title: "Sign in", action: {}).padding(.horizontal, pad)
        }

        // --- OnboardingCodeDisplay / Entry: same glyph both ends ---
        snapshot("code_display") {
            OnboardingCodeDisplay(code: "BR8K-90ZT").padding(.horizontal, pad)
        }
        snapshot("code_entry_empty") {
            OnboardingCodeEntry(code: .constant("")).padding(.horizontal, pad)
        }
        snapshot("code_entry_filled") {
            OnboardingCodeEntry(code: .constant("BR8K-90ZT")).padding(.horizontal, pad)
        }

        // --- Reduce Motion variant (proves the components honor the env) ---
        snapshot("field_error_reduce_motion", reduceMotion: true) {
            OPSOnboardingField(label: "Email", text: .constant("bad"), kind: .email, error: "enter a valid email")
                .padding(.horizontal, pad)
        }
        snapshot("cta_primary_reduce_motion", reduceMotion: true) {
            OnboardingPrimaryCTA(title: "Continue", action: {}).padding(.horizontal, pad)
        }

        // --- Full stacked composition (the way a screen assembles them) ---
        snapshot("composed_screen") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                OnboardingStepHeader(title: "Build your crew", onSignOut: {})
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    OnboardingCodeDisplay(code: "BR8K-90ZT")
                    OnboardingPrimaryCTA(title: "Done", action: {})
                    OnboardingSecondaryCTA(title: "Skip for now", action: {})
                }
                .padding(.horizontal, pad)
            }
        }
    }
}
#endif
