//
//  OnboardingCodeDisplay.swift
//  OPS
//
//  The crew-code renderer. ONE glyph treatment, shared by both ends of the flow:
//
//    • Display mode (`OnboardingCodeDisplay`) — the owner's share screen. Renders
//      the code read-only with a COPY affordance (success haptic + COPIED confirm).
//    • Entry mode (`OnboardingCodeEntry`)    — the crew member's join screen. The
//      same bracketed glyph, but the operator types into it.
//
//  Both compose the shared `BracketedCodeGlyph` so the code reads IDENTICALLY on
//  both screens. JetBrains Mono, tabular + slashed-zero, generous tracking, sharp
//  bracket frame in `text3`. No box-shadow.
//
//  Spec: `DESIGN.md` §4 (numbers are ALWAYS mono, tabular-lining, slashed zero),
//  §2 (`[brackets]` tactical punctuation), `mobile/MOBILE.md` §9 (input fill/border).
//  COPY / COPIED literals are UPPERCASE-for-authority per the OPS voice.
//  Every color / radius / font / spacing value traces to an `OPSStyle` token.
//

import SwiftUI
import UIKit

// MARK: - Shared glyph frame

/// The bracketed code frame shared by display + entry modes so the code renders
/// identically on the owner's share screen and the crew member's join screen.
///
/// `[`  CONTENT  `]` — brackets in `text3`, content slot supplied by the caller.
/// JetBrains Mono with tabular-lining + slashed-zero so every digit aligns.
private struct BracketedCodeGlyph<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) { // 12pt — air around the code
            Text("[")
                .font(OPSStyle.Typography.dataValueLg) // JetBrains Mono Medium 20pt
                .foregroundColor(OPSStyle.Colors.text3)

            content()

            Text("]")
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.inputHeight) // §9 input height (48pt)
        .frame(maxWidth: .infinity)
        .background(OPSStyle.Colors.surfaceInput)      // rgba(255,255,255,0.04)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)) // 5pt
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

/// The code text itself — JetBrains Mono, tracked, tabular + slashed-zero,
/// scaling down before it ever clips. Used by both modes via the glyph frame.
private struct CodeText: View {
    let code: String

    var body: some View {
        Text(code)
            .font(OPSStyle.Typography.dataValueLg)    // JetBrains Mono Medium 20pt
            .monospacedDigit()                        // tabular-lining
            .tracking(2)                              // tactical letter-spacing on the code
            .foregroundColor(OPSStyle.Colors.text)
            .lineLimit(1)
            .minimumScaleFactor(0.5)                  // Dynamic Type / long codes: scale, don't clip
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Display mode (owner share screen)

/// Read-only crew-code display with a COPY affordance. The owner sees their code
/// here and copies it to send to the crew.
struct OnboardingCodeDisplay: View {
    let code: String
    /// Notifies the screen a copy happened (e.g. to surface a toast). Optional —
    /// the component already gives in-line COPIED feedback + a success haptic.
    var onCopy: (() -> Void)?

    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            BracketedCodeGlyph { CodeText(code: code) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Crew code")
                .accessibilityValue(spelledOut(code))

            copyButton
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = code
            OnboardingHaptics.success()
            onCopy?()
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.hover) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.hover) { copied = false }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: copied ? OPSStyle.Icons.checkmark : OPSStyle.Icons.copy)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                Text(copied ? "COPIED" : "COPY")
                    .font(OPSStyle.Typography.buttonLabel) // Cake Mono 300, 14pt
            }
            .foregroundColor(OPSStyle.Colors.text2) // ghost affordance, never accent
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy crew code")
    }

    /// VoiceOver reads codes character-by-character so "B" and "8" don't blur.
    private func spelledOut(_ s: String) -> String {
        s.map { String($0) }.joined(separator: " ")
    }
}

// MARK: - Entry mode (crew join screen)

/// Bracketed crew-code input. The crew member types their code into the same
/// glyph frame the owner shares it in. Auto-uppercases and strips whitespace so
/// the stored value is canonical regardless of how it was pasted.
struct OnboardingCodeEntry: View {
    @Binding var code: String
    var placeholder: String = "ENTER CODE"
    /// Submit label for the keyboard return key.
    var submitLabel: SubmitLabel = .join
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        BracketedCodeGlyph {
            TextField("", text: $code)
                .font(OPSStyle.Typography.dataValueLg) // JetBrains Mono Medium 20pt
                .monospacedDigit()
                .tracking(2)
                .multilineTextAlignment(.center)
                .foregroundColor(OPSStyle.Colors.text)
                .tint(OPSStyle.Colors.text)            // white caret, never accent
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(submitLabel)
                .focused($isFocused)
                .placeholder(when: code.isEmpty) {
                    Text(placeholder.uppercased())
                        .font(OPSStyle.Typography.dataValue) // JetBrains Mono 13pt
                        .tracking(1.5)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(maxWidth: .infinity)
                }
                .onChange(of: code) { _, newValue in
                    // Canonicalize: uppercase, no whitespace — matches how the
                    // owner's display renders it, so the same code reads identically.
                    let cleaned = newValue.uppercased().filter { !$0.isWhitespace }
                    if cleaned != newValue { code = cleaned }
                }
                .onSubmit { onSubmit?() }
        }
        .overlay(
            // Focus brightens the frame border — white, never accent (§9).
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                .stroke(isFocused ? Color.white.opacity(0.20) : Color.clear,
                        lineWidth: OPSStyle.Layout.Border.standard)
        )
        .animation(OPSStyle.Animation.hover, value: isFocused)
        .accessibilityLabel("Crew code")
        .accessibilityValue(code.isEmpty ? "Empty" : code.map { String($0) }.joined(separator: " "))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("OnboardingCodeDisplay / Entry") {
    struct Wrapper: View {
        @State private var entered = ""
        var body: some View {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                VStack(spacing: OPSStyle.Layout.spacing5) {
                    OnboardingCodeDisplay(code: "BR8K-90ZT")
                    OnboardingCodeEntry(code: $entered)
                    OnboardingCodeEntry(code: .constant("BR8K-90ZT"))
                }
                .padding(OPSStyle.Layout.spacing4)
            }
            .preferredColorScheme(.dark)
        }
    }
    return Wrapper()
}
#endif
