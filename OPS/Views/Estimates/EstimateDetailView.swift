//
//  EstimateDetailView.swift
//  OPS
//
//  Full detail for one estimate — line items, totals, and context-dependent action footer.
//

import SwiftUI
import SwiftData

struct EstimateDetailView: View {
    var estimate: Estimate
    @ObservedObject var viewModel: EstimateViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showConvertOptions = false
    @State private var showProgressInvoice = false
    @State private var showOverflowMenu = false
    @State private var showBreakdown = false
    @Query(sort: \TaskType.displayOrder) private var taskTypes: [TaskType]

    private var lineItems: [EstimateLineItem] {
        viewModel.lineItems(for: estimate.id)
    }

    private var parentItems: [EstimateLineItem] {
        lineItems.filter { $0.parentLineItemId == nil }
    }

    private func childItems(for parentId: String) -> [EstimateLineItem] {
        lineItems.filter { $0.parentLineItemId == parentId }
    }

    private func taskTypeColor(for taskTypeId: String?) -> Color? {
        guard let id = taskTypeId else { return nil }
        guard let tt = taskTypes.first(where: { $0.id == id && $0.deletedAt == nil }) else { return nil }
        return Color(hex: tt.color)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    approvalStateBanner
                    lineItemsSection
                    totalsSection
                }
                .padding(.bottom, 100) // footer clearance
            }

            // Sticky footer
            stickyFooter
        }
        .trackScreen("EstimateDetail")
        .navigationBarTitleDisplayMode(.inline)
        .hidesGlobalTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showOverflowMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .confirmationDialog("", isPresented: $showOverflowMenu) {
            if estimate.status == .draft {
                Button("Edit Estimate") { showEditSheet = true }
                Button("Send Estimate") {
                    Task { await viewModel.sendEstimate(estimate) }
                }
            }
            if estimate.status == .sent || estimate.status == .viewed {
                if viewModel.approvalState(for: estimate.id).isSubmitting {
                    Button("Accepting") {}
                } else {
                    Button("Mark Approved") {
                        Task { await viewModel.markApproved(estimate) }
                    }
                }
            }
            if estimate.status == .approved {
                Button("Convert to Invoice") { showConvertOptions = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Convert to Invoice", isPresented: $showConvertOptions) {
            Button("Invoice Full Amount") {
                Task {
                    await viewModel.convertToInvoice(estimate)
                    dismiss()
                }
            }
            Button("Progress Invoice") {
                showProgressInvoice = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showProgressInvoice) {
            ProgressInvoiceSheet(
                estimate: estimate,
                lineItems: viewModel.lineItems(for: estimate.id),
                onCreateInvoice: { selections in
                    let success = await viewModel.createProgressInvoice(
                        from: estimate,
                        lineItemSelections: selections
                    )
                    if success {
                        showProgressInvoice = false
                    }
                    return success
                }
            )
        }
        .sheet(isPresented: $showEditSheet) {
            EstimateFormSheet(viewModel: viewModel, editing: estimate)
        }
        .errorToast($viewModel.error, label: Feedback.Err.operationFailed)
    }

    @ViewBuilder
    private var approvalStateBanner: some View {
        switch viewModel.approvalState(for: estimate.id) {
        case .idle:
            EmptyView()
        case .submitting:
            approvalBanner(
                title: "SYS :: ACCEPTING",
                message: "Server is booking the job.",
                color: OPSStyle.Colors.primaryAccent
            )
        case .accepted(
            _,
            let inventoryMode,
            let warningCount,
            let missingMappingCount,
            let overrunCount,
            let overrunDetails,
            let idempotentReplay
        ):
            // Booked-job material signals (stock overrun, missing stock
            // mappings, held material warnings) only exist for companies that
            // actually track inventory. For off-mode companies the server skips
            // all material work, so the banner stays a plain acceptance — never
            // surface overrun/mapping language they can't act on.
            let isTracked = inventoryMode == "tracked"
            let effectiveWarningCount = isTracked ? warningCount : 0
            let effectiveMissingMappingCount = isTracked ? missingMappingCount : 0
            let effectiveOverrunCount = isTracked ? overrunCount : 0
            let effectiveOverrunDetails = isTracked ? overrunDetails : []
            let hasOverruns = effectiveOverrunCount > 0
            let hasMappings = effectiveMissingMappingCount > 0
            let message = acceptedApprovalMessage(
                warningCount: effectiveWarningCount,
                missingMappingCount: effectiveMissingMappingCount,
                overrunCount: effectiveOverrunCount,
                overrunDetails: effectiveOverrunDetails,
                idempotentReplay: idempotentReplay
            )
            approvalBanner(
                title: hasOverruns
                    ? "WARN :: STOCK OVERRUN"
                    : hasMappings ? "WARN :: STOCK MAPPING" : "SYS :: ACCEPTED",
                message: message,
                color: hasOverruns || hasMappings
                    ? OPSStyle.Colors.warningStatus
                    : OPSStyle.Colors.successStatus
            )
        case .failed(let message):
            approvalBanner(
                title: "SYS :: ACCEPT FAILED",
                message: message,
                color: OPSStyle.Colors.errorStatus
            )
        }
    }

    private func approvalBanner(title: String, message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(color)
            Text(message)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2_5)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(color.opacity(0.35), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    private func acceptedApprovalMessage(
        warningCount: Int,
        missingMappingCount: Int,
        overrunCount: Int,
        overrunDetails: [EstimateAcceptanceOverrunDetail],
        idempotentReplay: Bool
    ) -> String {
        if overrunCount > 0 {
            var parts = [
                "\(overrunCount) stock overrun\(overrunCount == 1 ? "" : "s") projected"
            ]
            if let shortQuantity = overrunDetails.compactMap(\.projectedOverrunQuantity).first {
                parts.append("Short \(formatQuantity(shortQuantity)) at booking")
            }
            if missingMappingCount > 0 {
                parts.append(mappingMessage(count: missingMappingCount))
            }
            return parts.joined(separator: ". ") + "."
        }

        if missingMappingCount > 0 {
            return mappingMessage(count: missingMappingCount) + "."
        }

        if warningCount > 0 {
            let noun = warningCount == 1 ? "warning" : "warnings"
            return "\(warningCount) inventory \(noun) held for review."
        }

        return idempotentReplay ? "Project link replayed." : "Project linked."
    }

    private func mappingMessage(count: Int) -> String {
        let noun = count == 1 ? "fix" : "fixes"
        return "\(count) mapping \(noun) queued in notifications"
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack {
                Text(estimate.estimateNumber.isEmpty ? "NEW ESTIMATE" : estimate.estimateNumber)
                    .font(OPSStyle.Typography.screenTitle(for: estimate.estimateNumber.isEmpty ? "NEW ESTIMATE" : estimate.estimateNumber))
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
            }

            if let title = estimate.title, !title.isEmpty {
                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(estimate.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                statusBadge

                Text("[created \(estimate.createdAt.timeAgoDetail)]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    private var statusBadge: some View {
        let color = estimate.status.badgeColor
        return HStack(spacing: OPSStyle.Layout.spacing1) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(estimate.status.displayName)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }

    // MARK: - Line Items

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("LINE ITEMS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                if lineItems.contains(where: { $0.parentLineItemId != nil }) {
                    Button {
                        withAnimation(OPSStyle.Animation.spring) { showBreakdown.toggle() }
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Text(showBreakdown ? "BUNDLED" : "BREAKDOWN")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Image(systemName: showBreakdown ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            if lineItems.isEmpty {
                Text("No line items")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(parentItems.enumerated()), id: \.element.id) { index, item in
                        parentLineItemRow(item)

                        if showBreakdown {
                            let children = childItems(for: item.id)
                            ForEach(children) { child in
                                childLineItemRow(child)
                            }
                        }

                        if index < parentItems.count - 1 {
                            Divider().background(OPSStyle.Colors.cardBorder)
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    private func parentLineItemRow(_ item: EstimateLineItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(taskTypeColor(for: item.taskTypeId) ?? OPSStyle.Colors.tertiaryText.opacity(0.3))
                    .frame(width: 10, height: 10)
                Text(item.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(item.lineTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(item.type.rawValue.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                if let label = item.resolvedOptionsLabel, !label.isEmpty {
                    Text("· \(label)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
                let children = childItems(for: item.id)
                if !children.isEmpty {
                    Text("[\(children.count) items]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                if item.optional {
                    Text("[OPTIONAL]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private func childLineItemRow(_ item: EstimateLineItem) -> some View {
        HStack {
            Rectangle()
                .fill(taskTypeColor(for: item.taskTypeId) ?? OPSStyle.Colors.tertiaryText.opacity(0.2))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                Text(childMetaLine(item))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Text(item.lineTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.leading, OPSStyle.Layout.spacing3 + 14)
        .padding(.trailing, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.3))
    }

    /// Child-row metadata: "qty unit · [chosen option] · unit price". The option
    /// label appears only when the child line snapshotted a configured option.
    private func childMetaLine(_ item: EstimateLineItem) -> String {
        let qtyUnit = "\(formatQuantity(item.quantity)) \(item.unit ?? "")"
            .trimmingCharacters(in: .whitespaces)
        let price = item.unitPrice.formatted(.currency(code: "USD"))
        if let label = item.resolvedOptionsLabel, !label.isEmpty {
            return "\(qtyUnit) · \(label) · \(price)"
        }
        return "\(qtyUnit) · \(price)"
    }

    private func formatQuantity(_ qty: Double) -> String {
        qty.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(qty)) : String(format: "%.1f", qty)
    }

    // MARK: - Totals

    private var totalsSection: some View {
        VStack(spacing: 0) {
            Divider().background(OPSStyle.Colors.cardBorder)

            VStack(spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    Text("SUBTOTAL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(estimate.subtotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                if estimate.taxRate > 0 {
                    HStack {
                        Text("TAX (\(String(format: "%.0f", estimate.taxRate))%)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text(estimate.taxAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }

                HStack {
                    Text("TOTAL")
                        .font(OPSStyle.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                    Text(estimate.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Sticky Footer

    private var stickyFooter: some View {
        OPSFloatingButtonBar(horizontalPadding: OPSStyle.Layout.spacing3, verticalPadding: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                switch estimate.status {
                case .draft:
                    Button("EDIT") { showEditSheet = true }
                        .opsSecondaryButtonStyle()
                    Button("SEND ESTIMATE") {
                        Task { await viewModel.sendEstimate(estimate) }
                    }
                    .opsPrimaryButtonStyle()

                case .sent, .viewed:
                    let isSubmittingApproval = viewModel.approvalState(for: estimate.id).isSubmitting
                    Button("RESEND") {
                        Task { await viewModel.sendEstimate(estimate) }
                    }
                    .opsSecondaryButtonStyle()
                    .disabled(isSubmittingApproval)
                    Button(isSubmittingApproval ? "ACCEPTING" : "MARK APPROVED") {
                        Task { await viewModel.markApproved(estimate) }
                    }
                    .opsPrimaryButtonStyle()
                    .disabled(isSubmittingApproval)

                case .approved:
                    Button("CONVERT TO INVOICE") { showConvertOptions = true }
                        .opsPrimaryButtonStyle()

                default:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Helpers

private extension EstimateStatus {
    var badgeColor: Color {
        switch self {
        case .draft:     return OPSStyle.Colors.tertiaryText
        case .sent:      return OPSStyle.Colors.primaryAccent
        case .viewed:    return OPSStyle.Colors.primaryAccent
        case .approved:  return OPSStyle.Colors.successStatus
        case .converted: return OPSStyle.Colors.successStatus
        case .declined:  return OPSStyle.Colors.errorStatus
        case .expired:   return OPSStyle.Colors.warningStatus
        }
    }
}

private extension Date {
    var timeAgoDetail: String {
        let interval = Date().timeIntervalSince(self)
        let days = Int(interval / 86400)
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }
}
