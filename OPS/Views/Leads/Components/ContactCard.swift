//
//  ContactCard.swift
//  OPS
//
//  L1 contact card on LeadDetailView. Single panel containing:
//
//      [40pt initials avatar]   Helen Calloway
//                               (555) 123-4567 · 1240 Maple Ave
//
//      [CALL] [TEXT] [EMAIL] [MAP]    ← 4-up button row, all equal weight
//
//  Per Phase 3 brief: NO accent color on any contact CTA. The only accent
//  on the entire LeadDetailView is the MARK WON button in StickyActionBar.
//  All four contact buttons share the surfaceInput + line treatment.
//
//  Buttons whose underlying field is empty render disabled (35% opacity).
//

import SwiftUI

struct ContactCard: View {
    let opportunity: Opportunity

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            header
            actionRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            InitialsAvatar(name: displayName, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.custom("Mohave-Medium", size: 15))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(contactSubline)
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .kerning(0.8)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 4-up CTA row

    private var actionRow: some View {
        HStack(spacing: 6) {
            CTAButton(label: "CALL",  icon: "phone",
                      isEnabled: hasPhone,
                      action: { placeCall() })

            CTAButton(label: "TEXT",  icon: "bubble.left",
                      isEnabled: hasPhone,
                      action: { open("sms:\(sanitizedPhone)") })

            CTAButton(label: "EMAIL", icon: "envelope",
                      isEnabled: hasEmail,
                      action: { open(mailtoURLString) })

            CTAButton(label: "MAP",   icon: "mappin.and.ellipse",
                      isEnabled: hasAddress,
                      action: { open(mapURLString) })
        }
    }

    // MARK: - Derived

    private var displayName: String {
        if !opportunity.contactName.isEmpty { return opportunity.contactName }
        if let title = opportunity.title, !title.isEmpty { return title }
        return "Unnamed lead"
    }

    private var contactSubline: String {
        var parts: [String] = []
        if let phone = opportunity.contactPhone, !phone.isEmpty { parts.append(phone) }
        if let addr  = opportunity.address,      !addr.isEmpty  { parts.append(addr) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var hasPhone: Bool {
        guard let p = opportunity.contactPhone else { return false }
        return !p.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasEmail: Bool {
        guard let e = opportunity.contactEmail else { return false }
        return !e.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasAddress: Bool {
        guard let a = opportunity.address else { return false }
        return !a.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Strips spaces, dashes, parens so `tel:` and `sms:` accept the URL on iOS.
    private var sanitizedPhone: String {
        (opportunity.contactPhone ?? "")
            .filter { "0123456789+".contains($0) }
    }

    private var mapURLString: String {
        let encoded = (opportunity.address ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://maps.apple.com/?address=\(encoded)"
    }

    /// Percent-encodes the email so a malformed-but-present address degrades
    /// gracefully (matching the map path) rather than silently yielding a nil
    /// URL that drops the tap. (review I-11)
    private var mailtoURLString: String {
        let encoded = (opportunity.contactEmail ?? "")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "mailto:\(encoded)"
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIApplication.shared.open(url)
    }

    /// Place an outbound call AND record the intent so OPS can offer a one-tap
    /// "log that call" prompt when the operator returns from the Phone app.
    /// Around-call lead capture (feature 154cb8a3).
    private func placeCall() {
        CallLogStore.shared.recordOutbound(
            opportunityId: opportunity.id,
            contactName: opportunity.contactName,
            phone: opportunity.contactPhone ?? sanitizedPhone
        )
        open("tel:\(sanitizedPhone)")
    }
}

// MARK: - CTAButton (private)

/// One equal-weight contact CTA. Stroke + surfaceInput fill, text2 foreground.
/// 44pt min height per MOBILE.md §1. Disabled appearance: 35% opacity; the
/// button stays in the VoiceOver tree (announced "dimmed") so the action is
/// discoverable even when no contact detail is on file.
private struct CTAButton: View {
    let label: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                Text(label)
                    .font(.custom("CakeMono-Light", size: 11.5))
                    .kerning(0.46)
                    .textCase(.uppercase)
            }
            .foregroundColor(OPSStyle.Colors.text2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.35)
        .accessibilityLabel(label)
        // Keep disabled CTAs in the VoiceOver tree (announced "dimmed") rather
        // than hiding them entirely — the operator should know the action
        // exists but is unavailable. (review W-2)
        .accessibilityHint(isEnabled ? "" : "Unavailable — no contact detail on file")
    }
}

// MARK: - InitialsAvatar (private)

/// Simple 40pt circle with up to two initials. Glass-quiet styling — no
/// accent, no semantic color. The contact card is informational, not status.
private struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 40

    private var initials: String {
        let parts = name
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        let first = parts.first.map { String($0.prefix(1)) } ?? "?"
        let last = parts.count > 1 ? String(parts.last!.prefix(1)) : ""
        return (first + last).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.custom("JetBrainsMono-Medium", size: size * 0.34))
            .foregroundColor(OPSStyle.Colors.text2)
            .frame(width: size, height: size)
            .background(Circle().fill(OPSStyle.Colors.fillNeutralDim))
            .overlay(Circle().strokeBorder(OPSStyle.Colors.line, lineWidth: 1))
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ContactCard / states") {
    ScrollView {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            ContactCard(opportunity: {
                let o = Opportunity.preview(
                    contactName: "Helen Calloway",
                    stage: .quoted,
                    estimatedValue: 14_200
                )
                o.contactPhone = "(555) 123-4567"
                o.contactEmail = "helen@example.com"
                o.address = "1240 Maple Ave"
                return o
            }())

            ContactCard(opportunity: {
                let o = Opportunity.preview(
                    contactName: "Joel Lioudakis",
                    stage: .qualifying,
                    estimatedValue: 6_200
                )
                o.contactPhone = "(555) 234-5678"
                return o
            }())

            ContactCard(opportunity: Opportunity.preview(
                contactName: "Aimee Watari",
                stage: .newLead,
                estimatedValue: nil
            ))
        }
        .padding(.vertical, OPSStyle.Layout.spacing3_5)
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
