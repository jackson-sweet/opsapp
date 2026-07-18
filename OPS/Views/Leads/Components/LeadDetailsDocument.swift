//
//  LeadDetailsDocument.swift
//  OPS
//
//  // DETAILS — the fixed dossier document (Leads redesign spec §5.9).
//  One L1 card of rows whose ORDER NEVER CHANGES; blanks render `—`:
//
//      CLIENT   Calloway Homes
//               HELEN — ON FILE            (roster state / ADD TO CLIENT)
//      PROJECT  Maple Lane porch        →
//      DECK     Backyard deck v2        →
//      PHOTOS   [ADD][▦][▦][▦] …
//      FILES    quote-v2.pdf · EST-0142 …
//
//  58pt mono label column; content region right. The DECK row is omitted
//  entirely (not `—`) when the deck_builder feature is off — a permanently
//  dead row for non-deck trades would be noise, and the fixed-order rule
//  governs state, not feature flags.
//
//  CLIENT is deliberately non-navigating in v1 — iOS has no client detail
//  push from this context; the row carries the roster state + ADD action.
//

import SwiftUI
import SwiftData

struct LeadDetailsDocument: View {
    let lead: Opportunity
    let client: Client?
    let rosterState: LeadContactRosterState
    let canEdit: Bool
    let projectName: String?
    let attachments: [LeadAttachment]
    let estimates: [Estimate]
    var isAddingToClient: Bool = false
    var onAddToClient: () -> Void = {}
    var onOpenProject: () -> Void = {}
    var onOpenDeck: (DeckDesign) -> Void = { _ in }
    var onCreateDeck: () -> Void = {}
    var onAddPhotos: () -> Void = {}
    var onTapPhoto: (_ items: [LeadPhotoItem], _ index: Int) -> Void = { _, _ in }
    var onOpenAttachment: (LeadAttachment) -> Void = { _ in }
    var onOpenEstimate: (Estimate) -> Void = { _ in }

    @EnvironmentObject private var permissionStore: PermissionStore

    private var deckFeatureEnabled: Bool {
        permissionStore.isFeatureEnabled("deck_builder")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(label: "DETAILS")
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                clientRow
                rowDivider
                projectRow
                if deckFeatureEnabled {
                    rowDivider
                    DocRow(label: "DECK") {
                        LeadDeckSection(
                            opportunity: lead,
                            canManage: canEdit,
                            onCreate: onCreateDeck,
                            onOpen: onOpenDeck
                        )
                    }
                }
                rowDivider
                DocRow(label: "PHOTOS") {
                    LeadPhotosSection(
                        opportunity: lead,
                        canManage: canEdit,
                        onAdd: onAddPhotos,
                        onTap: onTapPhoto
                    )
                }
                rowDivider
                filesRow
            }
            .commandCard()
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.lineSoft)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    // MARK: - CLIENT

    private var clientRow: some View {
        DocRow(label: "CLIENT") {
            VStack(alignment: .leading, spacing: 6) {
                Text(client?.name ?? "—")
                    .font(.custom("Mohave-Medium", size: 14))
                    .foregroundColor(client == nil ? OPSStyle.Colors.textMute : OPSStyle.Colors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                rosterLine
            }
        }
    }

    /// The lead's person against the roster: ON FILE stamp, an ADD TO CLIENT
    /// action, or nothing when the contact mirrors the client / no client.
    @ViewBuilder
    private var rosterLine: some View {
        switch rosterState {
        case .mirrorsClient, .noClient:
            EmptyView()
        case .onFile:
            Text("\(firstNameUpper) — ON FILE")
                .font(.custom("JetBrainsMono-Medium", size: 9))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.oliveTextM)
        case .notOnFile:
            if canEdit {
                Button(action: onAddToClient) {
                    HStack(spacing: 5) {
                        if isAddingToClient {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(OPSStyle.Colors.text2)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text("ADD TO CLIENT")
                            .font(.custom("JetBrainsMono-Medium", size: 9))
                            .tracking(0.9)
                            .textCase(.uppercase)
                    }
                    .foregroundColor(OPSStyle.Colors.text2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous).fill(OPSStyle.Colors.surfaceInput))
                    .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous).strokeBorder(OPSStyle.Colors.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isAddingToClient)
                .accessibilityLabel("Add \(lead.displayContactName) to the client roster")
            } else {
                Text("NOT ON FILE")
                    .font(.custom("JetBrainsMono-Medium", size: 9))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
    }

    private var firstNameUpper: String {
        lead.displayContactName
            .split(separator: " ")
            .first.map(String.init)?
            .uppercased() ?? lead.displayContactName.uppercased()
    }

    // MARK: - PROJECT

    private var projectRow: some View {
        DocRow(label: "PROJECT") {
            if let projectName {
                Button(action: onOpenProject) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(projectName)
                            .font(.custom("Mohave-Medium", size: 14))
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open project \(projectName)")
            } else {
                Text("—")
                    .font(.custom("Mohave-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
    }

    // MARK: - FILES

    private var filesRow: some View {
        DocRow(label: "FILES") {
            if attachments.isEmpty && estimates.isEmpty {
                Text("—")
                    .font(.custom("Mohave-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.textMute)
            } else {
                VStack(spacing: 0) {
                    ForEach(estimates) { estimate in
                        fileLine(
                            icon: "doc.text",
                            name: estimate.title?.isEmpty == false ? estimate.title! : estimate.estimateNumber,
                            meta: "\(estimate.estimateNumber) · \(BooksFormat.currency(estimate.total))",
                            action: { onOpenEstimate(estimate) }
                        )
                    }
                    ForEach(attachments) { attachment in
                        fileLine(
                            icon: "paperclip",
                            name: attachment.displayName,
                            meta: attachmentMeta(attachment),
                            action: { onOpenAttachment(attachment) }
                        )
                    }
                }
            }
        }
    }

    private func fileLine(icon: String, name: String, meta: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.custom("Mohave-Medium", size: 13.5))
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(meta)
                        .font(.custom("JetBrainsMono-Regular", size: 8.5))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(name)")
    }

    private func attachmentMeta(_ attachment: LeadAttachment) -> String {
        var parts: [String] = []
        if let from = attachment.fromEmail, !from.isEmpty { parts.append(from) }
        if let date = attachment.date {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            parts.append(f.string(from: date).uppercased())
        }
        return parts.isEmpty ? attachment.ingestStatus.uppercased() : parts.joined(separator: " · ")
    }
}

// MARK: - Document row (58pt mono label column)

struct DocRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 8.5))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 3)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }
}
