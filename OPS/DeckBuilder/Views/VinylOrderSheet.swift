// OPS/OPS/DeckBuilder/Views/VinylOrderSheet.swift

import MessageUI
import Supabase
import SwiftData
import SwiftUI
import UIKit

struct VinylOrderSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    let projectId: String?
    let companyId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @Query private var projects: [Project]
    @Query private var vinylOrderMarkers: [ProjectVinylOrderMarker]
    @Query private var catalogItems: [CatalogItem]
    @Query private var catalogVariants: [CatalogVariant]
    @Query private var catalogOptionValues: [CatalogOptionValue]
    @Query private var catalogVariantOptionValues: [CatalogVariantOptionValue]

    @State private var settings = VinylOrderSettings.default
    @State private var isCreating = false
    @State private var isUpdatingProjectMarker = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showingMessageComposer = false
    @State private var surfaceInputs: [VinylOrderSurfaceInput] = []
    @State private var didLoadSurfaceInputs = false
    @State private var showingTemplateEditor = false
    @AppStorage(VinylCutListTextTemplate.messageStorageKey) private var messageTemplate = VinylCutListTextTemplate.defaultMessageTemplate
    @AppStorage(VinylCutListTextTemplate.cutStorageKey) private var cutTemplate = VinylCutListTextTemplate.defaultCutTemplate
    @AppStorage(VinylCutListTextTemplate.separatorStorageKey) private var cutSeparatorRawValue = VinylCutListSeparator.lines.rawValue

    private var plan: VinylCutPlan {
        VinylCutListEngine.makePlan(surfaces: surfaceInputs, settings: settings)
    }

    private var cutSeparator: VinylCutListSeparator {
        VinylCutListSeparator(rawValue: cutSeparatorRawValue) ?? .lines
    }

    private var project: Project? {
        guard let projectId else { return nil }
        return projects.first { $0.id == projectId }
    }

    private var projectVinylOrderMarker: ProjectVinylOrderMarker? {
        guard let projectId else { return nil }
        return vinylOrderMarkers.first { $0.projectId == projectId }
    }

    private var projectVinylOrderStatus: ProjectVinylOrderStatus {
        projectVinylOrderMarker?.status ?? .notOrdered
    }

    private var projectTitle: String {
        let trimmed = project?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.flatMap { $0.isEmpty ? nil : $0 } ?? "PROJECT"
    }

    private var deckTitle: String {
        let trimmed = viewModel.deckDesign.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "DECK DESIGN" : trimmed
    }

    private var noteText: String {
        plan.orderNotes(projectTitle: projectTitle, deckTitle: deckTitle)
    }

    private var messageText: String {
        plan.textMessageBody(
            messageTemplate: messageTemplate,
            cutTemplate: cutTemplate,
            cutSeparator: cutSeparator
        )
    }

    private var currentUserId: String? {
        SupabaseService.shared.currentUserId ?? UserDefaults.standard.string(forKey: "currentUserId")
    }

    private var canCreateOrder: Bool {
        projectId != nil
            && currentUserId != nil
            && !plan.surfaces.isEmpty
            && hasResolvedCatalogColor
            && !isCreating
    }

    private var canToggleProjectMarker: Bool {
        guard let project, let userId = currentUserId else { return false }
        return !ProjectAccessHelper.isMentionOnly(project, userId: userId)
            && PermissionStore.shared.isFeatureEnabled("deck_builder")
            && PermissionStore.shared.can("deck_builder.view", requiredScope: "assigned")
            && PermissionStore.shared.can("projects.edit")
            && !isUpdatingProjectMarker
    }

    private var catalogProductChoices: [VinylCatalogProductChoice] {
        let activeVariantsByItem = Dictionary(grouping: catalogVariants.filter { variant in
            variant.companyId == companyId
                && variant.isActive
                && variant.deletedAt == nil
        }, by: \.catalogItemId)

        return catalogItems
            .filter { item in
                item.companyId == companyId
                    && item.isActive
                    && item.deletedAt == nil
                    && !(activeVariantsByItem[item.id] ?? []).isEmpty
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { item in
                VinylCatalogProductChoice(
                    item: item,
                    variants: (activeVariantsByItem[item.id] ?? []).sorted { lhs, rhs in
                        variantDisplayName(lhs).localizedStandardCompare(variantDisplayName(rhs)) == .orderedAscending
                    }
                )
            }
    }

    private var selectedProductChoice: VinylCatalogProductChoice? {
        guard let itemId = settings.catalogItemId else { return nil }
        return catalogProductChoices.first { $0.id == itemId }
    }

    private var catalogProductChoicesSignature: String {
        catalogProductChoices.map(\.id).joined(separator: "|")
    }

    private var selectedVariant: CatalogVariant? {
        guard let variantId = settings.catalogVariantId else { return nil }
        return selectedProductChoice?.variants.first { $0.id == variantId }
    }

    private var hasResolvedCatalogColor: Bool {
        settings.catalogItemId == nil || selectedVariant != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            validationBanner
                            VinylCutPreview(plan: plan)
                                .frame(height: VinylOrderLayout.previewHeight)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )

                            controlsSection
                            summarySection
                            cutListSection
                            textTemplateSection
                            reuseSection
                            catalogSection
                            projectMarkerSection
                            statusSection

                            Color.clear.frame(height: VinylOrderLayout.actionBarReserveHeight)
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                }

                VStack {
                    Spacer()
                    actionBar
                }
            }
            .navigationTitle("// VINYL ORDER")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CLOSE") { dismiss() }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .sheet(isPresented: $showingMessageComposer) {
                VinylOrderMessageComposeView(
                    body: messageText,
                    onCompletion: { _ in
                        showingMessageComposer = false
                    }
                )
            }
            .task {
                await loadSurfaceInputsIfNeeded()
            }
            .onChange(of: catalogProductChoicesSignature) { _, _ in
                applyConfiguredCatalogProduct()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(alignment: .leading, spacing: 3) {
                Text("// VINYL ORDER")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1.1)
                Text("\(plan.surfaces.count) SURFACE\(plan.surfaces.count == 1 ? "" : "S") / \(plan.totalOrderedSqFt) SQ FT")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    @ViewBuilder
    private var validationBanner: some View {
        if projectId == nil {
            banner(text: "PROJECT LINK MISSING", color: OPSStyle.Colors.errorStatus)
        } else if viewModel.vinylOrderSurfaceScope == .selectedSurfaces && viewModel.selection.selectedSurfaceIds.isEmpty {
            banner(text: "SELECT A SURFACE", color: OPSStyle.Colors.warningStatus)
        } else if viewModel.vinylOrderEffectiveScale == nil {
            banner(text: "CONFIRM ONE EDGE LENGTH", color: OPSStyle.Colors.warningStatus)
        } else if settings.catalogItemId != nil && selectedVariant == nil {
            banner(text: "SELECT VINYL COLOR", color: OPSStyle.Colors.warningStatus)
        } else if plan.surfaces.isEmpty {
            banner(text: "NO ORDERABLE SURFACE FOUND", color: OPSStyle.Colors.warningStatus)
        }
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            Text(text)
                .font(OPSStyle.Typography.captionBold)
                .tracking(0.8)
            Spacer(minLength: 0)
        }
        .foregroundColor(color)
        .padding(OPSStyle.Layout.spacing2)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(color.opacity(0.45), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    private var controlsSection: some View {
        section(title: "SETTINGS") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if selectedProductChoice != nil {
                    catalogVariantPicker
                } else {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("COLOR")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)
                        TextField("FIELD CONFIRM", text: $settings.color)
                            .font(OPSStyle.Typography.body)
                            .textInputAutocapitalization(.words)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(OPSStyle.Colors.subtleBackground)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                }

                directionControl
                runLockControl

                settingStepper(
                    label: "ROLL",
                    value: $settings.rollWidthInches,
                    range: 24...144,
                    step: 6
                )
                settingStepper(
                    label: "SEAM",
                    value: $settings.seamOverlapInches,
                    range: 0...12,
                    step: 0.25
                )
                settingStepper(
                    label: "WRAP",
                    value: $settings.edgeWrapInches,
                    range: 0...18,
                    step: 0.5
                )
            }
        }
    }

    private var catalogVariantPicker: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("VARIANT")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)

            Picker("VARIANT", selection: Binding(
                get: { settings.catalogVariantId ?? "" },
                set: { selectCatalogVariant($0) }
            )) {
                Text("SELECT")
                    .tag("")
                ForEach(selectedProductChoice?.variants ?? []) { variant in
                    Text(variantDisplayName(variant).uppercased())
                        .tag(variant.id)
                }
            }
            .pickerStyle(.menu)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    private var runLockControl: some View {
        Toggle(isOn: Binding(
            get: { !settings.allowsDirectionalChanges },
            set: { settings.allowsDirectionalChanges = !$0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOCK RUN")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(settings.allowsDirectionalChanges ? "SOLID COLOR ONLY" : "ONE DIRECTION")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    private var directionControl: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("RUN")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(VinylLayoutDirection.allCases) { direction in
                    Button {
                        settings.direction = direction
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(direction.label)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(settings.direction == direction ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(settings.direction == direction ? OPSStyle.Colors.surfaceActive : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private func settingStepper(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)
                Text(formatInchesForSheet(value.wrappedValue))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 0)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    private var summarySection: some View {
        section(title: "SUMMARY") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                metricRow("ORDER AREA", "\(plan.totalOrderedSqFt) SQ FT")
                metricRow("SURFACE AREA", "\(formatSqFtForSheet(plan.totalSurfaceAreaSqFt)) SQ FT")
                if plan.totalReusedCutAreaSqFt > 0 {
                    metricRow("REUSED AREA", "\(formatSqFtForSheet(plan.totalReusedCutAreaSqFt)) SQ FT")
                }
                metricRow("CUT WASTE", "\(formatSqFtForSheet(plan.totalWasteSqFt)) SQ FT")
                metricRow("CUTS", "\(plan.totalStripCount)")
            }
        }
    }

    private var cutListSection: some View {
        section(title: "CUT LIST") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if plan.surfaces.isEmpty {
                    emptyLine("—")
                } else {
                    ForEach(plan.surfaces) { surface in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(surface.displayLabel.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            ForEach(VinylCutGroup.groups(from: surface.cuts)) { group in
                                Text(group.displayLine)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(group.isPurchased ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.tan)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                }
            }
        }
    }

    private var textTemplateSection: some View {
        section(title: "TEXT TEMPLATE") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Button {
                    showingTemplateEditor.toggle()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        Text(showingTemplateEditor ? "HIDE TEMPLATE" : "EDIT TEMPLATE")
                            .font(OPSStyle.Typography.buttonLabel)
                        Spacer(minLength: 0)
                        Image(systemName: showingTemplateEditor ? "chevron.up" : "chevron.down")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                }
                .buttonStyle(.plain)

                if showingTemplateEditor {
                    templateEditor(label: "MESSAGE", text: $messageTemplate, minHeight: VinylOrderLayout.templateEditorHeight)

                    templateEditor(label: "CUT ROW", text: $cutTemplate, minHeight: VinylOrderLayout.cutTemplateEditorHeight)

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text("JOIN")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            ForEach(VinylCutListSeparator.allCases) { separator in
                                Button {
                                    cutSeparatorRawValue = separator.rawValue
                                } label: {
                                    Text(separator.label)
                                        .font(OPSStyle.Typography.buttonLabel)
                                        .foregroundColor(cutSeparator == separator ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, OPSStyle.Layout.spacing2)
                                        .background(cutSeparator == separator ? OPSStyle.Colors.primaryAccent.opacity(0.18) : OPSStyle.Colors.subtleBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(
                                                    cutSeparator == separator ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder,
                                                    lineWidth: OPSStyle.Layout.Border.standard
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MESSAGE: [color] [cuts] [cut_count]")
                            Text("CUT: [quantity] [length] [surface]")
                        }
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("RESET") {
                            messageTemplate = VinylCutListTextTemplate.defaultMessageTemplate
                            cutTemplate = VinylCutListTextTemplate.defaultCutTemplate
                            cutSeparatorRawValue = VinylCutListSeparator.lines.rawValue
                        }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func templateEditor(label: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            TextEditor(text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .padding(OPSStyle.Layout.spacing2)
                .frame(minHeight: minHeight)
                .background(OPSStyle.Colors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    private var reuseSection: some View {
        section(title: "OFFCUT REUSE") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                if plan.reuseNotes.isEmpty {
                    emptyLine("NO FULL-SURFACE REUSE FOUND. KEEP LONG OFFCUTS.")
                } else {
                    ForEach(Array(plan.reuseNotes.enumerated()), id: \.offset) { _, note in
                        Text(note.line)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.tanSoft)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                }
            }
        }
    }

    private var catalogSection: some View {
        section(title: "CATALOG") {
            if let choice = selectedProductChoice {
                metricRow("PRODUCT", choice.item.name.uppercased())
                if let variant = selectedVariant {
                    metricRow("VARIANT", variantDisplayName(variant).uppercased())
                    if let sku = variant.sku, !sku.isEmpty {
                        metricRow("SKU", sku.uppercased())
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VARIANT NOT SELECTED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                        Text("SELECT A VARIANT TO WRITE A CATALOG ITEM.")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NO PRODUCT SELECTED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("COLOR STAYS FIELD TEXT. NO CATALOG ITEM IS WRITTEN.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var projectMarkerSection: some View {
        if PermissionStore.shared.isFeatureEnabled("deck_builder")
            && PermissionStore.shared.can("deck_builder.view", requiredScope: "assigned") {
            section(title: "PROJECT MARKER") {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("VINYL")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(projectVinylOrderStatus.displayLabel)
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(projectVinylOrderStatus == .ordered ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryText)
                        }

                        Spacer(minLength: 0)

                        Button {
                            setProjectVinylOrdered(projectVinylOrderStatus != .ordered)
                        } label: {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                if isUpdatingProjectMarker {
                                    ProgressView()
                                        .tint(OPSStyle.Colors.primaryText)
                                }
                                Text(projectVinylOrderStatus == .ordered ? "CLEAR ORDERED" : "MARK ORDERED")
                                    .font(OPSStyle.Typography.buttonLabel)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.surfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canToggleProjectMarker)
                        .opacity(canToggleProjectMarker ? 1 : 0.45)
                    }

                    if let orderedAt = projectVinylOrderMarker?.orderedAt, projectVinylOrderStatus == .ordered {
                        Text("ORDERED \(DateHelper.simpleDateString(from: orderedAt).uppercased())")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let statusMessage {
            banner(text: statusMessage, color: OPSStyle.Colors.successStatus)
        } else if let errorMessage {
            banner(text: errorMessage, color: OPSStyle.Colors.errorStatus)
        }
    }

    private var actionBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                handleTextAction()
            } label: {
                Label(MFMessageComposeViewController.canSendText() ? "TEXT CUTS" : "COPY CUTS", systemImage: "message.fill")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(.plain)
            .disabled(plan.surfaces.isEmpty)

            Button {
                beginCreateOrderAndNote()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if isCreating {
                        ProgressView()
                            .tint(OPSStyle.Colors.background)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text("CREATE ORDER + NOTE")
                }
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .background(canCreateOrder ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(!canCreateOrder)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background.opacity(0.96))
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer(minLength: 0)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectCatalogVariant(_ rawVariantId: String) {
        let variantId = rawVariantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !variantId.isEmpty,
              let variant = selectedProductChoice?.variants.first(where: { $0.id == variantId }) else {
            settings.catalogVariantId = nil
            settings.color = ""
            return
        }
        settings.catalogVariantId = variant.id
        settings.color = variantDisplayName(variant)
    }

    private func variantDisplayName(_ variant: CatalogVariant) -> String {
        let optionValueIds = catalogVariantOptionValues
            .filter { $0.variantId == variant.id }
            .map(\.optionValueId)
        let optionValues = catalogOptionValues
            .filter { optionValueIds.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.value.localizedStandardCompare(rhs.value) == .orderedAscending
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .map(\.value)

        if !optionValues.isEmpty {
            return optionValues.joined(separator: " / ")
        }
        if let sku = variant.sku?.trimmingCharacters(in: .whitespacesAndNewlines), !sku.isEmpty {
            return sku
        }
        return "VARIANT"
    }

    private var vinylCatalogSelection: (item: CatalogItem, variant: CatalogVariant)? {
        guard let itemId = settings.catalogItemId,
              let variantId = settings.catalogVariantId,
              let item = catalogItems.first(where: {
                  $0.id == itemId
                      && $0.companyId == companyId
                      && $0.isActive
                      && $0.deletedAt == nil
              }),
              let variant = catalogVariants.first(where: {
                  $0.id == variantId
                      && $0.catalogItemId == item.id
                      && $0.companyId == companyId
                      && $0.isActive
                      && $0.deletedAt == nil
              }) else {
            return nil
        }
        return (item, variant)
    }

    private func handleTextAction() {
        guard !plan.surfaces.isEmpty else { return }
        if MFMessageComposeViewController.canSendText() {
            showingMessageComposer = true
        } else {
            UIPasteboard.general.string = messageText
            statusMessage = "CUTS COPIED"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func setProjectVinylOrdered(_ ordered: Bool) {
        guard canToggleProjectMarker, let projectId, let userId = currentUserId else { return }

        let now = Date()
        let fields: [String: AnyJSON]
        if ordered {
            fields = [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.ordered.rawValue),
                ProjectVinylOrderFields.orderedAt: .string(SupabaseDate.format(now)),
                ProjectVinylOrderFields.orderedBy: .string(userId)
            ]
        } else {
            fields = [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.notOrdered.rawValue),
                ProjectVinylOrderFields.orderedAt: .null,
                ProjectVinylOrderFields.orderedBy: .null
            ]
        }

        isUpdatingProjectMarker = true
        statusMessage = nil
        errorMessage = nil

        Task {
            do {
                try await dataController.updateProjectFields(projectId: projectId, fields: fields)
                await MainActor.run {
                    isUpdatingProjectMarker = false
                    statusMessage = ordered ? "VINYL MARKED ORDERED" : "VINYL MARK CLEARED"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                print("[VinylOrderSheet] Vinyl marker update failed: \(error)")
                await MainActor.run {
                    isUpdatingProjectMarker = false
                    errorMessage = "VINYL STATUS FAILED"
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func beginCreateOrderAndNote() {
        guard canCreateOrder else { return }
        isCreating = true
        Task { await createOrderAndNote() }
    }

    @MainActor
    private func loadSurfaceInputsIfNeeded() async {
        guard !didLoadSurfaceInputs else { return }
        didLoadSurfaceInputs = true
        // This reconciles @Published deck state; keep it out of SwiftUI's body pass.
        await Task.yield()
        applyConfiguredCatalogProduct()
        surfaceInputs = viewModel.vinylOrderSurfaceInputs(scope: viewModel.vinylOrderSurfaceScope)
    }

    private func applyConfiguredCatalogProduct() {
        guard settings.catalogItemId == nil,
              let configuredItemId = viewModel.drawingData.config.vinylCatalogItemId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !configuredItemId.isEmpty,
              catalogProductChoices.contains(where: { $0.id == configuredItemId }) else {
            return
        }
        settings.catalogItemId = configuredItemId
        settings.catalogVariantId = nil
        settings.color = ""
    }

    @MainActor
    private func createOrderAndNote() async {
        defer { isCreating = false }

        guard let projectId else {
            errorMessage = "PROJECT LINK MISSING"
            return
        }
        guard let userId = currentUserId else {
            errorMessage = "USER MISSING"
            return
        }

        let draftPlan = plan
        let draftSettings = settings.normalized
        let draftNoteText = draftPlan.orderNotes(projectTitle: projectTitle, deckTitle: deckTitle)
        let draftProjectTitle = projectTitle
        let draftCatalogSelection = vinylCatalogSelection

        guard !draftPlan.surfaces.isEmpty else {
            errorMessage = "NO CUT LIST"
            return
        }

        statusMessage = nil
        errorMessage = nil

        let orderRepo = CatalogOrderRepository(companyId: companyId)
        var createdOrderDTO: CatalogOrderDTO?
        var createdItemDTO: CatalogOrderItemDTO?
        let createdNoteDTO: ProjectNoteDTO

        do {
            let orderDTO = try await orderRepo.createOrder(CreateCatalogOrderDTO(
                companyId: companyId,
                status: CatalogOrderStatus.draft.rawValue,
                title: "VINYL ORDER - \(draftProjectTitle)",
                supplierName: nil,
                supplierContact: nil,
                expectedDeliveryDate: nil,
                notes: draftNoteText,
                createdById: userId
            ))
            createdOrderDTO = orderDTO

            if let match = draftCatalogSelection {
                let quantity = Double(draftPlan.totalOrderedSqFt)
                createdItemDTO = try await orderRepo.addItem(
                    orderId: orderDTO.id,
                    dto: CreateCatalogOrderItemDTO(
                        orderId: orderDTO.id,
                        catalogVariantId: match.variant.id,
                        quantityRequested: quantity,
                        costPerUnit: match.variant.unitCostOverride ?? match.item.defaultUnitCost,
                        notes: "VINYL CUT LIST - \(draftSettings.color.isEmpty ? "FIELD CONFIRM" : draftSettings.color)"
                    )
                )
            }

            createdNoteDTO = try await ProjectNoteRepository(companyId: companyId).create(CreateProjectNoteDTO(
                projectId: projectId,
                companyId: companyId,
                authorId: userId,
                content: "\(draftNoteText)\n\nORDER DRAFT: \(orderDTO.id)",
                mentionedUserIds: []
            ))
        } catch {
            if let itemId = createdItemDTO?.id {
                try? await orderRepo.removeItem(itemId)
            }
            if let orderId = createdOrderDTO?.id {
                try? await orderRepo.softDeleteOrder(orderId)
            }
            print("[VinylOrderSheet] Order create failed: \(error)")
            errorMessage = "ORDER FAILED"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        var localSaveFailed = false
        do {
            if let createdOrderDTO {
                modelContext.insert(createdOrderDTO.toModel())
            }
            if let createdItemDTO {
                modelContext.insert(createdItemDTO.toModel())
            }
            modelContext.insert(createdNoteDTO.toModel())
            try modelContext.save()
        } catch {
            localSaveFailed = true
            print("[VinylOrderSheet] Local save failed after remote order create: \(error)")
        }

        var railFailed = false
        do {
            try await NotificationRepository.shared.createNotification(
                NotificationRepository.CreateNotificationDTO(
                    userId: userId,
                    companyId: companyId,
                    type: "catalog_order_drafted",
                    title: "// VINYL ORDER DRAFTED",
                    body: "\(draftProjectTitle.uppercased()) · \(draftPlan.totalOrderedSqFt) SQ FT READY",
                    projectId: projectId,
                    noteId: createdNoteDTO.id,
                    deepLinkType: "catalogOrders",
                    persistent: false,
                    actionUrl: "ops://catalog/orders?tab=draft",
                    actionLabel: "REVIEW"
                )
            )
        } catch {
            railFailed = true
            print("[VinylOrderSheet] Notification insert failed: \(error)")
        }

        if localSaveFailed {
            statusMessage = "ORDER DRAFTED / LOCAL SYNC PENDING"
        } else if railFailed {
            statusMessage = "ORDER DRAFTED / RAIL FAILED"
        } else {
            statusMessage = "ORDER DRAFTED"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func formatInchesForSheet(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))\""
        }
        return String(format: "%.1f\"", rounded)
    }

    private func formatSqFtForSheet(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct VinylCutPreview: View {
    let plan: VinylCutPlan

    var body: some View {
        Canvas { context, size in
            guard let bounds = sourceBounds, bounds.width > 0, bounds.height > 0 else {
                drawEmpty(in: &context, size: size)
                return
            }

            let target = CGRect(
                x: VinylOrderLayout.previewInset,
                y: VinylOrderLayout.previewInset,
                width: max(1, size.width - (VinylOrderLayout.previewInset * 2)),
                height: max(1, size.height - (VinylOrderLayout.previewInset * 2))
            )
            let scale = min(target.width / bounds.width, target.height / bounds.height)
            let fitted = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let origin = CGPoint(
                x: target.midX - fitted.width / 2,
                y: target.midY - fitted.height / 2
            )

            for surface in plan.surfaces {
                drawSurface(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vinyl cut preview")
    }

    private var sourceBounds: CGRect? {
        let points = plan.surfaces.flatMap(\.positions)
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let reserve = plan.surfaces
            .map { max(CGFloat(plan.settings.edgeWrapInches * surfaceScale($0) * 4), CGFloat(OPSStyle.Layout.spacing4)) }
            .max() ?? CGFloat(OPSStyle.Layout.spacing4)
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
            .insetBy(dx: -reserve, dy: -reserve)
    }

    private func drawSurface(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard let path = surfacePath(for: surface.positions, bounds: bounds, origin: origin, scale: scale) else { return }

        drawOverlapBands(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
        context.fill(path, with: .color(OPSStyle.Colors.surfaceActive.opacity(0.42)))
        drawCuts(surface, clippedTo: path, in: &context, bounds: bounds, origin: origin, scale: scale)
        context.stroke(path, with: .color(OPSStyle.Colors.secondaryText), lineWidth: OPSStyle.Layout.Border.standard)
        drawHouseEdgeLabels(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
        drawOverlapLeaders(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
    }

    private func drawOverlapBands(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard plan.settings.edgeWrapInches > 0 else { return }
        let wrapCanvas = CGFloat(plan.settings.edgeWrapInches * surfaceScale(surface))

        for layout in edgeLayouts(for: surface) {
            let start = map(layout.edge.start, bounds: bounds, origin: origin, scale: scale)
            let end = map(layout.edge.end, bounds: bounds, origin: origin, scale: scale)
            let outerStartSource = offset(layout.edge.start, normal: layout.outwardNormal, distance: wrapCanvas)
            let outerEndSource = offset(layout.edge.end, normal: layout.outwardNormal, distance: wrapCanvas)
            let outerStart = map(outerStartSource, bounds: bounds, origin: origin, scale: scale)
            let outerEnd = map(outerEndSource, bounds: bounds, origin: origin, scale: scale)

            var band = Path()
            band.move(to: start)
            band.addLine(to: end)
            band.addLine(to: outerEnd)
            band.addLine(to: outerStart)
            band.closeSubpath()
            context.fill(band, with: .color(overlapFill(for: layout.edge.edgeType)))

            var outerLine = Path()
            outerLine.move(to: outerStart)
            outerLine.addLine(to: outerEnd)
            context.stroke(
                outerLine,
                with: .color(overlapStroke(for: layout.edge.edgeType)),
                style: StrokeStyle(lineWidth: OPSStyle.Layout.Border.standard, dash: [4, 3])
            )
        }
    }

    private func drawHouseEdgeLabels(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        for layout in edgeLayouts(for: surface) where layout.edge.edgeType == .houseEdge {
            let midpoint = midpoint(layout.edge.start, layout.edge.end)
            let insideSource = offset(midpoint, normal: layout.outwardNormal, distance: -CGFloat(OPSStyle.Layout.spacing2) / max(scale, 0.001))
            let label = Text("HOUSE EDGE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tan)
            context.draw(label, at: map(insideSource, bounds: bounds, origin: origin, scale: scale), anchor: .center)
        }
    }

    private func drawOverlapLeaders(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard plan.settings.edgeWrapInches > 0 else { return }
        let layouts = edgeLayouts(for: surface)

        if let deckLayout = representativeLayout(in: layouts, type: .deckEdge) {
            drawOverlapLeader(
                "DECK LAP \(formatOverlapInches(plan.settings.edgeWrapInches))",
                layout: deckLayout,
                color: OPSStyle.Colors.secondaryText,
                in: &context,
                bounds: bounds,
                origin: origin,
                scale: scale
            )
        }

        if let houseLayout = representativeLayout(in: layouts, type: .houseEdge) {
            drawOverlapLeader(
                "HOUSE LAP \(formatOverlapInches(plan.settings.edgeWrapInches))",
                layout: houseLayout,
                color: OPSStyle.Colors.tan,
                in: &context,
                bounds: bounds,
                origin: origin,
                scale: scale
            )
        }
    }

    private func drawOverlapLeader(
        _ label: String,
        layout: VinylPreviewEdgeLayout,
        color: Color,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        let wrapCanvas = CGFloat(plan.settings.edgeWrapInches * surfaceScale(layout.surface))
        let edgeMidpoint = midpoint(layout.edge.start, layout.edge.end)
        let anchorSource = offset(edgeMidpoint, normal: layout.outwardNormal, distance: wrapCanvas)
        let labelSource = offset(edgeMidpoint, normal: layout.outwardNormal, distance: wrapCanvas + (CGFloat(OPSStyle.Layout.spacing3) / max(scale, 0.001)))
        let anchor = map(anchorSource, bounds: bounds, origin: origin, scale: scale)
        let labelPoint = map(labelSource, bounds: bounds, origin: origin, scale: scale)

        var leader = Path()
        leader.move(to: anchor)
        leader.addLine(to: labelPoint)
        context.stroke(leader, with: .color(color.opacity(0.82)), lineWidth: OPSStyle.Layout.Border.standard)

        context.draw(
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(color),
            at: labelPoint,
            anchor: .center
        )
    }

    private func drawCuts(
        _ surface: VinylSurfaceCutPlan,
        clippedTo clipPath: Path,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard !surface.cuts.isEmpty else { return }

        var clipped = context
        clipped.clip(to: clipPath)

        for (index, cut) in surface.cuts.enumerated() {
            guard let cutPath = cutPath(for: cut, surface: surface, bounds: bounds, origin: origin, scale: scale) else {
                continue
            }

            let fill = cutFillColor(cut: cut, index: index)
            let stroke = cut.isPurchased ? OPSStyle.Colors.primaryAccent.opacity(0.78) : OPSStyle.Colors.tan
            clipped.fill(cutPath, with: .color(fill))
            clipped.stroke(cutPath, with: .color(stroke), style: StrokeStyle(lineWidth: 1, dash: cut.isPurchased ? [] : [5, 4]))

            let label = Text(vinylFormatFeetAndInches(cut.lengthInches))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(cut.isPurchased ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tan)
            clipped.draw(label, at: labelPoint(for: cut, surface: surface, bounds: bounds, origin: origin, scale: scale), anchor: .center)
        }
    }

    private func cutFillColor(cut: VinylCutPiece, index: Int) -> Color {
        if cut.isPurchased {
            return OPSStyle.Colors.primaryAccent.opacity(index.isMultiple(of: 2) ? 0.18 : 0.10)
        }
        return OPSStyle.Colors.tanSoft.opacity(index.isMultiple(of: 2) ? 0.95 : 0.72)
    }

    private func cutPath(
        for cut: VinylCutPiece,
        surface: VinylSurfaceCutPlan,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> Path? {
        guard cut.runEndInches > cut.runStartInches,
              cut.bandEndInches > cut.bandStartInches else { return nil }

        let corners = [
            previewPoint(run: cut.runStartInches, cross: cut.bandStartInches, axis: cut.runAxis, surface: surface, bounds: bounds, origin: origin, scale: scale),
            previewPoint(run: cut.runEndInches, cross: cut.bandStartInches, axis: cut.runAxis, surface: surface, bounds: bounds, origin: origin, scale: scale),
            previewPoint(run: cut.runEndInches, cross: cut.bandEndInches, axis: cut.runAxis, surface: surface, bounds: bounds, origin: origin, scale: scale),
            previewPoint(run: cut.runStartInches, cross: cut.bandEndInches, axis: cut.runAxis, surface: surface, bounds: bounds, origin: origin, scale: scale)
        ]

        var path = Path()
        path.move(to: corners[0])
        for point in corners.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func labelPoint(
        for cut: VinylCutPiece,
        surface: VinylSurfaceCutPlan,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        previewPoint(
            run: (cut.runStartInches + cut.runEndInches) / 2,
            cross: (cut.bandStartInches + cut.bandEndInches) / 2,
            axis: cut.runAxis,
            surface: surface,
            bounds: bounds,
            origin: origin,
            scale: scale
        )
    }

    private func previewPoint(
        run: Double,
        cross: Double,
        axis: VinylRunAxis,
        surface: VinylSurfaceCutPlan,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        let point: CGPoint
        switch axis {
        case .horizontal:
            point = CGPoint(x: run * surfaceScale(surface), y: cross * surfaceScale(surface))
        case .vertical:
            point = CGPoint(x: cross * surfaceScale(surface), y: run * surfaceScale(surface))
        }
        return map(point, bounds: bounds, origin: origin, scale: scale)
    }

    private func surfaceScale(_ surface: VinylSurfaceCutPlan) -> Double {
        guard let faceBounds = rawSurfaceBounds(for: surface.positions), surface.boundingWidthInches > 0 else {
            return 1
        }
        return Double(faceBounds.width) / surface.boundingWidthInches
    }

    private func surfacePath(
        for points: [CGPoint],
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> Path? {
        guard let first = points.first else { return nil }
        var path = Path()
        path.move(to: map(first, bounds: bounds, origin: origin, scale: scale))
        for point in points.dropFirst() {
            path.addLine(to: map(point, bounds: bounds, origin: origin, scale: scale))
        }
        path.closeSubpath()
        return path
    }

    private func edgeLayouts(for surface: VinylSurfaceCutPlan) -> [VinylPreviewEdgeLayout] {
        previewEdges(for: surface).compactMap { edge in
            let dx = edge.end.x - edge.start.x
            let dy = edge.end.y - edge.start.y
            let length = CGFloat(sqrt(Double((dx * dx) + (dy * dy))))
            guard length > 0 else { return nil }
            return VinylPreviewEdgeLayout(
                surface: surface,
                edge: edge,
                outwardNormal: outwardNormal(for: edge, surface: surface),
                length: length
            )
        }
    }

    private func previewEdges(for surface: VinylSurfaceCutPlan) -> [VinylOrderSurfaceEdge] {
        if !surface.edges.isEmpty { return surface.edges }
        guard surface.positions.count >= 2 else { return [] }
        return surface.positions.indices.map { index in
            let nextIndex = (index + 1) % surface.positions.count
            return VinylOrderSurfaceEdge(
                id: "\(surface.id)-edge-\(index)",
                start: surface.positions[index],
                end: surface.positions[nextIndex],
                edgeType: .deckEdge,
                label: nil
            )
        }
    }

    private func outwardNormal(for edge: VinylOrderSurfaceEdge, surface: VinylSurfaceCutPlan) -> CGVector {
        let dx = edge.end.x - edge.start.x
        let dy = edge.end.y - edge.start.y
        let length = CGFloat(sqrt(Double((dx * dx) + (dy * dy))))
        guard length > 0 else { return .zero }

        let normalA = CGVector(dx: dy / length, dy: -dx / length)
        let normalB = CGVector(dx: -normalA.dx, dy: -normalA.dy)
        let mid = midpoint(edge.start, edge.end)
        let probeDistance = CGFloat(OPSStyle.Layout.spacing2)
        let probeA = offset(mid, normal: normalA, distance: probeDistance)

        return PolygonMath.pointInPolygon(probeA, vertices: surface.positions) ? normalB : normalA
    }

    private func representativeLayout(
        in layouts: [VinylPreviewEdgeLayout],
        type: EdgeType
    ) -> VinylPreviewEdgeLayout? {
        layouts
            .filter { $0.edge.edgeType == type }
            .max { $0.length < $1.length }
    }

    private func overlapFill(for edgeType: EdgeType) -> Color {
        switch edgeType {
        case .houseEdge:
            return OPSStyle.Colors.tanSoft.opacity(0.86)
        case .deckEdge:
            return OPSStyle.Colors.surfaceActive.opacity(0.72)
        }
    }

    private func overlapStroke(for edgeType: EdgeType) -> Color {
        switch edgeType {
        case .houseEdge:
            return OPSStyle.Colors.tan.opacity(0.82)
        case .deckEdge:
            return OPSStyle.Colors.secondaryText.opacity(0.64)
        }
    }

    private func midpoint(_ start: CGPoint, _ end: CGPoint) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    private func offset(_ point: CGPoint, normal: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: point.x + (normal.dx * distance), y: point.y + (normal.dy * distance))
    }

    private func formatOverlapInches(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))\""
        }
        return String(format: "%.1f\"", rounded)
    }

    private func drawEmpty(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(
            x: VinylOrderLayout.previewInset,
            y: VinylOrderLayout.previewInset,
            width: max(1, size.width - (VinylOrderLayout.previewInset * 2)),
            height: max(1, size.height - (VinylOrderLayout.previewInset * 2))
        )
        let path = Path(roundedRect: rect, cornerRadius: OPSStyle.Layout.cornerRadius)
        context.stroke(path, with: .color(OPSStyle.Colors.cardBorder), lineWidth: 1)
    }

    private func rawSurfaceBounds(for points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func map(
        _ point: CGPoint,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: origin.x + ((point.x - bounds.minX) * scale),
            y: origin.y + ((point.y - bounds.minY) * scale)
        )
    }
}

private struct VinylPreviewEdgeLayout {
    let surface: VinylSurfaceCutPlan
    let edge: VinylOrderSurfaceEdge
    let outwardNormal: CGVector
    let length: CGFloat
}

private struct VinylCatalogProductChoice: Identifiable {
    let item: CatalogItem
    let variants: [CatalogVariant]

    var id: String { item.id }
}

private enum VinylOrderLayout {
    static let previewHeight = CGFloat(OPSStyle.Layout.touchTargetLarge * 3)
    static let actionBarReserveHeight = CGFloat(OPSStyle.Layout.touchTargetStandard * 2)
    static let labelWidth = CGFloat(OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5)
    static let previewInset = CGFloat(OPSStyle.Layout.spacing3)
    static let templateEditorHeight = CGFloat(OPSStyle.Layout.touchTargetLarge * 2)
    static let cutTemplateEditorHeight = CGFloat(OPSStyle.Layout.touchTargetLarge)
}

private struct VinylOrderMessageComposeView: UIViewControllerRepresentable {
    let body: String
    let onCompletion: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = body
        controller.recipients = nil
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onCompletion: (MessageComposeResult) -> Void

        init(onCompletion: @escaping (MessageComposeResult) -> Void) {
            self.onCompletion = onCompletion
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onCompletion(result)
        }
    }
}
