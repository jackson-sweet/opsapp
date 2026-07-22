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
    /// A hidden linked project must be verified through the guarded conversion
    /// RPC before the client may present a committed win. While this flag is
    /// set, the sheet exposes no create/retry action.
    @State private var hiddenConversionRecoveryDetected = false

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
        .task {
            let recoveredCommittedConversion = await loadPreflight()
            guard !recoveredCommittedConversion else { return }
            applyInitialFormValues()
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

            Text(opportunity.contactName.isEmpty ? "—" : opportunity.contactName)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(opportunity.shortDisplayId)
                    .monospacedDigit()
                if let phone = opportunity.contactPhone, !phone.isEmpty {
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
            onOpen: openExistingProject,
            onMatch: selectExistingProject
        )
    }

    /// Tan attention banner for the CLIENT-HAS-OTHERS render state. Extracted
    /// as its own view so the snapshot harness can render it against fixture
    /// counts (bug 4e11e121 — the old header wrapped onto multiple lines).
    struct ClientOthersBanner: View {
        let projects: [RelatedProjectRef]
        let selectedProjectId: String?
        let onOpen: (String) -> Void
        let onMatch: (String) -> Void

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
                        Button {
                            switch project.interaction {
                            case .match:
                                onMatch(project.id)
                            case .open:
                                onOpen(project.id)
                            }
                        } label: {
                            projectChip(project)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(accessibilityLabel(for: project))
                    }
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

        private func projectChip(_ project: RelatedProjectRef) -> some View {
            let isSelected = selectedProjectId == project.id && project.interaction == .match

            return HStack(spacing: 6) {
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
                        .foregroundColor(isSelected ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.tanTextM)
                        .textCase(.uppercase)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(isSelected ? OPSStyle.Colors.oliveFillM : OPSStyle.Colors.surfaceHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(isSelected ? OPSStyle.Colors.oliveLineM : OPSStyle.Colors.line, lineWidth: 1)
            )
            // 32pt visible chip · 44pt hit area — MOBILE.md §1 / audit F1.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }

        private func accessibilityLabel(for project: RelatedProjectRef) -> String {
            switch project.interaction {
            case .match:
                return selectedProjectId == project.id
                    ? "Selected project \(project.title) for matching"
                    : "Match lead to project \(project.title)"
            case .open:
                return "Open project \(project.title)"
            }
        }

        private func truncatedTitle(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return "UNTITLED" }
            return trimmed.count > 18 ? String(trimmed.prefix(17)) + "…" : trimmed
        }
    }

    // MARK: - Form fields

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            if submissionTarget.showsProjectIdentityFields {
                nameField

                LeadField(
                    label: "ADDRESS",
                    hint: creationBlocker == .addressRequired ? "[REQUIRED]" : "[OPTIONAL]"
                ) {
                    LeadTextInput(
                        placeholder: "3185 Fairview Rd",
                        text: $addressText,
                        textContentType: .fullStreetAddress
                    )
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

            Text(formatMoney(bundle.estimate.total))
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
                        label: "ADMIN REVIEW REQUIRED",
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
        let service = LeadConversionService(companyId: companyId)
        preflightFailed = false
        creationBlocker = nil
        errorMessage = nil

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

            let matchableCandidateIds = try await service.matchableCandidateProjectIds(
                for: opportunity,
                candidates: preflight.duplicateCandidates
            )
            creationBlocker = preflight.creationBlocker
            if creationBlocker == nil,
               !preflight.duplicateCandidates.isEmpty,
               matchableCandidateIds.isEmpty {
                creationBlocker = .projectReviewRequired
            }
            clientOtherProjects = mergeRelatedRefs(
                candidates: preflight.duplicateCandidates,
                others: preflight.otherClientProjects,
                matchableCandidateIds: matchableCandidateIds
            )
            preflightFailed = false
            switch creationBlocker {
            case .addressRequired:
                errorMessage = "ADD AN ADDRESS TO CHECK EXISTING PROJECTS"
            case .projectReviewRequired:
                errorMessage = "MATCHING PROJECT REQUIRES ADMIN REVIEW"
            case nil:
                break
            }
        } catch {
            // Fail closed. RETRY CHECK is the only committing footer action
            // until the authoritative candidate + reciprocal-link reads pass.
            preflightFailed = true
            suggestedName = ""
            errorMessage = "COULD NOT CHECK PROJECTS — RETRY"
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

    /// Merge candidates (likely-duplicates) + other-client projects into the
    /// chip list. Dedup by project id, candidates first so the strongest signal
    /// leads. Maps a status string to a ProjectStatus/color where present.
    private func mergeRelatedRefs(
        candidates: [PreflightCandidate],
        others: [PreflightClientProject],
        matchableCandidateIds: Set<String>
    ) -> [RelatedProjectRef] {
        var seen = Set<String>()
        var refs: [RelatedProjectRef] = []

        for c in candidates where seen.insert(c.projectId).inserted {
            refs.append(RelatedProjectRef(
                id: c.projectId,
                title: c.title ?? "",
                address: c.address,
                status: nil,
                isLikelyDuplicate: true,
                isMatchAvailable: matchableCandidateIds.contains(c.projectId.lowercased())
                    && !unavailableMatchProjectIds.contains(c.projectId.lowercased())
            ))
        }
        for o in others where seen.insert(o.projectId).inserted {
            refs.append(RelatedProjectRef(
                id: o.projectId,
                title: o.title ?? "",
                address: o.address,
                status: o.status.flatMap { Status(rawValue: $0) },
                isLikelyDuplicate: false
            ))
        }
        return refs
    }

    private func applyInitialFormValues() {
        if addressText.isEmpty {
            addressText = opportunity.address ?? ""
        }
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
                let service = LeadConversionService(companyId: companyId)

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
                let service = LeadConversionService(companyId: opportunity.companyId)
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
                case .committedWithoutAccessibleProject:
                    completeConvertedWithoutAccessibleProject()
                }
            } catch {
                isSaving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    private func openExistingProject(_ projectId: String) {
        // CLIENT-HAS-OTHERS info chip — a non-committing review peek.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            appState.viewProjectDetailsById(projectId)
        }
    }

    private func selectExistingProject(_ projectId: String) {
        guard clientOtherProjects.contains(where: {
            $0.id == projectId && $0.interaction == .match
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
        hasLoadedPreflight = false

        Task {
            let recovered = await loadPreflight()
            if recovered { return }
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
            _ = try await repo.update(opportunity.id, patch: ["address": canonicalAddress])
            opportunity.address = canonicalAddress.isEmpty ? nil : canonicalAddress
        }

        selectedExistingProjectId = nil
        existingProject = nil
        clientOtherProjects = []
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

    private func formatMoney(_ value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return "$" + (fmt.string(from: NSNumber(value: value)) ?? "0")
    }

    private func simplifyError(_ error: Error, target: SubmissionTarget? = nil) -> String {
        if let conversionError = error as? LeadConversionError {
            switch conversionError {
            case .opportunityNotFound: return "LEAD NOT FOUND"
            case .accessDenied: return "PERMISSION DENIED"
            case .assignmentChanged: return "ASSIGNMENT CHANGED — REFRESH"
            case .leadChanged: return "LEAD CHANGED — REFRESH"
            case .projectLinkUnavailable: return "PROJECT CHANGED — REVIEW MATCHES"
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
        case match
        case open
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
    /// preflight (no local Project required). `isLikelyDuplicate` flags the
    /// high/medium-confidence candidates so they read distinctly.
    struct RelatedProjectRef: Identifiable {
        let id: String
        let title: String
        let address: String?
        let status: Status?
        let isLikelyDuplicate: Bool
        let isMatchAvailable: Bool

        init(
            id: String,
            title: String,
            address: String?,
            status: Status?,
            isLikelyDuplicate: Bool,
            isMatchAvailable: Bool? = nil
        ) {
            self.id = id
            self.title = title
            self.address = address
            self.status = status
            self.isLikelyDuplicate = isLikelyDuplicate
            self.isMatchAvailable = isMatchAvailable ?? isLikelyDuplicate
        }

        /// The server already applied project view/edit authorization to its
        /// duplicate candidates. Other client projects remain informational.
        var interaction: RelatedProjectInteraction {
            isLikelyDuplicate && isMatchAvailable ? .match : .open
        }

        var actionLabel: String? {
            switch interaction {
            case .match:
                return "MATCH"
            case .open:
                return isLikelyDuplicate ? "REVIEW" : nil
            }
        }

        /// Status color where known; neutral hairline otherwise.
        var statusColor: Color {
            status?.color ?? OPSStyle.Colors.textMute
        }
    }
}
