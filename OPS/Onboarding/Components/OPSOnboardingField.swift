//
//  OPSOnboardingField.swift
//  OPS
//
//  The single text input used by every rebuilt onboarding screen.
//
//  Spec: `ops-design-system/project/mobile/MOBILE.md` §9 (Form inputs / Text input).
//    • Height ~48pt (mobile touch, larger than web's 36px)
//    • Fill `surfaceInput` (rgba(255,255,255,0.04))
//    • Border `line` (rgba(255,255,255,0.10)); focus brightens to white@0.20 — NO accent
//    • Label ABOVE the field: JetBrains Mono uppercase, `text3`, 0.14em tracking, 6pt gap
//    • Placeholder / value: Mohave 15pt, `text3` / `text`
//    • Error: border → `rose`; error message below in JetBrains Mono 10pt `rose`, `// ERROR — ` voice
//
//  The single OPS easing curve is honored, and reduced motion collapses the
//  focus/error border animation to nothing (the value still changes instantly).
//  Every color / radius / font / animation value traces to an `OPSStyle` token.
//

import SwiftUI
import UIKit

/// The unified onboarding text input. One component covers plain text, email,
/// phone, URL, and secure (password) entry with a show/hide toggle.
///
/// Field configuration (keyboard, content type, autocapitalization) is driven by
/// `OnboardingFieldKind`, with per-instance overrides for the rare screen that
/// needs to deviate (e.g. all-caps crew handles on a `.text` field).
struct OPSOnboardingField: View {

    // MARK: Capitalization

    /// Comparable autocapitalization mode. `TextInputAutocapitalization` is not
    /// `Equatable`, so we model the choice as our own enum (unit-testable) and map
    /// it to SwiftUI's type at the call site.
    enum Capitalization: Equatable {
        case never, words, sentences, characters

        var swiftUI: TextInputAutocapitalization {
            switch self {
            case .never: return .never
            case .words: return .words
            case .sentences: return .sentences
            case .characters: return .characters
            }
        }
    }

    // MARK: Kind

    /// Semantic field kind — drives keyboard, content type, autocapitalization,
    /// autocorrection, and secure entry in one place so screens stay declarative.
    enum Kind {
        case text
        case name
        case email
        case phone
        case url
        case password
        case oneTimeCode

        var isSecure: Bool { self == .password }

        var keyboardType: UIKeyboardType {
            switch self {
            case .text, .name, .password: return .default
            case .email: return .emailAddress
            case .phone: return .phonePad
            case .url: return .URL
            case .oneTimeCode: return .numberPad
            }
        }

        var textContentType: UITextContentType? {
            switch self {
            case .text: return nil
            case .name: return .name
            case .email: return .emailAddress
            case .phone: return .telephoneNumber
            case .url: return .URL
            case .password: return .password
            case .oneTimeCode: return .oneTimeCode
            }
        }

        var autocapitalization: Capitalization {
            switch self {
            case .name: return .words
            case .text: return .sentences
            case .email, .url, .phone, .password, .oneTimeCode: return .never
            }
        }

        var disablesAutocorrection: Bool {
            switch self {
            case .text, .name: return false
            case .email, .url, .phone, .password, .oneTimeCode: return true
            }
        }
    }

    // MARK: Inputs

    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var kind: Kind = .text
    /// When non-nil and non-empty, the field renders its error treatment
    /// (rose border + mono error line below). Pass `nil` for the valid state.
    var error: String?
    /// Override the kind's default autocapitalization (e.g. `.characters` for a
    /// crew handle on a `.text` field). Defaults to the kind's behavior.
    var autocapitalizationOverride: Capitalization?
    /// Submit label for the keyboard return key (e.g. `.next`, `.done`, `.continue`).
    var submitLabel: SubmitLabel = .next
    /// Called when the user commits the field (return key).
    var onSubmit: (() -> Void)?

    // MARK: State

    @FocusState private var isFocused: Bool
    @State private var isRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True when an error string is present — drives the rose border + error line.
    /// `internal` so the error-surfacing contract is unit-testable without rendering.
    var hasError: Bool { !(error ?? "").isEmpty }

    /// The resolved autocapitalization (override beats the kind default).
    /// `internal` + `Equatable` so the resolution is unit-testable.
    var effectiveAutocapitalization: Capitalization {
        autocapitalizationOverride ?? kind.autocapitalization
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1 + 2) { // 6pt label gap (§9)
            labelView
            fieldRow
            if hasError, let error {
                errorLine(error)
            }
        }
    }

    // MARK: Label

    private var labelView: some View {
        Text(label.uppercased())
            .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt — tactical micro-label
            .tracking(1.5)                       // ≈0.14em at 11pt
            .foregroundColor(OPSStyle.Colors.text3)
            .accessibilityHidden(true)           // surfaced via the field's accessibilityLabel
    }

    // MARK: Field

    private var fieldRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            inputControl
                .font(OPSStyle.Typography.body) // Mohave 16pt (≥ §9 15pt floor)
                .foregroundColor(OPSStyle.Colors.text)
                .tint(OPSStyle.Colors.text)     // caret is white, never accent (§9 / anti-patterns)
                .focused($isFocused)
                .keyboardType(kind.keyboardType)
                .textContentType(kind.textContentType)
                .textInputAutocapitalization(effectiveAutocapitalization.swiftUI)
                .autocorrectionDisabled(kind.disablesAutocorrection)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }

            if kind.isSecure {
                revealToggle
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)            // 16pt
        .frame(minHeight: OPSStyle.Layout.inputHeight)           // §9 mobile input height (48pt)
        .background(OPSStyle.Colors.surfaceInput)                 // rgba(255,255,255,0.04)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)) // 5pt
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: hasError ? OPSStyle.Layout.Border.thick : OPSStyle.Layout.Border.standard)
        )
        .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: isFocused)
        .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: hasError)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(text.isEmpty ? "" : (kind.isSecure && !isRevealed ? "Entry hidden" : text))
        .accessibilityHint(hasError ? (error ?? "") : "")
    }

    @ViewBuilder
    private var inputControl: some View {
        if kind.isSecure && !isRevealed {
            SecureField("", text: $text)
                .placeholder(when: text.isEmpty) { placeholderView }
        } else {
            TextField("", text: $text)
                .placeholder(when: text.isEmpty) { placeholderView }
        }
    }

    private var placeholderView: some View {
        Text(placeholder.isEmpty ? label : placeholder)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.text3) // §9 placeholder color
    }

    // MARK: Reveal toggle (secure entry)

    private var revealToggle: some View {
        Button {
            OnboardingHaptics.selection()
            isRevealed.toggle()
        } label: {
            Image(systemName: isRevealed ? "eye.slash" : "eye")
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .regular)) // 20pt icon
                .foregroundColor(OPSStyle.Colors.text2) // metadata icon, never accent (§11)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin) // 44pt target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Error line

    private func errorLine(_ message: String) -> some View {
        Text("// ERROR — \(message.uppercased())")
            .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
            .tracking(1.5)
            .foregroundColor(OPSStyle.Colors.rose)
            .fixedSize(horizontal: false, vertical: true) // Dynamic Type: wrap, don't clip
            .transition(.opacity)
            .accessibilityHidden(true) // surfaced via the field's accessibilityHint
    }

    // MARK: Derived

    private var borderColor: Color {
        if hasError { return OPSStyle.Colors.rose }
        return isFocused ? Color.white.opacity(0.20) : OPSStyle.Colors.line
    }
}

// MARK: - Previews

#if DEBUG
#Preview("OPSOnboardingField") {
    struct Wrapper: View {
        @State private var name = "Jackson Sweet"
        @State private var email = ""
        @State private var password = "hunter2"
        @State private var badEmail = "not-an-email"

        var body: some View {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    OPSOnboardingField(label: "Full name", text: $name, placeholder: "Your name", kind: .name)
                    OPSOnboardingField(label: "Email", text: $email, placeholder: "you@company.com", kind: .email)
                    OPSOnboardingField(label: "Password", text: $password, placeholder: "Min 8 characters", kind: .password)
                    OPSOnboardingField(label: "Email", text: $badEmail, kind: .email, error: "enter a valid email")
                }
                .padding(OPSStyle.Layout.spacing4)
            }
            .preferredColorScheme(.dark)
        }
    }
    return Wrapper()
}
#endif
