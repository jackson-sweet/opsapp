//
//  LeadContactBlock.swift
//  OPS
//
//  The expanded day-sheet card's contact block — where the lead is, and the
//  two ways to reach them. An L2 nested card inside the card's L1 glass shell
//  (MOBILE.md §3: `surfaceInput` fill, `nestedBorder` hairline, r6, no blur).
//
//  Absent lines are OMITTED, never rendered as `—`. This block exists to be
//  acted on, not read as a report: a dash on the PHONE row tells a runner
//  standing in a driveway nothing he can use, and it costs him a line of
//  scanning to learn it. The whole block disappears when all three are absent.
//
//  Every row is a 44pt target carrying an iOS context menu — COPY on all
//  three, plus the channel's own verbs (CALL / TEXT on the number, MAIL on the
//  address). The verbs commit through the host's closures so the day sheet has
//  exactly ONE call/text/email contract (the card's, matching LeadTriageCard's
//  do-and-stamp), never a second one hiding in a menu.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3.4
//

import SwiftUI
import UIKit

struct LeadContactBlock: View {

    let lead: Opportunity
    /// The host's do-and-stamp contracts — identical to the quick-action row's,
    /// so a call placed from the menu logs exactly like a call placed from the
    /// button.
    var onCall: () -> Void = {}
    var onText: () -> Void = {}
    var onEmail: () -> Void = {}

    /// The document's established mono label column (`DocRow`, 58pt) — the
    /// detail sheet and the day sheet line their labels up on the same edge.
    private static let labelColumnWidth: CGFloat = 58

    var body: some View {
        if hasAnyChannel {
            VStack(alignment: .leading, spacing: 0) {
                addressRow
                phoneRow
                emailRow
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.nestedBorder,
                                  lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Rows

    /// Address is prose, so it carries the Mohave body voice; the number and
    /// the address below it are data, so they carry mono.
    @ViewBuilder
    private var addressRow: some View {
        if let address = address {
            row(label: "ADDRESS",
                value: address,
                font: OPSStyle.Typography.cardBody,
                spoken: "Address, \(address)") {
                copyButton(address)
            }
        }
    }

    @ViewBuilder
    private var phoneRow: some View {
        if let phone = phone {
            row(label: "PHONE",
                value: phone,
                font: OPSStyle.Typography.smallCaption,
                spoken: "Phone, \(phone)") {
                copyButton(phone)
                Button {
                    onCall()
                } label: {
                    SwiftUI.Label("CALL", systemImage: OPSStyle.Icons.phone)
                }
                Button {
                    onText()
                } label: {
                    SwiftUI.Label("TEXT", systemImage: OPSStyle.Icons.message)
                }
            }
        }
    }

    @ViewBuilder
    private var emailRow: some View {
        if let email = email {
            row(label: "EMAIL",
                value: email,
                font: OPSStyle.Typography.smallCaption,
                spoken: "Email, \(email)") {
                copyButton(email)
                Button {
                    onEmail()
                } label: {
                    SwiftUI.Label("MAIL", systemImage: OPSStyle.Icons.envelope)
                }
            }
        }
    }

    // MARK: - Row shell

    private func row<Menu: View>(
        label: String,
        value: String,
        font: Font,
        spoken: String,
        @ViewBuilder menu: () -> Menu
    ) -> some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2_5) {
            Text(label)
                .font(OPSStyle.Typography.nanoLabel)
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(width: Self.labelColumnWidth, alignment: .leading)

            // Single line, ellipsized: a wrapped address turns a scan row into
            // a paragraph, and the full string is one long-press away.
            Text(value)
                .font(font)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .contentShape(Rectangle())
        .contextMenu { menu() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityHint("Touch and hold for actions")
    }

    private func copyButton(_ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            SwiftUI.Label("COPY", systemImage: OPSStyle.Icons.copy)
        }
    }

    // MARK: - Derived

    private var address: String? { trimmed(lead.address) }
    private var phone: String? { trimmed(lead.contactPhone) }
    private var email: String? { trimmed(lead.contactEmail) }

    private var hasAnyChannel: Bool {
        address != nil || phone != nil || email != nil
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadContactBlock / full + sparse") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(spacing: OPSStyle.Layout.spacing3) {
            LeadContactBlock(lead: {
                let lead = Opportunity.preview(contactName: "Marcus Webb", stage: .quoting)
                lead.address = "1841 Beckwith Ave, Burnaby BC"
                lead.contactPhone = "604-555-0142"
                lead.contactEmail = "marcus.webb@example.com"
                return lead
            }())

            // Phone only — ADDRESS and EMAIL are absent, not blank.
            LeadContactBlock(lead: {
                let lead = Opportunity.preview(contactName: "Dana Ruiz", stage: .followUp)
                lead.contactPhone = "604-555-0177"
                return lead
            }())
        }
        .padding(OPSStyle.Layout.spacing3_5)
    }
    .preferredColorScheme(.dark)
}
#endif
