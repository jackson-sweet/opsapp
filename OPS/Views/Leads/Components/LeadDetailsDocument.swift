//
//  LeadDetailsDocument.swift
//  OPS
//
//  // DETAILS — the fixed dossier document (Leads redesign spec §5.9).
//  One L1 card of rows whose ORDER NEVER CHANGES; blanks render `—`:
//
//      CLIENT   Calloway Homes          →   (opens ContactDetailView)
//               HELEN — ON FILE            (roster state / ADD TO CLIENT)
//      ADDRESS  1240 Maple Ave          →   (opens directions)
//      PROJECT  Maple Lane porch          →  (open only once linked)
//      PROJECT  MATCH PROJECT                (won + unconverted only)
//      LAST WORD← THEM · 2D — Re: quote     (latest meaningful correspondence)
//      DECK     Backyard deck v2        →
//      PHOTOS   [ADD][▦][▦][▦] …
//      FILES    12 attachments             →
//
//  58pt mono label column; content region right. The DECK row is omitted
//  entirely (not `—`) when the deck_builder feature is off — a permanently
//  dead row for non-deck trades would be noise, and the fixed-order rule
//  governs state, not feature flags. The LAST WORD row is likewise omitted
//  (not `—`) when the lead has no correspondence yet — silence needs no
//  monument.
//
//  CLIENT navigates to ContactDetailView — the same canonical contact surface
//  every other client tap in the app opens (JobBoard card, universal search,
//  Spotlight). A linked PROJECT always opens and is never directly re-linked.
//  A won, unconverted lead routes MATCH PROJECT through the canonical guarded
//  conversion sheet so every mirrored relationship and conversion artifact
//  moves in one atomic transaction.
//

import SwiftUI
import SwiftData

struct LeadDetailsDocument: View {
    let lead: Opportunity
    let client: Client?
    let rosterState: LeadContactRosterState
    let canEdit: Bool
    var canMatchProject: Bool = false
    let projectName: String?
    let attachments: [LeadAttachment]
    let estimates: [Estimate]
    var correspondence: LeadCorrespondence? = nil
    var isAddingToClient: Bool = false
    var onAddToClient: () -> Void = {}
    var onOpenClient: () -> Void = {}
    var onOpenAddress: () -> Void = {}
    var onOpenProject: () -> Void = {}
    var onMatchProject: () -> Void = {}
    /// Push `LeadDeckScreen`. The row identifies the drawing; the screen owns
    /// it, so nothing needs to travel with the tap.
    var onOpenDeck: () -> Void = {}
    var onCreateDeck: () -> Void = {}
    var importingPhotoIDs: [String] = []
    var onAddPhotos: () -> Void = {}
    var onTapPhoto: (_ items: [LeadPhotoItem], _ index: Int) -> Void = { _, _ in }
    var onOpenAttachments: () -> Void = {}
    var onOpenEstimate: (Estimate) -> Void = { _ in }

    // Hold-to-edit (bug b1d30fe8). CLIENT and ADDRESS are two of the five
    // facts an operator corrects on a lead; both live in this document, so both
    // take the dossier's hold gesture. The controller owns the open editor, the
    // staged input, and the failure — this view only renders it.
    var fieldEdit: LeadFieldEditController? = nil
    /// Opens the house client picker. The picker is hosted by LeadDetailView so
    /// it presents above the whole dossier, not inside a document row.
    var onEditClient: () -> Void = {}
    /// One-time discovery line on the DETAILS header. Retires itself.
    var showsHoldHint: Bool = false

    enum ProjectRowPresentation: Equatable {
        case linked(label: String)
        case match
        case empty
    }

    static let projectActionMinimumHeight = OPSStyle.Layout.touchTargetMin

    static func projectRowPresentation(
        projectId: String?,
        projectName: String?,
        stage: PipelineStage,
        canMatchProject: Bool
    ) -> ProjectRowPresentation {
        if let projectId,
           !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let name = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .linked(label: name.isEmpty ? "LINKED PROJECT" : name)
        }
        if canMatchProject && stage == .won {
            return .match
        }
        return .empty
    }

    @EnvironmentObject private var permissionStore: PermissionStore

    private var deckFeatureEnabled: Bool {
        permissionStore.isFeatureEnabled("deck_builder")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(
                label: "DETAILS",
                hint: showsHoldHint ? LeadHoldHint.label : nil
            )
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                clientRow
                rowDivider
                addressRow
                rowDivider
                projectRow
                if correspondence != nil {
                    rowDivider
                    lastWordRow
                }
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
                        importingPhotoIDs: importingPhotoIDs,
                        emailPhotoAttachments: attachments,
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
                clientValueLine

                if let failure = fieldEdit?.failure(for: .client) {
                    LeadInlineEditError(failure: failure) {
                        Task { await fieldEdit?.retry() }
                    }
                }

                rosterLine
            }
        }
    }

    /// The client line, in whichever of its three realities is true right now:
    /// linked, being relinked, or absent. Tap opens the client; hold swaps it.
    /// With no client there is nothing to open, so a plain tap picks one —
    /// holding an em dash teaches nobody anything.
    @ViewBuilder
    private var clientValueLine: some View {
        let isWorking = fieldEdit?.isSaving(.client) ?? false
        let pendingName = fieldEdit?.pendingClientName
        let displayName = isWorking
            ? (pendingName ?? client?.name ?? "—")
            : (client?.name ?? "—")
        let hasClient = client != nil

        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(displayName)
                .font(.custom("Mohave-Medium", size: 14))
                .foregroundColor(hasClient || isWorking
                                 ? OPSStyle.Colors.text
                                 : OPSStyle.Colors.textMute)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isWorking {
                ProgressView()
                    .controlSize(.mini)
                    .tint(OPSStyle.Colors.text2)
            } else if hasClient {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: OPSStyle.Layout.touchTargetMin,
            alignment: .leading
        )
        .holdToEdit(
            .client,
            canEdit: canEdit && !isWorking,
            hasValue: hasClient,
            onEdit: onEditClient,
            onActivate: hasClient ? onOpenClient : nil
        )
        .accessibilityLabel(
            hasClient ? "Client, \(displayName)" : "Client, none set"
        )
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

    // MARK: - ADDRESS

    private var addressRow: some View {
        DocRow(label: "ADDRESS") {
            if let fieldEdit, fieldEdit.isEditing(.address) {
                LeadAddressInlineEditor(controller: fieldEdit)
            } else {
                addressValueLine
            }
        }
    }

    /// Read state. Tap routes; hold corrects. An address the lead never had
    /// takes a plain tap straight into the editor — there are no directions to
    /// protect, and a bare em dash is a poor long-press target.
    @ViewBuilder
    private var addressValueLine: some View {
        let presentation = LeadDetailsAddressPresentation.resolve(lead.address)
        let isRoutable: Bool = {
            if case .routable = presentation { return true }
            return false
        }()

        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(presentation.displayValue)
                .font(OPSStyle.Typography.bodyEmphasis)
                .foregroundColor(isRoutable
                                 ? OPSStyle.Colors.text
                                 : OPSStyle.Colors.textMute)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if isRoutable {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: OPSStyle.Layout.touchTargetMin,
            alignment: .leading
        )
        .holdToEdit(
            .address,
            canEdit: canEdit,
            hasValue: isRoutable,
            onEdit: { fieldEdit?.begin(.address) },
            onActivate: isRoutable ? onOpenAddress : nil
        )
        // The route meaning rides in the LABEL, not a second hint: a trailing
        // `.accessibilityHint` would silently replace the hold hint that
        // `holdToEdit` just published, and the hold is the capability VoiceOver
        // users cannot otherwise reach.
        .accessibilityLabel(
            isRoutable
                ? "Address, \(presentation.displayValue). Opens directions."
                : "Address, none set"
        )
    }

    // MARK: - PROJECT

    private var projectRow: some View {
        DocRow(label: "PROJECT") {
            switch Self.projectRowPresentation(
                projectId: lead.projectId,
                projectName: projectName,
                stage: lead.stage,
                canMatchProject: canMatchProject
            ) {
            case .linked(let label):
                // Row tap keeps its expected meaning: OPEN the committed link.
                Button(action: onOpenProject) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(label)
                            .font(.custom("Mohave-Medium", size: 14))
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .regular))
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: Self.projectActionMinimumHeight,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open project \(label)")
            case .match:
                Button(action: onMatchProject) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "link")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        Text("MATCH PROJECT")
                            .font(OPSStyle.Typography.miniLabelBold)
                            .tracking(0.9)
                            .textCase(.uppercase)
                    }
                    .foregroundColor(OPSStyle.Colors.text2)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous).fill(OPSStyle.Colors.surfaceInput))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                            .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: Self.projectActionMinimumHeight,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Match this lead to an existing project")
            case .empty:
                Text("—")
                    .font(.custom("Mohave-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
    }

    // MARK: - LAST WORD

    /// Latest meaningful correspondence, either party — who spoke last, when,
    /// and about what. Display-only: the full exchange lives in ACTIVITY.
    @ViewBuilder
    private var lastWordRow: some View {
        if let word = correspondence {
            DocRow(label: "LAST WORD") {
                // Same anatomy as CLIENT (value line + meta line): the subject
                // gets the full row width; who-spoke-last + age sit beneath.
                VStack(alignment: .leading, spacing: 6) {
                    Text(word.subject?.trimmingCharacters(in: .whitespaces).isEmpty == false
                         ? word.subject! : "No subject")
                        .font(.custom("Mohave-Medium", size: 14))
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {
                        Image(systemName: word.isInbound ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(word.isInbound ? "THEM" : "YOU") · \(Self.stamp(word.occurredAt))")
                            .font(.custom("JetBrainsMono-Medium", size: 9))
                            .tracking(0.9)
                    }
                    .foregroundColor(word.isInbound ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.text3)
                }
            }
        }
    }

    /// Compact age stamp, same dialect as the chase card's summary band.
    private static func stamp(_ date: Date) -> String {
        let hours = max(Int(Date().timeIntervalSince(date) / 3600), 0)
        if hours < 1 { return "NOW" }
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
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
                    if !attachments.isEmpty {
                        attachmentSummaryLine
                    }
                }
            }
        }
    }

    private var attachmentSummaryLine: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpenAttachments()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: OPSStyle.Icons.documents)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)

                Text(LeadAttachmentPresentation.summary(count: attachments.count))
                    .font(OPSStyle.Typography.bodyEmphasis)
                    .foregroundColor(OPSStyle.Colors.text)

                Spacer(minLength: 0)

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Open \(LeadAttachmentPresentation.summary(count: attachments.count))"
        )
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

}

// MARK: - Document row (58pt mono label column)

struct DocRow<Content: View>: View {
    let label: String

    /// Width of the mono label column. 58 is this document's own column — wide
    /// enough for its longest label — and every caller here uses it. The
    /// project-info document (DetailsTabView) carries a longer label
    /// (DESCRIPTION) and passes its own measured width, so one row anatomy can
    /// serve both surfaces without either one wrapping a label.
    var labelWidth: CGFloat = 58

    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
            Text(label)
                .font(.custom("JetBrainsMono-Medium", size: 8.5))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text3)
                // A field label is a single mono word by construction. Pinning
                // it to one line means a label that outgrows its column fails
                // visibly at the tail instead of silently breaking mid-word —
                // the way DESCRIPTION once wrapped to DESCRIPTIO / N.
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.top, 3)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }
}
