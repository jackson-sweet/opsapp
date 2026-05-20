//
//  ConvertToProjectSheet.swift
//  OPS
//
//  Full-detent sheet that lands when an operator commits to winning a lead.
//  Phase 4 of the LEADS tab rebuild
//  (docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §8.6) — RICH
//  variant.
//
//  Three render states are decided in `onAppear` against SwiftData + Supabase:
//
//    NORMAL              standard form (title, address, value, notes) + optional
//                        attached-estimates section + optional tasks-preview.
//    DUPLICATE-EXISTS    a Project already back-links to this lead. We surface
//                        the existing project and let the operator open it; no
//                        new project gets created.
//    CLIENT-HAS-OTHERS   the lead's client has other projects on file. Tan
//                        warning banner sits above the standard form; the
//                        operator can still create.
//
//  Exit semantics (plan §2.1 Q3, restated in the Phase 4 brief):
//
//    Every exit from this sheet marks the lead WON. The decision to win was
//    already committed when the operator tapped MARK WON →. This sheet only
//    asks "do you also want a project?". A `didCommitWon` flag prevents
//    double-firing.
//
//    × / CANCEL / drag / scrim    → markWonNoProject(actualValue)
//    CREATE PROJECT →             → convertLeadToProject(...), open project
//    OPEN PROJECT → (DUPLICATE)   → markWonNoProject, open existing project
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

    // MARK: - Pre-flight state

    /// nil = loading / unset. Non-nil project = DUPLICATE-EXISTS.
    @State private var existingProject: Project?
    @State private var clientOtherProjects: [Project] = []
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

    // MARK: - Computed

    private var renderState: RenderState {
        if existingProject != nil { return .duplicate }
        if !clientOtherProjects.isEmpty { return .clientHasOthers }
        return .normal
    }

    private var canCreate: Bool {
        !titleText.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSaving
    }

    private var totalLaborItems: Int {
        estimateBundles.reduce(0) { $0 + $1.laborItems.count }
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
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
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
            // and set didCommitWon = true, so we'd skip work here.
            guard !didCommitWon else { return }
            didCommitWon = true
            Task { await markWonNoProjectSilently() }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                SheetCloseButton {
                    Task { await commitNoProjectAndDismiss() }
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            SheetTitleLabel(title: "CONVERT → PROJECT")
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
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

    private func duplicateCard(existing: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

            HStack(spacing: 8) {
                StatusBadge(
                    status: existing.status.displayName.uppercased(),
                    color: existing.status.color,
                    size: .small
                )
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
        .padding(12)
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

    private func projectChip(_ project: Project) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(project.status.color)
                .frame(width: 5, height: 5)
            Text(truncatedTitle(project.title))
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .kerning(1.2)
                .foregroundColor(OPSStyle.Colors.text)
                .textCase(.uppercase)
            if let created = project.createdAt {
                Text("·")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(relativeText(for: created).uppercased())
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .kerning(1.0)
                    .foregroundColor(OPSStyle.Colors.text3)
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
    }

    private func truncatedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "UNTITLED" }
        return trimmed.count > 18 ? String(trimmed.prefix(17)) + "…" : trimmed
    }

    // MARK: - Form fields

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            LeadField(label: "TITLE") {
                LeadTextInput(
                    placeholder: opportunity.contactName,
                    text: $titleText
                )
            }

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

    // MARK: - Attached estimates

    private var attachedEstimatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            VStack(alignment: .leading, spacing: 4) {
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
        .padding(.horizontal, 12)
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
            .padding(.top, 4)
        }
    }

    private var allLaborItems: [EstimateLineItem] {
        estimateBundles.flatMap { $0.laborItems }
    }

    private func taskPreviewRow(_ item: EstimateLineItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
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
        .padding(.vertical, 12)
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
                    .padding(.horizontal, 20)
            } else if isSaving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 8) {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { Task { await commitNoProjectAndDismiss() } }
                )
                .frame(maxWidth: .infinity)
                .disabled(isSaving)

                if renderState == .duplicate {
                    SheetCTAButton(
                        label: "OPEN PROJECT",
                        icon: "arrow.right",
                        variant: .primary,
                        isLoading: isSaving,
                        action: { openExistingProjectAction() }
                    )
                    .frame(maxWidth: .infinity * 2)
                    .disabled(isSaving)
                } else {
                    SheetCTAButton(
                        label: "CREATE PROJECT",
                        icon: "arrow.right",
                        variant: .primary,
                        isLoading: isSaving,
                        action: createProject
                    )
                    .frame(maxWidth: .infinity * 2)
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.5)
                }
            }
            .padding(.horizontal, 20)
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

        // Local SwiftData checks (synchronous)
        existingProject = service.existingProject(for: opportunity, in: modelContext)
        clientOtherProjects = service.clientProjectsSummary(for: opportunity, in: modelContext)

        // Network fetch (estimates + line items)
        do {
            estimateBundles = try await service.estimateBundles(for: opportunity)
        } catch {
            // Non-fatal — operator can still create without the preview
            estimateBundles = []
        }

        hasLoadedPreflight = true
    }

    private func applyInitialFormValues() {
        if titleText.isEmpty {
            titleText = opportunity.title?.isEmpty == false
                ? opportunity.title!
                : opportunity.contactName
        }
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
                let project = try await service.convertLeadToProject(
                    lead: opportunity,
                    actualValue: parseActualValue(),
                    title: titleText.trimmingCharacters(in: .whitespaces),
                    address: addressText.isEmpty ? nil : addressText,
                    notes: closingNotes.isEmpty ? nil : closingNotes,
                    userId: dataController.currentUser?.id
                )

                // Mark local SwiftData immediately
                opportunity.stage = .won
                opportunity.actualValue = parseActualValue()
                opportunity.actualCloseDate = Date()
                opportunity.projectId = project.id
                opportunity.stageEnteredAt = Date()
                opportunity.stageManuallySet = true
                didCommitWon = true

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadConvertedSuccess"),
                    object: nil,
                    userInfo: [
                        "leadId": opportunity.id,
                        "projectId": project.id,
                    ]
                )
                let projectId = project.id
                dismiss()
                // Defer navigation so the sheet's dismiss animation completes
                // before AppState presents the project-details sheet.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    appState.viewProjectDetailsById(projectId)
                }
            } catch {
                isSaving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    private func openExistingProjectAction() {
        guard let existing = existingProject else { return }
        errorMessage = nil
        isSaving = true
        let projectId = existing.id

        Task {
            // Idempotent mark-won — covers projects that pre-date stage tracking.
            await markWonNoProjectSilently()
            didCommitWon = true
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                appState.viewProjectDetailsById(projectId)
            }
        }
    }

    private func openExistingProject(_ projectId: String) {
        // Tapping a chip in CLIENT-HAS-OTHERS — does NOT mark won (operator is
        // just browsing). Skip the commit, just navigate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            appState.viewProjectDetailsById(projectId)
        }
        // Sheet stays open so the operator can come back and create their new
        // project after reviewing.
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

    // MARK: - Helpers

    private func parseActualValue() -> Double? {
        let stripped = actualValueText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { return nil }
        return Double(stripped)
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
