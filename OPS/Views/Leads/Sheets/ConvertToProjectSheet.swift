//
//  ConvertToProjectSheet.swift
//  OPS
//
//  Full-detent sheet that lands when an operator commits to winning a lead.
//  Phase 4 of the LEADS tab rebuild
//  (docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §8.6) — RICH
//  variant. Phase 5 of WON CONVERSION (dedup + auto-naming) switched detection
//  from local SwiftData to the SERVER `get_conversion_preflight` RPC and the
//  project name field to AUTO-named by default.
//
//  Three render states are decided in `task` against the server preflight:
//
//    NORMAL              standard form (auto-named title, address, value, notes)
//                        + optional attached-estimates section + optional
//                        tasks-preview.
//    DUPLICATE-EXISTS    a Project already back-links to this lead (preflight
//                        `existing_linked_project`). We surface the existing
//                        project and let the operator open it; no new project
//                        gets created.
//    CLIENT-HAS-OTHERS   the preflight surfaced likely-duplicate candidates
//                        and/or other client projects. Server-approved duplicate
//                        candidates can be selected for an atomic match; the
//                        remaining projects are review-only.
//
//  Auto-naming (Phase 5): the TITLE defaults to AUTO — the server derives the
//  name from the address via `derive_project_name` (street line before the
//  first comma) and the `projects_autoname` trigger dedups with `#N`. The sheet
//  shows the derived name and a LIVE preview as the operator edits the address;
//  a quiet RENAME affordance reveals a hand-edit field (sets title_is_auto =
//  false). When auto, the operator never types a name.
//
//  Exit semantics:
//
//    The canonical guarded RPC always creates or links a project. Closing or
//    cancelling this sheet therefore leaves the lead unchanged. CREATE PROJECT
//    and OPEN PROJECT are the only committing exits, and both pin the lead's
//    stage plus assignment version in the same atomic conversion transaction.
//

import SwiftUI
import SwiftData

struct ConvertToProjectSheet: View {
    let opportunity: Opportunity

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var conversionVisibilityStore = LeadConversionVisibilityStore.shared
    @Environment(\.modelContext) private var modelContext

    // MARK: - Form state

    @State private var titleText: String = ""
    @State private var addressText: String = ""
    /// True while `addressText` still holds the value borrowed from the linked
    /// client record. The field TAGS it: the create path persists whatever is
    /// visible back onto the opportunity, so the operator has to be able to see
    /// where it came from before they commit (bug a7df1f37).
    @State private var addressIsFromClient = false
    @State private var prefilledLatitude: Double?
    @State private var prefilledLongitude: Double?
    /// The lead's linked client, resolved once during preflight. Supplies the
    /// address and contact fallbacks.
    @State private var linkedClient: Client?
    @State private var actualValueText: String = ""
    @State private var closingNotes: String = ""

    /// Server-derived base name (`derive_project_name(address, client)`), no
    /// `#N` dedup suffix. Captured from the preflight; used as the live-preview
    /// fallback and the auto-name shown before the operator touches anything.
    @State private var suggestedName: String = ""
    /// TITLE defaults to AUTO. Flipped false the moment the operator opens
    /// RENAME and types a name; flipped back true via USE ADDRESS.
    @State private var titleIsAuto: Bool = true
    /// Whether the hand-edit name input is revealed.
    @State private var isRenaming: Bool = false

    @FocusState private var nameFieldFocused: Bool

    // MARK: - Pre-flight state

    /// Non-nil ⇒ DUPLICATE-EXISTS. The id always comes from the server
    /// preflight; the rich card detail is hydrated best-effort (network → local
    /// SwiftData → preflight title-only) so the sheet never crashes offline.
    @State private var existingProject: DuplicateProjectDisplay?
    /// Merged candidate + other-client refs (dedup by id, candidates first).
    @State private var clientOtherProjects: [RelatedProjectRef] = []
    /// Only server-approved duplicate candidates may populate this value. The
    /// final CTA passes it to the guarded conversion RPC; merely tapping a chip
    /// never commits or mutates either row.
    @State private var selectedExistingProjectId: String?
    /// A target rejected by the row-locked conversion must not immediately
    /// return as an actionable MATCH from the same preflight contract.
    @State private var unavailableMatchProjectIds: Set<String> = []
    @State private var estimateBundles: [LeadConversionService.EstimateBundle] = []
    @State private var hasLoadedPreflight = false
    @State private var preflightFailed = false
    /// Server-authored reason a nil-target CREATE cannot safely proceed even
    /// though there is no selectable MATCH candidate on screen.
    @State private var creationBlocker: ConversionPreflightCreationBlocker?
    @State private var requiresMatchReviewRefresh = false
    @State private var verifiedCreateAddressFingerprint: String?
    @State private var pendingCreateAddressFingerprint: String?
    @State private var initialClientAddressRecheckGate =
        InitialClientAddressRecheckGate()
    /// A hidden linked project must be verified through the guarded conversion
    /// RPC before the client may present a committed win. While this flag is
    /// set, the sheet exposes no create/retry action.
    @State private var hiddenConversionRecoveryDetected = false
    /// The candidate link re-read failed on its own. Reported in the chip area
    /// — it is NOT a preflight failure and must not close the sheet's only
    /// committing action (bug 5468b3c6, H7).
    @State private var candidateLinkCheckFailed = false
    /// Honest one-liner about why nothing on screen is matchable.
    @State private var chipNotice: String?
    /// The project being peeked at, layered over this sheet. Never a dismissal.
    @State private var peekProject: RelatedProjectRef?

    // MARK: - Operation state

    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: - Computed

    private var renderState: RenderState {
        if existingProject != nil { return .duplicate }
        if !clientOtherProjects.isEmpty { return .clientHasOthers }
        return .normal
    }

    private var canSubmit: Bool {
        Self.canCommitConversion(
            hasLoadedPreflight: hasLoadedPreflight,
            preflightFailed: preflightFailed,
            isSaving: isSaving,
            requiresMatchReviewRefresh: requiresMatchReviewRefresh,
            hasLikelyDuplicate: hasLikelyDuplicate,
            hasSelectedMatch: selectedExistingProjectId != nil,
            creationBlocker: creationBlocker
        )
    }

    private var hasLikelyDuplicate: Bool {
        clientOtherProjects.contains(where: \.isLikelyDuplicate)
    }

    private var primaryActionLabel: String {
        hasLikelyDuplicate && selectedExistingProjectId == nil
            ? "SELECT PROJECT"
            : submissionTarget.primaryLabel
    }

    private var submissionTarget: SubmissionTarget {
        SubmissionTarget(selectedProjectId: selectedExistingProjectId)
    }

    private var totalLaborItems: Int {
        estimateBundles.reduce(0) { $0 + $1.laborItems.count }
    }

    /// The street line the address resolves to, mirroring the server's
    /// `derive_project_name` via ProjectAutoNamer (comma split, plus the
    /// civic-number + street-suffix extraction for comma-less hand-typed
    /// addresses). Falls back to the server `suggested_name`, then to a
    /// neutral placeholder.
    private var derivedNamePreview: String {
        let trimmedAddress = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAddress.isEmpty,
           let streetLine = ProjectAutoNamer.streetLine(from: trimmedAddress) {
            return streetLine
        }
        let trimmedSuggested = suggestedName.trimmingCharacters(in: .whitespaces)
        if !trimmedSuggested.isEmpty { return trimmedSuggested }
        return "New project"
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        leadSummaryCard

                        if renderState == .duplicate, let existing = existingProject {
                            duplicateCard(existing: existing)
                        } else {
                            if renderState == .clientHasOthers {
                                clientOthersBanner
                            }
                            formFields
                            if !estimateBundles.isEmpty {
                                attachedEstimatesSection
                            }
                            if totalLaborItems > 0 {
                                tasksPreviewSection
                            }
                            provenanceFooter
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .padding(.bottom, 160)
                }
                .scrollIndicators(.hidden)
            }

            footerOverlay
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSaving)
        .sheet(item: $peekProject) { project in
            ProjectPeekSheet(
                projectId: project.id,
                fallbackTitle: project.title,
                fallbackAddress: project.address,
                linkNote: peekNote(for: project),
                companyId: opportunity.companyId,
                onOpenProject: { projectId in
                    peekProject = nil
                    openProjectLeavingConversion(projectId)
                }
            )
            .environmentObject(dataController)
            // A quick look, not a destination — the half detent keeps the
            // conversion visibly underneath.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            let recoveredCommittedConversion = await Self.runInitialLoad(
                resolveLinkedClient: {
                    await resolveLinkedClient()
                },
                applyAddressPrefill: {
                    applyInitialAddressPrefill()
                },
                loadPreflight: {
                    await loadPreflight()
                }
            )
            guard !recoveredCommittedConversion else { return }
            applyInitialFinancialValue()
        }
    }

    /// What the peek should say about this project's relationship to the lead.
    private func peekNote(for project: RelatedProjectRef) -> String? {
        switch project.linkState {
        case .matchable:
            return "Same address as this lead. Selecting it links the lead to this project instead of creating a new one."
        case .linkedElsewhere:
            return "Same address as this lead, but already linked to a different lead. It cannot be matched until that link is resolved."
        case .unverified:
            return "Same address as this lead. Its link could not be checked just now."
        case .unavailable:
            return "This project was rejected as a match during the last attempt."
        case .reviewOnly:
            return "This project can be reviewed here but is not available to link."
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            SheetTitleLabel(title: "CONVERT → PROJECT", size: .full)
            SheetCloseButton { dismiss() }
        }
        .padding(.leading, OPSStyle.Layout.spacing3_5)
        .padding(.trailing, 6)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    // MARK: - Lead summary card

    /// Contact identity for the card, falling back to the linked client so a
    /// lead created from a client page never shows a bare em dash.
    private var summaryContact: LeadSummaryContact {
        Self.leadSummaryContact(
            opportunityName: opportunity.contactName,
            opportunityPhone: opportunity.contactPhone,
            clientName: linkedClient?.name,
            clientPhone: linkedClient?.phoneNumber
        )
    }

    private var leadSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("FROM WON LEAD")
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
            }
            .font(OPSStyle.Typography.miniLabelBold)
            .kerning(1.6)
            .textCase(.uppercase)

            Text(summaryContact.name)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(opportunity.shortDisplayId)
                    .monospacedDigit()
                if let phone = summaryContact.phone {
                    Text("·")
                    Text(phone)
                }
            }
            .font(OPSStyle.Typography.miniLabel)
            .kerning(1.2)
            .foregroundColor(OPSStyle.Colors.text3)
            .textCase(.uppercase)

            if let address = opportunity.address, !address.isEmpty {
                Text(address)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .commandCard()
    }

    // MARK: - Duplicate state

    private func duplicateCard(existing: DuplicateProjectDisplay) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("PROJECT ALREADY EXISTS")
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
                if let created = existing.createdAt {
                    Text("  ·  ")
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text(relativeText(for: created).uppercased())
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
            .font(OPSStyle.Typography.miniLabelBold)
            .kerning(1.6)
            .textCase(.uppercase)

            Text(existing.title.isEmpty ? "Untitled project" : existing.title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let status = existing.status {
                    StatusBadge(
                        status: status.displayName.uppercased(),
                        color: status.color,
                        size: .small
                    )
                }
                if let address = existing.address, !address.isEmpty {
                    Text(address)
                        .font(OPSStyle.Typography.miniLabel)
                        .kerning(1.0)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                        .textCase(.uppercase)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                .fill(OPSStyle.Colors.oliveFillM)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.oliveLineM, lineWidth: 1)
        )
    }

    // MARK: - Client-has-others banner

    private var clientOthersBanner: some View {
        ClientOthersBanner(
            projects: clientOtherProjects,
            selectedProjectId: selectedExistingProjectId,
            onPeek: { peekProject = $0 },
            onMatch: selectExistingProject,
            notice: chipNotice
        )
    }

    /// Tan attention banner for the CLIENT-HAS-OTHERS render state. Extracted
    /// as its own view so the snapshot harness can render it against fixture
    /// counts (bug 4e11e121 — the old header wrapped onto multiple lines).
    struct ClientOthersBanner: View {
        let projects: [RelatedProjectRef]
        let selectedProjectId: String?
        /// Opens a read-only peek LAYERED over the convert sheet. It never
        /// dismisses or navigates — form state is sacred here.
        let onPeek: (RelatedProjectRef) -> Void
        let onMatch: (String) -> Void
        /// One honest line about why nothing is matchable, rendered inside the
        /// chip area where the problem actually lives.
        var notice: String? = nil

        /// `CLIENT HAS 02 OTHER PROJECTS` — one message, count zero-padded to
        /// match the mono HUD style. The old header also carried "REVIEW
        /// BEFORE CREATING", which pushed the line past every phone width and
        /// fragment-wrapped (bug 4e11e121); the tan tint + tappable chips
        /// already carry the review intent.
        private var headline: String {
            let count = projects.count
            let noun = count == 1 ? "PROJECT" : "PROJECTS"
            return "CLIENT HAS \(String(format: "%02d", count)) OTHER \(noun)"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                // Single concatenated text run + lineLimit(1): the header can
                // never fragment-wrap again, at any count.
                (
                    Text("// ")
                        .foregroundColor(OPSStyle.Colors.textMute)
                    + Text(headline)
                        .foregroundColor(OPSStyle.Colors.tanTextM)
                )
                .font(OPSStyle.Typography.miniLabelBold)
                .kerning(1.6)
                .textCase(.uppercase)
                .lineLimit(1)

                ChipWrap(spacing: 6) {
                    ForEach(projects.prefix(8)) { project in
                        projectChip(project)
                    }
                }

                if let notice {
                    Text(notice)
                        .font(OPSStyle.Typography.miniLabel)
                        .kerning(1.0)
                        .foregroundColor(OPSStyle.Colors.tanTextM)
                        .textCase(.uppercase)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .fill(OPSStyle.Colors.tanFillM)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.tanLineM, lineWidth: 1)
            )
        }

        /// A chip is two controls, not one. The BODY carries the chip's
        /// meaning — select it (matchable) or look at it (everything else) —
        /// and the trailing control always opens the peek, so an operator
        /// mid-selection can still inspect what they are about to match
        /// without losing the selection or the form.
        private func projectChip(_ project: RelatedProjectRef) -> some View {
            let isSelected = selectedProjectId == project.id && project.interaction == .match

            return HStack(spacing: 0) {
                Button {
                    switch project.interaction {
                    case .match: onMatch(project.id)
                    case .peek:  onPeek(project)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(project.statusColor)
                            .frame(width: 5, height: 5)
                        Text(truncatedTitle(project.title))
                            .font(OPSStyle.Typography.miniLabelBold)
                            .kerning(1.2)
                            .foregroundColor(OPSStyle.Colors.text)
                            .textCase(.uppercase)
                        if let actionLabel = project.actionLabel {
                            Text("·")
                                .foregroundColor(OPSStyle.Colors.textMute)
                            if isSelected {
                                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                                    .foregroundColor(OPSStyle.Colors.oliveTextM)
                            }
                            Text(isSelected ? "SELECTED" : actionLabel)
                                .font(OPSStyle.Typography.miniLabel)
                                .kerning(1.0)
                                .foregroundColor(labelColor(for: project, isSelected: isSelected))
                                .textCase(.uppercase)
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, project.interaction == .match ? 6 : 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(accessibilityLabel(for: project))

                // Selecting and inspecting are different intents, so a
                // matchable chip gets its own peek control rather than
                // overloading the tap.
                if project.interaction == .match {
                    Rectangle()
                        .fill(OPSStyle.Colors.line)
                        .frame(width: 1, height: 16)
                    Button {
                        onPeek(project)
                    } label: {
                        Image(systemName: OPSStyle.Icons.magnifyingglass)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.text3)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Quick view project \(project.title)")
                }
            }
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(isSelected ? OPSStyle.Colors.oliveFillM : OPSStyle.Colors.surfaceHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(isSelected ? OPSStyle.Colors.oliveLineM : OPSStyle.Colors.line, lineWidth: 1)
            )
        }

        private func labelColor(
            for project: RelatedProjectRef,
            isSelected: Bool
        ) -> Color {
            if isSelected { return OPSStyle.Colors.oliveTextM }
            switch project.linkState {
            case .matchable:                     return OPSStyle.Colors.tanTextM
            case .linkedElsewhere, .unavailable,
                 .unverified, .reviewOnly:       return OPSStyle.Colors.text3
            }
        }

        private func accessibilityLabel(for project: RelatedProjectRef) -> String {
            switch project.linkState {
            case .matchable:
                return selectedProjectId == project.id
                    ? "Selected project \(project.title) for matching"
                    : "Match lead to project \(project.title)"
            case .linkedElsewhere:
                return "Project \(project.title) is already linked to another lead. Quick view."
            case .unverified:
                return "Project \(project.title) link state unknown. Quick view."
            case .unavailable:
                return "Project \(project.title) is unavailable to match. Quick view."
            case .reviewOnly:
                return "Quick view project \(project.title)"
            }
        }

        private func truncatedTitle(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return "UNTITLED" }
            return trimmed.count > 18 ? String(trimmed.prefix(17)) + "…" : trimmed
        }
    }

    // MARK: - Form fields

    /// `[FROM CLIENT]` reuses the field-hint grammar already on this sheet
    /// (`[AUTO]`, `[REQUIRED]`, `[OPTIONAL]`) rather than inventing a badge.
    /// It outranks `[OPTIONAL]` because provenance is the more useful fact;
    /// `[REQUIRED]` still wins, since a blocked field is more urgent.
    private var addressHint: String {
        if creationBlocker == .addressRequired { return "[REQUIRED]" }
        if addressIsFromClient { return "[FROM CLIENT]" }
        return "[OPTIONAL]"
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            if submissionTarget.showsProjectIdentityFields {
                nameField

                LeadField(label: "ADDRESS", hint: addressHint) {
                    LeadTextInput(
                        placeholder: "3185 Fairview Rd",
                        text: $addressText,
                        textContentType: .fullStreetAddress
                    )
                    .onChange(of: addressText) { _, _ in
                        // The tag claims provenance. The moment the operator
                        // edits the value, the claim stops being true.
                        if addressIsFromClient {
                            addressIsFromClient = false
                            prefilledLatitude = nil
                            prefilledLongitude = nil
                        }
                    }
                }
            }

            LeadField(label: "ACTUAL VALUE", hint: "[FINAL, NOT ESTIMATE]") {
                LeadTextInput(
                    placeholder: "14,200",
                    text: $actualValueText,
                    keyboard: .decimalPad,
                    leading: "$"
                )
            }

            LeadField(label: "CLOSING NOTES", hint: "[OPTIONAL]") {
                LeadTextArea(
                    placeholder: "Anything the project team should know to start clean.",
                    text: $closingNotes,
                    rows: 3
                )
            }
        }
        .disabled(isSaving)
    }

    // MARK: - Name field (auto-named by default)

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("NAME")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .textCase(.uppercase)
                Text(titleIsAuto ? "[AUTO]" : "[CUSTOM]")
                    .font(OPSStyle.Typography.miniLabel)
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)

                Spacer()

                nameModeToggle
            }

            if titleIsAuto {
                autoNamePreview
            } else {
                LeadTextInput(
                    placeholder: derivedNamePreview,
                    text: $titleText
                )
                .focused($nameFieldFocused)
            }
        }
    }

    /// The RENAME / USE ADDRESS toggle. ≥44pt hit area, OPSStyle-styled, quiet.
    private var nameModeToggle: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if titleIsAuto {
                // Reveal hand-edit. Seed the field with the current derived
                // name so the operator edits FROM the auto value rather than a
                // blank, and flip to custom the moment they engage.
                titleIsAuto = false
                isRenaming = true
                if titleText.trimmingCharacters(in: .whitespaces).isEmpty {
                    titleText = derivedNamePreview
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    nameFieldFocused = true
                }
            } else {
                // Revert to auto — clear the custom title, hide the field.
                titleIsAuto = true
                isRenaming = false
                titleText = ""
                nameFieldFocused = false
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: titleIsAuto ? OPSStyle.Icons.edit : OPSStyle.Icons.locationFill)
                    .font(.system(size: 10))
                Text(titleIsAuto ? "RENAME" : "USE ADDRESS")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .kerning(1.2)
            }
            .foregroundColor(OPSStyle.Colors.text2)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(titleIsAuto ? "Rename project" : "Use address for project name")
    }

    /// Quiet auto-name preview line shown in place of the input when AUTO.
    private var autoNamePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("NAME · ")
                    .foregroundColor(OPSStyle.Colors.text3)
                Text(derivedNamePreview.uppercased())
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .font(.custom("JetBrainsMono-Medium", size: 11))
            .kerning(1.0)
            .lineLimit(1)
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )

            Text("Auto-named from the site address. Rename anytime.")
                .font(OPSStyle.Typography.miniLabel)
                .kerning(0.4)
                .foregroundColor(OPSStyle.Colors.textMute)
                .lineLimit(2)
        }
    }

    // MARK: - Attached estimates

    private var attachedEstimatesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            PanelSectionHeader(
                label: "ATTACHED ESTIMATES",
                count: estimateBundles.count
            )

            VStack(spacing: 6) {
                ForEach(estimateBundles, id: \.estimate.id) { bundle in
                    estimateRow(bundle: bundle)
                }
            }
        }
    }

    private func estimateRow(bundle: LeadConversionService.EstimateBundle) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(bundle.estimate.estimateNumber.isEmpty
                     ? bundle.estimate.title?.uppercased() ?? "—"
                     : bundle.estimate.estimateNumber.uppercased())
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .kerning(1.0)
                    .foregroundColor(OPSStyle.Colors.text)

                HStack(spacing: 6) {
                    Text(bundle.estimate.status.displayName)
                    Text("·")
                    Text("\(String(format: "%02d", bundle.lineItems.count)) ITEMS")
                }
                .font(OPSStyle.Typography.miniLabel)
                .kerning(1.0)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)
            }

            Spacer()

            Text(BooksFormat.currency(bundle.estimate.total))
                .font(.custom("JetBrainsMono-Medium", size: 13))
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity)
        .nestedCard()
    }

    // MARK: - Tasks preview

    private var tasksPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSectionHeader(
                label: "TASKS TO BE CREATED",
                count: totalLaborItems
            )

            VStack(spacing: 6) {
                ForEach(allLaborItems, id: \.id) { item in
                    taskPreviewRow(item)
                }
            }

            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("\(String(format: "%02d", totalLaborItems)) ")
                    .foregroundColor(OPSStyle.Colors.text3)
                Text("TASKS WILL BE CREATED FROM ")
                    .foregroundColor(OPSStyle.Colors.text3)
                Text("\(String(format: "%02d", estimateBundles.count)) ")
                    .foregroundColor(OPSStyle.Colors.text3)
                Text(estimateBundles.count == 1 ? "ESTIMATE" : "ESTIMATES")
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(OPSStyle.Typography.miniLabel)
            .kerning(1.4)
            .textCase(.uppercase)
            .padding(.top, OPSStyle.Layout.spacing1)
        }
    }

    private var allLaborItems: [EstimateLineItem] {
        estimateBundles.flatMap { $0.laborItems }
    }

    private func taskPreviewRow(_ item: EstimateLineItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(item.name.isEmpty ? "—" : item.name)
                    .font(.custom("Mohave-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("LABOR")
                    if let unit = item.unit, !unit.isEmpty {
                        Text("·")
                        Text("\(formatQty(item.quantity)) \(unit.uppercased())")
                    } else if item.quantity != 1 {
                        Text("·")
                        Text("\(formatQty(item.quantity))")
                    }
                }
                .font(OPSStyle.Typography.miniLabel)
                .kerning(1.0)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)
            }

            Spacer()
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity)
        .nestedCard()
    }

    private func formatQty(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    // MARK: - Provenance footer

    private var provenanceFooter: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(provenanceText)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .font(OPSStyle.Typography.miniLabel)
        .kerning(0.4)
        .lineSpacing(2)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
    }

    private var provenanceText: String {
        if submissionTarget.linkToProjectId != nil {
            return "Marks the lead WON and links it to the selected Project. Existing project details stay unchanged."
        }
        return "Marks the lead WON and creates a Project (status: ACCEPTED) linked back to this lead. Finish project setup from the PROJECTS tab."
    }

    // MARK: - Footer

    private var footerOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            if let errorMessage {
                SheetStatusLine(mode: .error(errorMessage))
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else if isSaving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }

            if hiddenConversionRecoveryDetected {
                SheetCTAButton(
                    label: isSaving ? "VERIFYING" : "CLOSE",
                    variant: .primary,
                    isLoading: isSaving,
                    action: { dismiss() }
                )
                .disabled(isSaving)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 28)
            } else {
                SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { dismiss() }
                )
                .disabled(isSaving)
            } primary: {
                if !hasLoadedPreflight {
                    SheetCTAButton(
                        label: "CHECKING PROJECTS",
                        variant: .primary,
                        isLoading: true,
                        action: {}
                    )
                    .disabled(true)
                } else if preflightFailed {
                    SheetCTAButton(
                        label: "RETRY CHECK",
                        icon: "arrow.clockwise",
                        variant: .primary,
                        isLoading: isSaving,
                        action: retryPreflight
                    )
                    .disabled(isSaving)
                } else if renderState == .duplicate {
                    SheetCTAButton(
                        label: "OPEN PROJECT",
                        icon: "arrow.right",
                        variant: .primary,
                        isLoading: isSaving,
                        action: { openExistingProjectAction() }
                    )
                    .disabled(isSaving)
                } else if creationBlocker == .addressRequired {
                    let hasAddress = !Self.createAddressFingerprint(addressText).isEmpty
                    SheetCTAButton(
                        label: hasAddress ? "CHECK ADDRESS" : "ADD ADDRESS",
                        icon: hasAddress ? "arrow.right" : nil,
                        variant: .primary,
                        isLoading: isSaving,
                        action: checkRequiredAddress
                    )
                    .disabled(isSaving || !hasAddress)
                    .opacity(hasAddress ? 1 : 0.5)
                } else if creationBlocker == .projectReviewRequired {
                    SheetCTAButton(
                        label: "ADMIN ACCESS NEEDED",
                        variant: .primary,
                        action: {}
                    )
                    .disabled(true)
                    .opacity(0.5)
                } else {
                    SheetCTAButton(
                        label: primaryActionLabel,
                        icon: "arrow.right",
                        variant: .primary,
                        isLoading: isSaving,
                        action: commitConversion
                    )
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)
                }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 28)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.95),
                    .black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false),
            alignment: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Pre-flight load

    @discardableResult
    private func loadPreflight() async -> Bool {
        guard !hasLoadedPreflight else { return false }
        let companyId = opportunity.companyId
        let service = LeadConversionService(companyId: companyId, modelContext: modelContext)
        preflightFailed = false
        creationBlocker = nil
        errorMessage = nil
        candidateLinkCheckFailed = false
        chipNotice = nil

        var shouldAutomaticallyRecheckClientAddress = false

        // SERVER preflight — single source of truth for render state + suggested
        // name. Replaces the prior local SwiftData duplicate/other-projects
        // checks. Commit stays closed until this succeeds: the human nil-link
        // create path does not auto-dedupe when preflight is unavailable.
        do {
            let preflight = try await service.getConversionPreflight(for: opportunity)
            suggestedName = preflight.suggestedName ?? ""

            if preflight.isCommittedWithoutAccessibleProject {
                preflightFailed = false
                hasLoadedPreflight = true
                hiddenConversionRecoveryDetected = true
                return await verifyHiddenCommittedConversion(
                    service: service,
                    preflight: preflight
                )
            }

            // Access can legitimately change later. A successful accessible
            // preflight clears any durable hidden-conversion presentation mark.
            if preflight.alreadyConverted && preflight.projectAccessible {
                conversionVisibilityStore.clear(opportunity.id)
            }

            if let linked = preflight.existingLinkedProject {
                existingProject = await resolveDuplicateDisplay(
                    id: linked.id,
                    fallbackTitle: linked.title
                )
            }

            // Bug 5468b3c6 (H7) — this read gets its OWN error handling. It
            // used to share the preflight's `do`, so a transient failure of
            // the candidate re-read reported as "COULD NOT CHECK PROJECTS"
            // and closed the sheet's only committing action, even though the
            // authoritative preflight had already succeeded.
            var matchableCandidateIds: Set<String> = []
            var manualCandidates: [ManualProjectLinkCandidate] = []
            do {
                manualCandidates = try await service.manualProjectLinkCandidates(
                    for: opportunity
                )
                matchableCandidateIds = Set(
                    manualCandidates.map { $0.projectId.lowercased() }
                )
            } catch {
                // The new complete-manual-list RPC may not be deployed yet.
                // Preserve the proven same-address path as a compatibility
                // fallback, but report that the complete link list could not
                // be checked.
                candidateLinkCheckFailed = true
                do {
                    matchableCandidateIds = try await service
                        .matchableCandidateProjectIds(
                            for: opportunity,
                            candidates: preflight.duplicateCandidates
                        )
                } catch {
                    matchableCandidateIds = []
                }
            }

            let state = Self.reducePreflight(
                preflight,
                matchableCandidateIds: matchableCandidateIds,
                candidateLinkCheckFailed: candidateLinkCheckFailed,
                unavailableMatchProjectIds: unavailableMatchProjectIds,
                manualCandidates: manualCandidates
            )
            creationBlocker = state.creationBlocker
            clientOtherProjects = state.refs
            chipNotice = state.refs.isEmpty ? nil : state.statusMessage
            errorMessage = state.refs.isEmpty ? state.statusMessage : nil
            preflightFailed = false
            shouldAutomaticallyRecheckClientAddress =
                initialClientAddressRecheckGate.consume(
                    creationBlocker: creationBlocker,
                    address: addressText,
                    isFromClient: addressIsFromClient
                )
        } catch {
            // Fail closed. RETRY CHECK is the only committing footer action
            // until the authoritative preflight read passes.
            preflightFailed = true
            suggestedName = ""
            errorMessage = "COULD NOT CHECK PROJECTS — RETRY"
        }

        if shouldAutomaticallyRecheckClientAddress {
            do {
                return try await stopForCreateAddressRecheckIfNeeded(
                    companyId: companyId
                )
            } catch {
                // The authoritative preflight succeeded. Keep its blocker and
                // the borrowed address visible so the operator can retry the
                // existing CHECK ADDRESS action without retyping anything.
                errorMessage = simplifyError(error)
            }
        }

        // Network fetch (estimates + line items) — still drives the tasks preview.
        do {
            estimateBundles = try await service.estimateBundles(for: opportunity)
        } catch {
            // Non-fatal — operator can still create without the preview
            estimateBundles = []
        }

        hasLoadedPreflight = true
        return false
    }

    /// Hydrate the rich DUPLICATE-EXISTS card. Network first (canonical), then
    /// local SwiftData by id, then a title-only fallback from the preflight so
    /// the sheet never crashes offline.
    private func resolveDuplicateDisplay(id: String, fallbackTitle: String?) async -> DuplicateProjectDisplay {
        let repo = ProjectRepository(companyId: opportunity.companyId)
        if let dto = try? await repo.fetchOne(id) {
            let model = dto.toModel()
            return DuplicateProjectDisplay(
                id: model.id,
                title: model.title,
                address: model.address,
                status: model.status,
                createdAt: model.createdAt
            )
        }

        let localId = id
        var descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == localId }
        )
        descriptor.fetchLimit = 1
        if let local = (try? modelContext.fetch(descriptor))?.first {
            return DuplicateProjectDisplay(
                id: local.id,
                title: local.title,
                address: local.address,
                status: local.status,
                createdAt: local.createdAt
            )
        }

        return DuplicateProjectDisplay(
            id: id,
            title: fallbackTitle ?? "",
            address: nil,
            status: nil,
            createdAt: nil
        )
    }

    /// Resolves the lead's linked client from the local store, then the
    /// repository. The client record holds the address and contact details a
    /// client-page lead never got its own copy of (bug a7df1f37).
    private func resolveLinkedClient() async {
        guard linkedClient == nil else { return }

        linkedClient = await Self.resolveLinkedClientValue(
            clientId: opportunity.clientId,
            local: { clientId in
                var descriptor = FetchDescriptor<Client>(
                    predicate: #Predicate<Client> { $0.id == clientId }
                )
                descriptor.fetchLimit = 1
                guard let local = (try? modelContext.fetch(descriptor))?.first,
                      local.companyId == opportunity.companyId else {
                    return nil
                }
                return local
            },
            remote: { clientId in
                let repository = ClientRepository(companyId: opportunity.companyId)
                let dto = try await repository.fetchOne(clientId)
                guard dto.companyId == opportunity.companyId else {
                    throw LinkedClientResolutionError.tenantMismatch
                }
                return dto.toModel()
            }
        )
    }

    private func applyInitialAddressPrefill() {
        if addressText.isEmpty {
            let prefill = Self.addressPrefill(
                opportunityAddress: opportunity.address,
                opportunityLatitude: opportunity.latitude,
                opportunityLongitude: opportunity.longitude,
                clientAddress: linkedClient?.address,
                clientLatitude: linkedClient?.latitude,
                clientLongitude: linkedClient?.longitude
            )
            addressText = prefill.text
            prefilledLatitude = prefill.latitude
            prefilledLongitude = prefill.longitude
            addressIsFromClient = prefill.isFromClient
        }
    }

    private func applyInitialFinancialValue() {
        if actualValueText.isEmpty {
            let prefillValue = estimateBundles.first?.estimate.total
                ?? opportunity.estimatedValue
            if let v = prefillValue, v > 0 {
                actualValueText = LeadForm.formatValueInput(v)
            }
        }
    }

    // MARK: - Actions

    private func commitConversion() {
        guard canSubmit else { return }
        let target = submissionTarget
        errorMessage = nil
        isSaving = true

        Task {
            do {
                let companyId = opportunity.companyId
                let service = LeadConversionService(companyId: companyId, modelContext: modelContext)

                // A create commits only against the exact address the server
                // just checked. The first create attempt persists the visible
                // address and re-runs preflight; later edits invalidate that
                // proof. Matching never rewrites project identity fields.
                if target.linkToProjectId == nil,
                   try await stopForCreateAddressRecheckIfNeeded(companyId: companyId) {
                    isSaving = false
                    return
                }

                let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                let outcome = try await service.convertOpportunityToProject(
                    lead: opportunity,
                    actualValue: parseActualValue(),
                    titleOverride: target.linkToProjectId == nil && !titleIsAuto
                        ? (trimmedTitle.isEmpty ? nil : trimmedTitle)
                        : nil,
                    notes: closingNotes.isEmpty ? nil : closingNotes,
                    linkToProjectId: target.linkToProjectId,
                    userId: dataController.currentUser?.id
                )

                switch outcome {
                case .project(let project):
                    completeConverted(projectId: project.id)
                case .committedWithKnownProject(let projectId):
                    // The server named the project; only hydration failed.
                    // Keeping the link is the whole fix for ced5b3cb-B.
                    completeConverted(projectId: projectId)
                case .committedWithoutAccessibleProject:
                    completeConvertedWithoutAccessibleProject()
                }
            } catch {
                if let conversionError = error as? LeadConversionError,
                   case .projectLinkUnavailable = conversionError {
                    let recovered = await refreshPreflightAfterLinkFailure(
                        failedProjectId: target.linkToProjectId
                    )
                    if recovered { return }
                }
                isSaving = false
                errorMessage = simplifyError(error, target: target)
            }
        }
    }

    /// A blank-address blocker is resolved in place: persist the operator's
    /// address, rerun the authoritative preflight, then reveal CREATE or MATCH.
    /// This action never invokes the conversion RPC itself.
    private func checkRequiredAddress() {
        guard creationBlocker == .addressRequired,
              !Self.createAddressFingerprint(addressText).isEmpty,
              !isSaving else { return }

        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await stopForCreateAddressRecheckIfNeeded(
                    companyId: opportunity.companyId
                )
            } catch {
                errorMessage = simplifyError(error)
            }
            isSaving = false
        }
    }

    private func completeConverted(projectId: String) {
        conversionVisibilityStore.clear(opportunity.id)
        opportunity.stage = .won
        opportunity.actualValue = parseActualValue()
        opportunity.actualCloseDate = Date()
        opportunity.projectId = projectId
        opportunity.stageEnteredAt = Date()
        opportunity.stageManuallySet = true

        applyPendingSiteVisitHandoff(projectId: projectId)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(
            name: Notification.Name("LeadConvertedSuccess"),
            object: nil,
            userInfo: [
                "leadId": opportunity.id,
                "projectId": projectId,
            ]
        )
        // Operator stays on the LEADS queue — the success toast carries the
        // tap-through to the new project (P3-2 / PM).
        dismiss()
    }

    private func completeConvertedWithoutAccessibleProject() {
        conversionVisibilityStore.markCommittedWithoutAccessibleProject(opportunity.id)
        opportunity.stage = .won
        opportunity.actualValue = parseActualValue()
        opportunity.actualCloseDate = Date()
        opportunity.projectId = nil
        opportunity.stageEnteredAt = Date()
        opportunity.stageManuallySet = true

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(
            name: Notification.Name("LeadMarkedWonSuccess"),
            object: nil,
            userInfo: [
                "leadId": opportunity.id,
                "projectCommitted": true,
                "projectAccessible": false,
            ]
        )
        // Close only the conversion sheet. The operator remains on the won
        // lead; no inaccessible project identity is exposed for navigation.
        dismiss()
    }

    /// A preflight link alone does not prove the lead reached WON. Re-enter
    /// the canonical row-locked conversion with the exact stage and assignment
    /// snapshot that opened this sheet, and present success only after its
    /// result proves the won commit. The project identity is discarded even if
    /// access becomes available during the check.
    @discardableResult
    private func verifyHiddenCommittedConversion(
        service: LeadConversionService,
        preflight: ConversionPreflight
    ) async -> Bool {
        isSaving = true
        errorMessage = nil

        guard preflight.assignmentVersion == nil
                || preflight.assignmentVersion == opportunity.assignmentVersion else {
            isSaving = false
            errorMessage = simplifyError(LeadConversionError.assignmentChanged)
            return false
        }

        do {
            _ = try await service.convertOpportunityToProject(
                lead: opportunity,
                actualValue: opportunity.actualValue,
                titleOverride: nil,
                notes: nil,
                linkToProjectId: nil,
                userId: dataController.currentUser?.id,
                // Preflight proved only that a project link exists. Pin WON
                // under the row lock so a genuinely committed conversion can
                // recover even when the local cache still shows the old stage,
                // while an inconsistent non-WON linked row fails closed.
                expectedStage: PipelineStage.won.rawValue,
                expectedAssignmentVersion: opportunity.assignmentVersion
            )
            completeVerifiedHiddenConversion()
            return true
        } catch {
            isSaving = false
            errorMessage = simplifyError(error)
            return false
        }
    }

    private func completeVerifiedHiddenConversion() {
        conversionVisibilityStore.markCommittedWithoutAccessibleProject(opportunity.id)
        opportunity.stage = .won
        opportunity.projectId = nil

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        NotificationCenter.default.post(
            name: Notification.Name("LeadMarkedWonSuccess"),
            object: nil,
            userInfo: [
                "leadId": opportunity.id,
                "projectCommitted": true,
                "projectAccessible": false,
            ]
        )
        // The row-locked conversion proved the won commit. Close immediately
        // and stay on the won lead; never reveal or navigate to a project id.
        dismiss()
    }

    private func applyPendingSiteVisitHandoff(projectId: String) {
        if let payload = SiteVisitProjectHandoffStore.shared.consume(for: opportunity.id) {
            let siteVisitId = payload.siteVisitId
            let descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
                predicate: #Predicate<SiteVisitCaptureArtifact> { artifact in
                    artifact.siteVisitId == siteVisitId
                },
                sortBy: [SortDescriptor(\.capturedAt, order: .forward)]
            )
            let artifacts = (try? modelContext.fetch(descriptor)) ?? []
            SiteVisitProjectHandoff.apply(
                payload: payload,
                artifacts: artifacts,
                projectId: projectId,
                companyId: opportunity.companyId,
                userId: dataController.currentUser?.id,
                modelContext: modelContext,
                dataController: dataController
            )
            return
        }

        // The staging store is in-memory — an app kill between visit review
        // and conversion used to drop the whole packet (photos, notes, deck
        // link) silently. The artifacts themselves are persisted SwiftData
        // rows, so rebuild the payload from them instead of losing the visit.
        guard let derived = SiteVisitProjectHandoff.derivePayload(
            opportunityId: opportunity.id,
            opportunityAddress: opportunity.address,
            modelContext: modelContext
        ) else { return }
        SiteVisitProjectHandoff.apply(
            payload: derived.payload,
            artifacts: derived.artifacts,
            projectId: projectId,
            companyId: opportunity.companyId,
            userId: dataController.currentUser?.id,
            modelContext: modelContext,
            dataController: dataController
        )
    }

    private func openExistingProjectAction() {
        guard let existing = existingProject else { return }
        errorMessage = nil
        isSaving = true

        Task {
            do {
                let service = LeadConversionService(
                    companyId: opportunity.companyId,
                    modelContext: modelContext
                )
                let outcome = try await service.convertOpportunityToProject(
                    lead: opportunity,
                    actualValue: parseActualValue(),
                    titleOverride: nil,
                    notes: closingNotes.isEmpty ? nil : closingNotes,
                    linkToProjectId: existing.id,
                    userId: dataController.currentUser?.id
                )

                switch outcome {
                case .project(let project):
                    completeConverted(projectId: project.id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        appState.viewProjectDetailsById(project.id)
                    }
                case .committedWithKnownProject(let projectId):
                    // OPEN PROJECT on the DUPLICATE-EXISTS footer lands on the
                    // RPC's already-converted branch, which reports
                    // `project_accessible: false` unconditionally. Acting on
                    // that flag is what cleared the lead's link and opened
                    // nothing (bug ced5b3cb-B). Open what the server named;
                    // the project sheet hydrates itself if the row is late.
                    completeConverted(projectId: projectId)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        appState.viewProjectDetailsById(projectId)
                    }
                case .committedWithoutAccessibleProject:
                    completeConvertedWithoutAccessibleProject()
                }
            } catch {
                isSaving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    /// The deliberate exit from the peek: the operator asked for the project,
    /// so the conversion closes and the app-wide project route runs. Nothing
    /// else in this sheet dismisses on a tap any more.
    private func openProjectLeavingConversion(_ projectId: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            appState.viewProjectDetailsById(projectId)
        }
    }

    private func selectExistingProject(_ projectId: String) {
        guard clientOtherProjects.contains(where: {
            $0.id == projectId && $0.linkState == .matchable
        }) else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedExistingProjectId = selectedExistingProjectId == projectId ? nil : projectId
        errorMessage = nil
    }

    /// A candidate can become invalid between preflight and commit. Clear the
    /// stale choice and replace the list from the authoritative server before
    /// asking the operator to review again.
    private func refreshPreflightAfterLinkFailure(failedProjectId: String?) async -> Bool {
        requiresMatchReviewRefresh = true
        if let failedProjectId {
            unavailableMatchProjectIds.insert(failedProjectId.lowercased())
        }
        selectedExistingProjectId = nil
        existingProject = nil
        clientOtherProjects = []
        chipNotice = nil
        candidateLinkCheckFailed = false
        hasLoadedPreflight = false
        let recovered = await loadPreflight()
        if !preflightFailed {
            requiresMatchReviewRefresh = false
        }
        return recovered
    }

    private func retryPreflight() {
        guard hasLoadedPreflight, preflightFailed, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        selectedExistingProjectId = nil
        existingProject = nil
        clientOtherProjects = []
        chipNotice = nil
        candidateLinkCheckFailed = false
        hasLoadedPreflight = false

        Task {
            let recovered = await Self.runInitialLoad(
                resolveLinkedClient: {
                    await resolveLinkedClient()
                },
                applyAddressPrefill: {
                    applyInitialAddressPrefill()
                },
                loadPreflight: {
                    await loadPreflight()
                }
            )
            if recovered { return }
            applyInitialFinancialValue()
            if !preflightFailed {
                requiresMatchReviewRefresh = false
                if let pendingCreateAddressFingerprint {
                    verifiedCreateAddressFingerprint = pendingCreateAddressFingerprint
                    self.pendingCreateAddressFingerprint = nil
                }
            }
            isSaving = false
            if preflightFailed {
                errorMessage = "COULD NOT CHECK PROJECTS — RETRY"
            }
        }
    }

    /// Persists the exact create address, then re-runs candidate discovery
    /// before any nil-link conversion. Returns true when the current tap must
    /// stop so the operator can review refreshed project state.
    private func stopForCreateAddressRecheckIfNeeded(companyId: String) async throws -> Bool {
        guard Self.createAddressNeedsRecheck(
            address: addressText,
            verifiedFingerprint: verifiedCreateAddressFingerprint
        ) else { return false }

        let fingerprint = Self.createAddressFingerprint(addressText)
        pendingCreateAddressFingerprint = fingerprint
        let canonicalAddress = ProjectAutoNamer.canonicalizedAddress(addressText)
        let originalAddress = (opportunity.address ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !canonicalAddress.isEmpty || canonicalAddress != originalAddress {
            let repo = OpportunityRepository(companyId: companyId)
            // A client-sourced address brings the client's geocode with it —
            // the RPC reads latitude/longitude off the opportunity row, so an
            // address written without them lands a project with no map pin.
            let carriesClientGeo = addressIsFromClient
                && prefilledLatitude != nil
                && prefilledLongitude != nil
            _ = try await repo.update(opportunity.id, patch: AddressPatch(
                address: canonicalAddress,
                latitude: carriesClientGeo ? prefilledLatitude : nil,
                longitude: carriesClientGeo ? prefilledLongitude : nil
            ))
            opportunity.address = canonicalAddress.isEmpty ? nil : canonicalAddress
            if carriesClientGeo {
                opportunity.latitude = prefilledLatitude
                opportunity.longitude = prefilledLongitude
            }
        }

        selectedExistingProjectId = nil
        existingProject = nil
        clientOtherProjects = []
        chipNotice = nil
        candidateLinkCheckFailed = false
        hasLoadedPreflight = false
        let recovered = await loadPreflight()
        if recovered { return true }
        guard !preflightFailed else { return true }
        if Self.shouldStopCreateAfterAddressRecheck(
            creationBlocker: creationBlocker
        ) {
            return true
        }

        verifiedCreateAddressFingerprint = fingerprint
        pendingCreateAddressFingerprint = nil

        guard Self.createAddressFingerprint(addressText) == fingerprint else {
            errorMessage = "ADDRESS CHANGED — CHECK AGAIN"
            return true
        }
        if existingProject != nil {
            errorMessage = "PROJECT LINK UPDATED — REVIEW"
            return true
        }
        if clientOtherProjects.contains(where: \.isLikelyDuplicate) {
            errorMessage = "PROJECTS FOUND — REVIEW MATCHES"
            return true
        }
        return false
    }

    // MARK: - Helpers

    /// Address write-back patch. Coordinates are OMITTED (never encoded as
    /// null) unless we actually have a pair to write — a null pair would erase
    /// an existing geocode.
    private struct AddressPatch: Encodable {
        let address: String
        let latitude: Double?
        let longitude: Double?

        enum CodingKeys: String, CodingKey {
            case address, latitude, longitude
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(address, forKey: .address)
            try container.encodeIfPresent(latitude, forKey: .latitude)
            try container.encodeIfPresent(longitude, forKey: .longitude)
        }
    }

    private func parseActualValue() -> Double? {
        let stripped = actualValueText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty, let value = Double(stripped) else { return nil }
        // Reject inf/nan and anything past the numeric(12,2) ceiling: an
        // out-of-range or non-finite value otherwise reaches the convert RPC and
        // 400s with an unrecoverable generic save error. (review W-16)
        guard value.isFinite, value >= 0, value < 10_000_000_000 else { return nil }
        return value
    }

    private func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func simplifyError(_ error: Error, target: SubmissionTarget? = nil) -> String {
        if let conversionError = error as? LeadConversionError {
            switch conversionError {
            case .opportunityNotFound: return "LEAD NOT FOUND"
            case .accessDenied: return "PERMISSION DENIED"
            case .assignmentChanged: return "ASSIGNMENT CHANGED — REFRESH"
            case .leadChanged: return "LEAD CHANGED — REFRESH"
            case .projectLinkUnavailable(let reason):
                return Self.projectLinkFailureCopy(reason)
            case .unverifiedResult: return "CONVERSION NOT VERIFIED — REFRESH"
            }
        }
        let description = String(describing: error).lowercased()
        if description.contains("network") || description.contains("offline") {
            return "CHECK CONNECTION — RETRY"
        }
        return target?.linkToProjectId == nil
            ? "COULD NOT CREATE — TAP TO RETRY"
            : "COULD NOT MATCH — TAP TO RETRY"
    }
}

// MARK: - Render-state enum

private extension ConvertToProjectSheet {
    enum RenderState {
        case normal
        case duplicate
        case clientHasOthers
    }
}

// MARK: - Lightweight display models (preflight-sourced)

extension ConvertToProjectSheet {
    static func canCommitConversion(
        hasLoadedPreflight: Bool,
        preflightFailed: Bool,
        isSaving: Bool,
        requiresMatchReviewRefresh: Bool,
        hasLikelyDuplicate: Bool,
        hasSelectedMatch: Bool,
        creationBlocker: ConversionPreflightCreationBlocker? = nil
    ) -> Bool {
        hasLoadedPreflight
            && !preflightFailed
            && !isSaving
            && !requiresMatchReviewRefresh
            && creationBlocker == nil
            && (!hasLikelyDuplicate || hasSelectedMatch)
    }

    static func createAddressFingerprint(_ address: String) -> String {
        ProjectAutoNamer.canonicalizedAddress(address)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func createAddressNeedsRecheck(
        address: String,
        verifiedFingerprint: String?
    ) -> Bool {
        verifiedFingerprint != createAddressFingerprint(address)
    }

    /// A refreshed server blocker is already the final authority for this tap.
    /// Do not invoke conversion just to receive the same rejection again.
    static func shouldStopCreateAfterAddressRecheck(
        creationBlocker: ConversionPreflightCreationBlocker?
    ) -> Bool {
        creationBlocker != nil
    }

    enum RelatedProjectInteraction: Equatable {
        /// Tapping SELECTS this project as the conversion target. Commit still
        /// belongs to the footer CTA — a chip never converts anything.
        case match
        /// Tapping opens a read-only PEEK layered over this sheet. The old
        /// `.open` dismissed the convert sheet and navigated away, silently
        /// destroying everything the operator had typed (bug ced5b3cb-A).
        case peek
    }

    /// Why a related project can or cannot be this conversion's target.
    /// Replaces the old `isLikelyDuplicate` + `isMatchAvailable` pair, which
    /// could not tell "already belongs to another lead" apart from "we could
    /// not check" — and the sheet blamed an admin for both.
    enum RelatedProjectLinkState: Equatable {
        /// Server-approved and unlinked (or already this lead's). Address is a
        /// ranking signal, not a requirement.
        case matchable
        /// Same address and server-approved, but it already belongs to a
        /// DIFFERENT lead. The commit would reject a link; review only.
        case linkedElsewhere
        /// Same address, but the link re-read failed. Neither offered nor
        /// declared taken — we do not know, and we say so.
        case unverified
        /// A target this session's commit already rejected.
        case unavailable
        /// Visible context that the server did not authorize as a target.
        case reviewOnly
    }

    /// Everything the sheet renders from one authoritative preflight, resolved
    /// as a pure value so the dead-end logic is provable without a network.
    struct PreflightViewState: Equatable {
        let existingLinkedProjectId: String?
        let existingLinkedProjectTitle: String?
        let refs: [RelatedProjectRef]
        let creationBlocker: ConversionPreflightCreationBlocker?
        let statusMessage: String?
        let candidateLinkCheckFailed: Bool
    }

    /// Reduces the server preflight (plus the client's candidate link re-read)
    /// into render state.
    ///
    /// The blocker is SERVER-AUTHORED ONLY. The old code synthesized
    /// `.projectReviewRequired` whenever its own re-check filtered every
    /// candidate away, which disabled MATCH *and* CREATE and told the operator
    /// an admin had to intervene — for a condition the server had not raised
    /// (bug 5468b3c6, H1).
    static func reducePreflight(
        _ preflight: ConversionPreflight,
        matchableCandidateIds: Set<String>,
        candidateLinkCheckFailed: Bool,
        unavailableMatchProjectIds: Set<String>,
        manualCandidates: [ManualProjectLinkCandidate] = []
    ) -> PreflightViewState {
        var seen = Set<String>()
        var refs: [RelatedProjectRef] = []

        for candidate in preflight.duplicateCandidates
        where seen.insert(candidate.projectId.lowercased()).inserted {
            let id = candidate.projectId.lowercased()
            let linkState: RelatedProjectLinkState
            if unavailableMatchProjectIds.contains(id) {
                linkState = .unavailable
            } else if candidateLinkCheckFailed {
                linkState = .unverified
            } else if matchableCandidateIds.contains(id) {
                linkState = .matchable
            } else {
                linkState = .linkedElsewhere
            }
            refs.append(RelatedProjectRef(
                id: candidate.projectId,
                title: candidate.title ?? "",
                address: candidate.address,
                status: nil,
                linkState: linkState,
                isAddressSuggestion: true
            ))
        }
        for other in preflight.otherClientProjects
        where seen.insert(other.projectId.lowercased()).inserted {
            let id = other.projectId.lowercased()
            refs.append(RelatedProjectRef(
                id: other.projectId,
                title: other.title ?? "",
                address: other.address,
                status: other.status.flatMap { Status(rawValue: $0) },
                linkState: unavailableMatchProjectIds.contains(id)
                    ? .unavailable
                    : (matchableCandidateIds.contains(id) ? .matchable : .reviewOnly),
                isAddressSuggestion: false
            ))
        }
        for candidate in manualCandidates
        where seen.insert(candidate.projectId.lowercased()).inserted {
            let id = candidate.projectId.lowercased()
            refs.append(RelatedProjectRef(
                id: candidate.projectId,
                title: candidate.title ?? "",
                address: candidate.address,
                status: candidate.status.flatMap { Status(rawValue: $0) },
                linkState: unavailableMatchProjectIds.contains(id)
                    ? .unavailable
                    : .matchable,
                isAddressSuggestion: candidate.sameAddress
            ))
        }

        return PreflightViewState(
            existingLinkedProjectId: preflight.existingLinkedProject?.id,
            existingLinkedProjectTitle: preflight.existingLinkedProject?.title,
            refs: refs,
            creationBlocker: preflight.creationBlocker,
            statusMessage: statusMessage(
                creationBlocker: preflight.creationBlocker,
                refs: refs,
                candidateLinkCheckFailed: candidateLinkCheckFailed
            ),
            candidateLinkCheckFailed: candidateLinkCheckFailed
        )
    }

    /// One honest line about the state the operator is actually in. Every
    /// message names the obstacle AND leaves a next move on screen — the peek
    /// affordance stays live on every chip in every one of these states.
    static func statusMessage(
        creationBlocker: ConversionPreflightCreationBlocker?,
        refs: [RelatedProjectRef],
        candidateLinkCheckFailed: Bool
    ) -> String? {
        switch creationBlocker {
        case .addressRequired:
            return "ADD AN ADDRESS TO CHECK EXISTING PROJECTS"
        case .projectReviewRequired:
            // The server raises this when an active same-address project
            // exists that this operator cannot see or edit. Naming the real
            // obstacle beats the old "MATCHING PROJECT REQUIRES ADMIN REVIEW".
            return "SAME ADDRESS PROJECT — ADMIN ACCESS NEEDED"
        case nil:
            break
        }
        if candidateLinkCheckFailed {
            return "COULD NOT CHECK PROJECT LINKS — RETRY"
        }
        let duplicates = refs.filter(\.isLikelyDuplicate)
        if !duplicates.isEmpty, !duplicates.contains(where: { $0.linkState == .matchable }) {
            return "EVERY MATCH IS LINKED TO ANOTHER LEAD"
        }
        return nil
    }

    /// Operator copy for each door the server can close on a link.
    static func projectLinkFailureCopy(_ reason: ProjectLinkFailureReason?) -> String {
        switch reason {
        case .matchingProjectRequiresReview: return "SAME ADDRESS ALREADY HAS A PROJECT"
        case .addressRequiredForProjectMatch: return "ADD AN ADDRESS TO MATCH A PROJECT"
        case .matchingProjectLinkConflict:    return "PROJECT IS LINKED TO ANOTHER LEAD"
        case .dedupeProofUnavailable:         return "COULD NOT CONFIRM DUPLICATES — RETRY"
        case nil:                             return "PROJECT CHANGED — REVIEW MATCHES"
        }
    }

    // MARK: - Prefill (bug a7df1f37)

    /// Executes the opening sequence in the only safe order: client identity,
    /// visible address, then the authoritative duplicate preflight.
    @MainActor
    static func runInitialLoad(
        resolveLinkedClient: () async -> Void,
        applyAddressPrefill: () -> Void,
        loadPreflight: () async -> Bool
    ) async -> Bool {
        await resolveLinkedClient()
        applyAddressPrefill()
        return await loadPreflight()
    }

    /// Predicate-scoped local resolution with a tenant-scoped repository
    /// fallback. The generic value keeps the ordering contract deterministic
    /// in tests while production passes the real SwiftData `Client` model.
    @MainActor
    static func resolveLinkedClientValue<Value>(
        clientId: String?,
        local: (String) -> Value?,
        remote: (String) async throws -> Value
    ) async -> Value? {
        guard let clientId = clientId?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clientId.isEmpty else { return nil }

        if let localValue = local(clientId) {
            return localValue
        }

        return try? await remote(clientId)
    }

    /// One-shot guard for the only automatic write. A client-borrowed address
    /// is pushed onto the lead only after the server proves it cannot match
    /// projects without that denormalized value.
    struct InitialClientAddressRecheckGate: Equatable {
        private(set) var hasAttempted = false

        mutating func consume(
            creationBlocker: ConversionPreflightCreationBlocker?,
            address: String,
            isFromClient: Bool
        ) -> Bool {
            guard !hasAttempted,
                  creationBlocker == .addressRequired,
                  isFromClient,
                  !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }

            hasAttempted = true
            return true
        }
    }

    private enum LinkedClientResolutionError: Error {
        case tenantMismatch
    }

    /// The ADDRESS the convert form opens with, and where it came from.
    struct AddressPrefill: Equatable {
        let text: String
        let latitude: Double?
        let longitude: Double?
        /// True when the value was borrowed from the linked client record.
        /// The form TAGS it, because the create path writes the visible
        /// address back onto the opportunity.
        let isFromClient: Bool
    }

    /// A lead created from a client page routinely carries no address of its
    /// own while the client record holds one. The old prefill read the
    /// opportunity alone, so the server answered `address_required` and the
    /// sheet demanded an address the system already had.
    static func addressPrefill(
        opportunityAddress: String?,
        opportunityLatitude: Double?,
        opportunityLongitude: Double?,
        clientAddress: String?,
        clientLatitude: Double?,
        clientLongitude: Double?
    ) -> AddressPrefill {
        if let own = opportunityAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !own.isEmpty {
            return AddressPrefill(
                text: own,
                latitude: opportunityLatitude,
                longitude: opportunityLongitude,
                isFromClient: false
            )
        }
        if let borrowed = clientAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !borrowed.isEmpty {
            // Coordinates travel with the address they were resolved for, or
            // not at all — never borrow the lead's geo for the client's street.
            return AddressPrefill(
                text: borrowed,
                latitude: clientLatitude,
                longitude: clientLongitude,
                isFromClient: true
            )
        }
        return AddressPrefill(text: "", latitude: nil, longitude: nil, isFromClient: false)
    }

    /// Contact identity for the summary card, falling back field-by-field to
    /// the client record. A lead with blank contact fields used to render a
    /// bare em dash while the system knew exactly whose job this was.
    struct LeadSummaryContact: Equatable {
        let name: String
        let phone: String?
    }

    static func leadSummaryContact(
        opportunityName: String,
        opportunityPhone: String?,
        clientName: String?,
        clientPhone: String?
    ) -> LeadSummaryContact {
        func firstNonBlank(_ values: [String?]) -> String? {
            for value in values {
                if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !trimmed.isEmpty {
                    return trimmed
                }
            }
            return nil
        }
        return LeadSummaryContact(
            name: firstNonBlank([opportunityName, clientName]) ?? "—",
            phone: firstNonBlank([opportunityPhone, clientPhone])
        )
    }

    struct SubmissionTarget: Equatable {
        let linkToProjectId: String?

        init(selectedProjectId: String?) {
            let trimmed = selectedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines)
            linkToProjectId = trimmed?.isEmpty == false ? trimmed : nil
        }

        var primaryLabel: String {
            linkToProjectId == nil ? "CREATE PROJECT" : "MATCH PROJECT"
        }

        var showsProjectIdentityFields: Bool {
            linkToProjectId == nil
        }
    }

    /// Display payload for the DUPLICATE-EXISTS card. Hydrated best-effort from
    /// the server project row, local SwiftData, or the preflight title alone.
    struct DuplicateProjectDisplay {
        let id: String
        let title: String
        let address: String?
        let status: Status?
        let createdAt: Date?
    }

    /// Chip ref for the CLIENT-HAS-OTHERS list, sourced from the server
    /// preflight (no local Project required).
    struct RelatedProjectRef: Identifiable, Equatable {
        let id: String
        let title: String
        let address: String?
        let status: Status?
        let linkState: RelatedProjectLinkState
        let isAddressSuggestion: Bool

        init(
            id: String,
            title: String,
            address: String?,
            status: Status?,
            linkState: RelatedProjectLinkState,
            isAddressSuggestion: Bool = false
        ) {
            self.id = id
            self.title = title
            self.address = address
            self.status = status
            self.linkState = linkState
            self.isAddressSuggestion = isAddressSuggestion
        }

        /// Same-address suggestions gate CREATE under the independent server
        /// dedupe contract. A manually selectable project at another address
        /// remains an option without becoming a duplicate warning.
        var isLikelyDuplicate: Bool { isAddressSuggestion }

        var interaction: RelatedProjectInteraction {
            linkState == .matchable ? .match : .peek
        }

        /// What the chip claims, in the operator's terms. `LINKED` is the
        /// honest word for a same-address project that already belongs to
        /// another lead — the old copy called it `REVIEW`, which read as a
        /// suggestion rather than a fact.
        var actionLabel: String? {
            switch linkState {
            case .matchable:       return "MATCH"
            case .linkedElsewhere: return "LINKED"
            case .unverified:      return "UNVERIFIED"
            case .unavailable:     return "REVIEW"
            case .reviewOnly:      return nil
            }
        }

        /// Status color where known; neutral hairline otherwise.
        var statusColor: Color {
            status?.color ?? OPSStyle.Colors.textMute
        }
    }
}
