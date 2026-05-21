// OPS/OPS/DeckBuilder/Views/VinylOrderSheet.swift

import MessageUI
import SwiftData
import SwiftUI
import UIKit

struct VinylOrderSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    let projectId: String?
    let companyId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var projects: [Project]
    @Query private var catalogItems: [CatalogItem]
    @Query private var catalogVariants: [CatalogVariant]

    @State private var settings = VinylOrderSettings.default
    @State private var isCreating = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showingMessageComposer = false

    private var surfaceInputs: [VinylOrderSurfaceInput] {
        viewModel.selectedVinylOrderSurfaceInputs()
    }

    private var plan: VinylCutPlan {
        VinylCutListEngine.makePlan(surfaces: surfaceInputs, settings: settings)
    }

    private var project: Project? {
        guard let projectId else { return nil }
        return projects.first { $0.id == projectId }
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

    private var currentUserId: String? {
        SupabaseService.shared.currentUserId ?? UserDefaults.standard.string(forKey: "currentUserId")
    }

    private var canCreateOrder: Bool {
        projectId != nil && currentUserId != nil && !plan.surfaces.isEmpty && !isCreating
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
                            reuseSection
                            catalogSection
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
                    body: noteText,
                    recipients: smsRecipients,
                    onCompletion: { _ in
                        showingMessageComposer = false
                    }
                )
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
        } else if viewModel.selection.selectedSurfaceIds.isEmpty {
            banner(text: "SELECT A SURFACE", color: OPSStyle.Colors.warningStatus)
        } else if viewModel.drawingData.scaleFactor == nil {
            banner(text: "SET SCALE FIRST", color: OPSStyle.Colors.warningStatus)
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

                directionControl

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
                            Text("\(surface.stripCount) CUT\(surface.stripCount == 1 ? "" : "S") @ \(formatInchesForSheet(surface.stripLengthInches)) X \(formatInchesForSheet(surface.rollWidthInches)) / \(surface.resolvedDirection.label)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Text("\(formatSqFtForSheet(surface.cutAreaSqFt)) SQ FT")
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(OPSStyle.Colors.primaryText)
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
            if let match = vinylCatalogSelection {
                metricRow("LINE", match.item.name.uppercased())
                if let sku = match.variant.sku, !sku.isEmpty {
                    metricRow("SKU", sku.uppercased())
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CATALOG LINE MISSING")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                    Text("ORDER SAVES WITH CUT LIST NOTES ONLY.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                Label(MFMessageComposeViewController.canSendText() ? "TEXT CUT LIST" : "COPY TEXT", systemImage: "message.fill")
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

    private var smsRecipients: [String] {
        guard let phone = project?.effectiveClientPhone else { return [] }
        let cleaned = phone.filter { "0123456789+".contains($0) }
        return cleaned.isEmpty ? [] : [cleaned]
    }

    private var vinylCatalogSelection: (item: CatalogItem, variant: CatalogVariant)? {
        let pairs = catalogVariants.compactMap { variant -> (item: CatalogItem, variant: CatalogVariant)? in
            guard variant.companyId == companyId,
                  let item = catalogItems.first(where: { $0.id == variant.catalogItemId && $0.companyId == companyId }) else {
                return nil
            }
            return (item, variant)
        }
        let candidates = pairs.map { pair in
            VinylCatalogCandidate(
                itemId: pair.item.id,
                variantId: pair.variant.id,
                itemName: pair.item.name,
                itemDescription: pair.item.itemDescription,
                itemNotes: pair.item.notes,
                variantSku: pair.variant.sku,
                itemUnitId: pair.item.defaultUnitId,
                variantUnitId: pair.variant.unitId,
                isItemActive: pair.item.isActive,
                itemDeleted: pair.item.deletedAt != nil,
                isVariantActive: pair.variant.isActive,
                variantDeleted: pair.variant.deletedAt != nil
            )
        }

        guard let match = VinylCatalogMatcher.bestMatch(
            from: candidates,
            preferredRollWidthInches: settings.normalized.rollWidthInches
        ) else {
            return nil
        }

        return pairs.first { $0.item.id == match.itemId && $0.variant.id == match.variantId }
    }

    private func handleTextAction() {
        guard !plan.surfaces.isEmpty else { return }
        if MFMessageComposeViewController.canSendText() {
            showingMessageComposer = true
        } else {
            UIPasteboard.general.string = noteText
            statusMessage = "TEXT COPIED"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func beginCreateOrderAndNote() {
        guard canCreateOrder else { return }
        isCreating = true
        Task { await createOrderAndNote() }
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
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func drawSurface(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard let first = surface.positions.first else { return }
        var path = Path()
        path.move(to: map(first, bounds: bounds, origin: origin, scale: scale))
        for point in surface.positions.dropFirst() {
            path.addLine(to: map(point, bounds: bounds, origin: origin, scale: scale))
        }
        path.closeSubpath()

        context.fill(path, with: .color(OPSStyle.Colors.surfaceActive))
        context.stroke(path, with: .color(OPSStyle.Colors.secondaryText), lineWidth: OPSStyle.Layout.Border.standard)
        drawSeams(surface, in: &context, bounds: bounds, origin: origin, scale: scale)
    }

    private func drawSeams(
        _ surface: VinylSurfaceCutPlan,
        in context: inout GraphicsContext,
        bounds: CGRect,
        origin: CGPoint,
        scale: CGFloat
    ) {
        guard surface.stripCount > 1, let faceBounds = surfaceBounds(for: surface.positions) else { return }
        for index in 1..<surface.stripCount {
            let fraction = CGFloat(index) / CGFloat(surface.stripCount)
            var seam = Path()
            switch surface.runAxis {
            case .horizontal:
                let y = faceBounds.minY + (faceBounds.height * fraction)
                seam.move(to: map(CGPoint(x: faceBounds.minX, y: y), bounds: bounds, origin: origin, scale: scale))
                seam.addLine(to: map(CGPoint(x: faceBounds.maxX, y: y), bounds: bounds, origin: origin, scale: scale))
            case .vertical:
                let x = faceBounds.minX + (faceBounds.width * fraction)
                seam.move(to: map(CGPoint(x: x, y: faceBounds.minY), bounds: bounds, origin: origin, scale: scale))
                seam.addLine(to: map(CGPoint(x: x, y: faceBounds.maxY), bounds: bounds, origin: origin, scale: scale))
            }
            context.stroke(seam, with: .color(OPSStyle.Colors.secondaryText.opacity(0.72)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
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

    private func surfaceBounds(for points: [CGPoint]) -> CGRect? {
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

private enum VinylOrderLayout {
    static let previewHeight = CGFloat(OPSStyle.Layout.touchTargetLarge * 3)
    static let actionBarReserveHeight = CGFloat(OPSStyle.Layout.touchTargetStandard * 2)
    static let labelWidth = CGFloat(OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5)
    static let previewInset = CGFloat(OPSStyle.Layout.spacing3)
}

private struct VinylOrderMessageComposeView: UIViewControllerRepresentable {
    let body: String
    let recipients: [String]
    let onCompletion: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = body
        controller.recipients = recipients.isEmpty ? nil : recipients
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
