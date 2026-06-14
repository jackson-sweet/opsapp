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
//                        and/or other client projects. Tan warning banner sits
//                        above the standard form; the operator can still create.
//
//  Auto-naming (Phase 5): the TITLE defaults to AUTO — the server derives the
//  name from the address via `derive_project_name` (street line before the
//  first comma) and the `projects_autoname` trigger dedups with `#N`. The sheet
//  shows the derived name and a LIVE preview as the operator edits the address;
//  a quiet RENAME affordance reveals a hand-edit field (sets title_is_auto =
//  false). When auto, the operator never types a name.
//
//  Exit semantics (plan §2.1 Q3, restated in the Phase 4 brief):
//
//    The decision to win was already committed when the operator tapped
//    MARK WON →; this sheet only asks "do you also want a project?". Every
//    *committing* exit marks the lead WON — a `didCommitWon` flag prevents
//    double-firing. The lone non-committing exit is the CLIENT-HAS-OTHERS
//    review peek: investigating a related project is not a conversion.
//
//    × / CANCEL / drag / scrim    → markWonNoProject(actualValue)
//    CREATE PROJECT →             → convertOpportunityToProject(...), stay on LEADS
//    OPEN PROJECT → (DUPLICATE)   → mark won with existing project, then open it
//    other-project chip           → review peek, no commit, then open it
//

import SwiftUI
import SwiftData

struct ConvertToProjectSheet: View {
    let opportunity: Opportunity

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
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
    @State private var estimateBundles: [LeadConversionService.EstimateBundle] = []
    @State private var hasLoadedPreflight = false

    // MARK: - Operation state

    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Once we've fired markWon (via convert or open-project) we suppress the
    /// onDisappear escape-hatch — otherwise drag-down dismiss after a successful
    /// CREATE PROJECT would mark-won-again and overwrite actualValue with stale
    /// state.
    @State private var didCommitWon = false
    /// Set only by the CLIENT-HAS-OTHERS review peek. Tapping an "other
    /// project" chip is an investigation, not a conversion — the operator has
    /// not committed to winning this lead — so this flag suppresses the
    /// onDisappear escape hatch and the sheet dismisses without marking won.
    @State private var didDismissForReview = false

    // MARK: - Computed

    private var renderState: RenderState {
        if existingProject != nil { return .duplicate }
        if !clientOtherProjects.isEmpty { return .clientHasOthers }
        return .normal
    }

    private var canCreate: Bool {
        // Title is OPTIONAL now — auto-naming fills it server-side. Only block
        // on an in-flight save.
        !isSaving
    }

    private var totalLaborItems: Int {
        estimateBundles.reduce(0) { $0 + $1.laborItems.count }
    }

    /// The street line a hand-typed address resolves to, mirroring the server's
    /// `derive_project_name`: substring before the first comma, trimmed. Falls
    /// back to the server `suggested_name`, then to a neutral placeholder.
    private var derivedNamePreview: String {
        let trimmedAddress = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAddress.isEmpty {
            let streetLine = trimmedAddress
                .components(separatedBy: ",")
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !streetLine.isEmpty { return streetLine }
            return trimmedAddress
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
            await loadPreflight()
            applyInitialFormValues()
        }
        .onDisappear {
            // Drag-down / scrim / interactive dismiss all funnel through here.
            // Tap-driven dismisses already fire their own markWon/convert path
            // and set didCommitWon = true, so we'd skip work here. The
            // CLIENT-HAS-OTHERS review peek sets didDismissForReview so it can
            // leave the sheet without committing the lead.
            guard !didCommitWon, !didDismissForReview else { return }
            didCommitWon = true
            Task { await markWonNoProjectSilently() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            SheetTitleLabel(title: "CONVERT → PROJECT", size: .full)
            SheetCloseButton {
                Task { await commitNoProjectAndDismiss() }
            }
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
            .font(.custom("JetBrainsMono-Medium", size: 10))
            .kerning(1.6)
            .textCase(.uppercase)

            Text(opportunity.contactName.isEmpty ? "—" : opportunity.contactName)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(String(opportunity.id.prefix(6)).uppercased())
                if let phone = opportunity.contactPhone, !phone.isEmpty {
                    Text("·")
                    Text(phone)
                }
            }
            .font(.custom("JetBrainsMono-Regular", size: 10))
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
        .glassSurface()
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
            .font(.custom("JetBrainsMono-Medium", size: 10))
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
                        .font(.custom("JetBrainsMono-Regular", size: 10))
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("THIS CLIENT HAS \(String(format: "%02d", clientOtherProjects.count)) OTHER ")
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                Text(clientOtherProjects.count == 1 ? "PROJECT" : "PROJECTS")
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                Text("  ·  ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("REVIEW BEFORE CREATING")
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(.custom("JetBrainsMono-Medium", size: 10))
            .kerning(1.6)
            .textCase(.uppercase)

            ChipWrap(spacing: 6) {
                ForEach(clientOtherProjects.prefix(8)) { project in
                    Button {
                        openExistingProject(project.id)
                    } label: {
                        projectChip(project)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Open project \(project.title)")
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
        HStack(spacing: 6) {
            Circle()
                .fill(project.statusColor)
                .frame(width: 5, height: 5)
            Text(truncatedTitle(project.title))
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .kerning(1.2)
                .foregroundColor(OPSStyle.Colors.text)
                .textCase(.uppercase)
            if project.isLikelyDuplicate {
                Text("·")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("MATCH")
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .kerning(1.0)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                    .textCase(.uppercase)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
        // 32pt visible chip · 44pt hit area — MOBILE.md §1 / audit F1.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func truncatedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "UNTITLED" }
        return trimmed.count > 18 ? String(trimmed.prefix(17)) + "…" : trimmed
    }

    // MARK: - Form fields

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            nameField

            LeadField(label: "ADDRESS", hint: "[OPTIONAL]") {
                LeadTextInput(
                    placeholder: "3185 Fairview Rd",
                    text: $addressText,
                    textContentType: .fullStreetAddress
                )
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
    }

    // MARK: - Name field (auto-named by default)

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("NAME")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .textCase(.uppercase)
                Text(titleIsAuto ? "[AUTO]" : "[CUSTOM]")
                    .font(.custom("JetBrainsMono-Regular", size: 10))
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
                    .font(.custom("JetBrainsMono-Medium", size: 10))
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
                .font(.custom("JetBrainsMono-Regular", size: 10))
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
                .font(.custom("JetBrainsMono-Regular", size: 10))
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
            .font(.custom("JetBrainsMono-Regular", size: 10))
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
                .font(.custom("JetBrainsMono-Regular", size: 10))
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
            Text("Marks the lead WON and creates a Project (status: ACCEPTED) linked back to this lead. Finish project setup from the PROJECTS tab.")
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .font(.custom("JetBrainsMono-Regular", size: 10))
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

            SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { Task { await commitNoProjectAndDismiss() } }
                )
                .disabled(isSaving)
            } primary: {
                if renderState == .duplicate {
                    SheetCTAButton(
                        label: "OPEN PROJECT",
                        icon: "arrow.right",
                        variant: .primary,
                        isLoading: isSaving,
                        action: { openExistingProjectAction() }
                    )
                    .disabled(isSaving)
                } else {
                    SheetCTAButton(
                        label: "CREATE PROJECT",
                        icon: "arrow.right",
                        variant: .primary,
                        isLoading: isSaving,
                        action: createProject
                    )
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.5)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 28)
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

    private func loadPreflight() async {
        guard !hasLoadedPreflight else { return }
        let companyId = opportunity.companyId
        let service = LeadConversionService(companyId: companyId)

        // SERVER preflight — single source of truth for render state + suggested
        // name. Replaces the prior local SwiftData duplicate/other-projects
        // checks. Non-fatal on failure: the operator can still create a project
        // (the convert RPC re-runs the same dedup server-side and is idempotent).
        do {
            let preflight = try await service.getConversionPreflight(for: opportunity)
            suggestedName = preflight.suggestedName ?? ""

            if let linked = preflight.existingLinkedProject {
                existingProject = await resolveDuplicateDisplay(
                    id: linked.id,
                    fallbackTitle: linked.title
                )
            }

            clientOtherProjects = mergeRelatedRefs(
                candidates: preflight.duplicateCandidates,
                others: preflight.otherClientProjects
            )
        } catch {
            // Preflight unavailable (offline / RPC error) — fall through to the
            // plain NORMAL form. Detection still happens server-side on convert.
            suggestedName = ""
        }

        // Network fetch (estimates + line items) — still drives the tasks preview.
        do {
            estimateBundles = try await service.estimateBundles(for: opportunity)
        } catch {
            // Non-fatal — operator can still create without the preview
            estimateBundles = []
        }

        hasLoadedPreflight = true
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
        others: [PreflightClientProject]
    ) -> [RelatedProjectRef] {
        var seen = Set<String>()
        var refs: [RelatedProjectRef] = []

        for c in candidates where seen.insert(c.projectId).inserted {
            refs.append(RelatedProjectRef(
                id: c.projectId,
                title: c.title ?? "",
                address: c.address,
                status: nil,
                isLikelyDuplicate: true
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

    private func createProject() {
        guard canCreate else { return }
        errorMessage = nil
        isSaving = true

        Task {
            do {
                let companyId = opportunity.companyId
                let service = LeadConversionService(companyId: companyId)

                // The unified convert RPC reads address/lat/lng from the
                // opportunity row — it has no address param. So if the operator
                // edited the address here, persist it to the opportunity FIRST
                // or the edit (and the derived name) is dropped server-side.
                let trimmedAddress = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
                let originalAddress = (opportunity.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedAddress != originalAddress {
                    let repo = OpportunityRepository(companyId: companyId)
                    _ = try? await repo.update(opportunity.id, patch: ["address": trimmedAddress])
                    // Mirror locally so the optimistic model + the lead summary
                    // stay coherent if the operator returns to this lead.
                    opportunity.address = trimmedAddress.isEmpty ? nil : trimmedAddress
                }

                let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                let project = try await service.convertOpportunityToProject(
                    lead: opportunity,
                    actualValue: parseActualValue(),
                    titleOverride: titleIsAuto ? nil : (trimmedTitle.isEmpty ? nil : trimmedTitle),
                    notes: closingNotes.isEmpty ? nil : closingNotes,
                    userId: dataController.currentUser?.id
                )

                completeConverted(projectId: project.id)
            } catch {
                if let conversionError = error as? LeadConversionError,
                   case let .projectCreatedButFetchFailed(projectId, _) = conversionError {
                    completeConverted(projectId: projectId)
                } else {
                    isSaving = false
                    errorMessage = simplifyError(error)
                }
            }
        }
    }

    private func completeConverted(projectId: String) {
        opportunity.stage = .won
        opportunity.actualValue = parseActualValue()
        opportunity.actualCloseDate = Date()
        opportunity.projectId = projectId
        opportunity.stageEnteredAt = Date()
        opportunity.stageManuallySet = true
        didCommitWon = true

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

    private func openExistingProjectAction() {
        guard let existing = existingProject else { return }
        errorMessage = nil
        isSaving = true
        let projectId = existing.id

        Task {
            // Idempotent mark-won — covers projects that pre-date stage tracking,
            // while preserving the existing project link so the lead leaves the
            // unconverted-won carousel.
            await markWonWithExistingProject(projectId)
            didCommitWon = true
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                appState.viewProjectDetailsById(projectId)
            }
        }
    }

    private func openExistingProject(_ projectId: String) {
        // CLIENT-HAS-OTHERS info chip — a non-committing review peek. The
        // operator is investigating a related project before deciding, NOT
        // converting this lead, so this exit must not mark the lead won.
        // didDismissForReview suppresses the onDisappear escape hatch; the
        // lead is left untouched and the operator can re-open convert later.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        didDismissForReview = true
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            appState.viewProjectDetailsById(projectId)
        }
    }

    private func commitNoProjectAndDismiss() async {
        guard !didCommitWon else {
            dismiss()
            return
        }
        didCommitWon = true
        isSaving = true
        await markWonNoProjectSilently()
        dismiss()
    }

    /// Idempotent — silent failure is acceptable here. If the network call
    /// errors we still want the sheet to close (the user already committed to
    /// winning the lead). The next sync will reconcile.
    private func markWonNoProjectSilently() async {
        let companyId = opportunity.companyId
        let service = LeadConversionService(companyId: companyId)
        let value = parseActualValue()
        do {
            try await service.markWonNoProject(
                lead: opportunity,
                actualValue: value,
                userId: dataController.currentUser?.id
            )
            opportunity.stage = .won
            opportunity.actualValue = value
            opportunity.actualCloseDate = Date()
            opportunity.stageEnteredAt = Date()
            opportunity.stageManuallySet = true

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(
                name: Notification.Name("LeadMarkedWonSuccess"),
                object: nil,
                userInfo: ["leadId": opportunity.id]
            )
        } catch {
            // Already on the won-no-project path — keep the dismissal flow
            // moving even if the server didn't accept the write. Sync engine
            // will replay.
            print("[CONVERT] markWonNoProject failed (will reconcile on sync): \(error)")
        }
    }

    /// Duplicate-state OPEN PROJECT still commits the won transition, but it
    /// must persist the existing project id. Otherwise the lead remains a
    /// "won but unconverted" item and the toast reads as no-project.
    private func markWonWithExistingProject(_ projectId: String) async {
        let companyId = opportunity.companyId
        let service = LeadConversionService(companyId: companyId)
        let value = parseActualValue()
        do {
            try await service.markWonWithExistingProject(
                lead: opportunity,
                projectId: projectId,
                actualValue: value,
                userId: dataController.currentUser?.id
            )
            opportunity.stage = .won
            opportunity.actualValue = value
            opportunity.actualCloseDate = Date()
            opportunity.projectId = projectId
            opportunity.stageEnteredAt = Date()
            opportunity.stageManuallySet = true

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(
                name: Notification.Name("LeadLinkedProjectSuccess"),
                object: nil,
                userInfo: [
                    "leadId": opportunity.id,
                    "projectId": projectId,
                ]
            )
        } catch {
            // Opening the existing project is still the right user-facing path;
            // the stage/link write will reconcile on the next successful sync.
            print("[CONVERT] markWonWithExistingProject failed (will reconcile on sync): \(error)")
        }
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

    private func simplifyError(_ error: Error) -> String {
        if let conversionError = error as? LeadConversionError {
            switch conversionError {
            case .opportunityNotFound: return "LEAD NOT FOUND"
            case .accessDenied: return "PERMISSION DENIED"
            case .projectCreatedButFetchFailed: return "PROJECT CREATED — REFRESH"
            }
        }
        let description = String(describing: error).lowercased()
        if description.contains("network") || description.contains("offline") {
            return "OFFLINE — TAP TO RETRY"
        }
        return "COULD NOT CREATE — TAP TO RETRY"
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

        /// Status color where known; neutral hairline otherwise.
        var statusColor: Color {
            status?.color ?? OPSStyle.Colors.textMute
        }
    }
}
