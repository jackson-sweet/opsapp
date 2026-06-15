//
//  SyncStatusSection.swift
//  OPS
//
//  Collapsible sync status section for the notifications sheet.
//  Shows pending/failed operations with retry and cancel capability.
//

import SwiftUI

struct SyncStatusSection: View {
    @EnvironmentObject private var dataController: DataController
    @State private var isExpanded: Bool = false

    /// Access sync state from the engine (SyncEngine is @Observable)
    private var syncEngine: SyncEngine {
        dataController.syncEngine
    }

    private var pendingCount: Int {
        syncEngine.pendingOperationCount
    }

    private var isSyncing: Bool {
        syncEngine.isSyncing
    }

    private var hasContent: Bool {
        pendingCount > 0 || isSyncing
    }

    var body: some View {
        if hasContent {
            VStack(spacing: 0) {
                // Collapsed header — always visible when there's content
                Button {
                    withAnimation(OPSStyle.Animation.standard) {
                        isExpanded.toggle()
                    }
                } label: {
                    headerRow
                }
                .buttonStyle(PlainButtonStyle())

                // Expanded content
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Status icon
            if isSyncing {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .rotationEffect(.degrees(isSyncing ? 360 : 0))
                    .animation(
                        .linear(duration: 1.5).repeatForever(autoreverses: false),
                        value: isSyncing
                    )
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .frame(width: 20, height: 20)
            }

            // Status text
            Text(headerText)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            // Chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    private var headerText: String {
        if isSyncing {
            return "Syncing \(pendingCount) change\(pendingCount == 1 ? "" : "s")…"
        } else {
            return "\(pendingCount) change\(pendingCount == 1 ? "" : "s") pending"
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .background(OPSStyle.Colors.line)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            // Individual operation rows (show up to 15)
            let items = syncEngine.getPendingOperations() + syncEngine.getFailedOperations()
            let uniqueItems = Array(Dictionary(grouping: items) { $0.id }.values.compactMap(\.first)).prefix(15)

            ForEach(Array(uniqueItems.enumerated()), id: \.element.id) { index, operation in
                if index > 0 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.vertical, 2)
                }
                operationRow(for: operation)
            }

            if (syncEngine.getPendingOperations().count + syncEngine.getFailedOperations().count) > 15 {
                Text("+ \(syncEngine.getPendingOperations().count + syncEngine.getFailedOperations().count - 15) more")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }

            // Retry all button for failed operations
            let failedOps = syncEngine.getFailedOperations()
            if !failedOps.isEmpty {
                Button {
                    for op in failedOps {
                        op.status = "pending"
                        op.retryCount = 0
                    }
                    try? dataController.modelContext?.save()
                    Task {
                        await syncEngine.triggerSync()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                        Text("RETRY ALL FAILED (\(failedOps.count))")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .frame(maxWidth: .infinity)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, OPSStyle.Layout.spacing2)
            }
        }
    }

    // MARK: - Operation Row

    private func operationRow(for operation: SyncOperation) -> some View {
        HStack(spacing: 10) {
            // Status indicator
            statusIcon(for: operation)
                .frame(width: 16, height: 16)

            // Description — entity type, action, changed fields, time
            VStack(alignment: .leading, spacing: 3) {
                // Primary line: action + entity
                Text(operationTitle(for: operation))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                // Detail line: changed fields
                let fields = operation.getChangedFields()
                if !fields.isEmpty {
                    Text(fields.joined(separator: ", "))
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }

                // Error line
                if let error = operation.lastError {
                    Text(error)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Time ago
            Text(timeAgo(from: operation.createdAt))
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            // Action buttons
            if operation.status == "failed" {
                // Retry button for failed
                Button {
                    operation.status = "pending"
                    operation.retryCount = 0
                    operation.lastError = nil
                    try? dataController.modelContext?.save()
                    Task { await syncEngine.triggerSync() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: 28, height: 28)
                        .background(OPSStyle.Colors.cardBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Cancel button — available for pending and failed (not in-progress)
            if operation.status != "inProgress" {
                Button {
                    withAnimation(OPSStyle.Animation.standard) {
                        syncEngine.cancelOperation(operation)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(width: 24, height: 24)
                        .background(OPSStyle.Colors.cardBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing1)
    }

    @ViewBuilder
    private func statusIcon(for operation: SyncOperation) -> some View {
        switch operation.status {
        case "pending":
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundColor(OPSStyle.Colors.warningStatus)
        case "inProgress":
            ProgressView()
                .scaleEffect(0.5)
                .tint(OPSStyle.Colors.primaryAccent)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(OPSStyle.Colors.errorStatus)
        default:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(OPSStyle.Colors.successStatus)
        }
    }

    private func operationTitle(for operation: SyncOperation) -> String {
        let action: String
        switch operation.operationType {
        case "create": action = "Create"
        case "update": action = "Update"
        case "delete": action = "Delete"
        default: action = "Sync"
        }

        let entity = friendlyEntityName(operation.entityType)
        return "\(action) \(entity)"
    }

    private func friendlyEntityName(_ entityType: String) -> String {
        switch entityType {
        case "project": return "Project"
        case "projectTask": return "Task"
        case "projectNote": return "Note"
        case "user": return "User"
        case "client": return "Client"
        case "subClient": return "Sub-Client"
        case "company": return "Company"
        case "taskType": return "Task Type"
        case "expense": return "Expense"
        case "estimate": return "Estimate"
        case "invoice": return "Invoice"
        case "lineItem": return "Line Item"
        case "payment": return "Payment"
        case "photoAnnotation": return "Photo Annotation"
        case "calendarUserEvent": return "Calendar Event"
        case "catalogCategory": return "Catalog Category"
        case "catalogUnit": return "Catalog Unit"
        case "catalogTag": return "Catalog Tag"
        case "catalogItem": return "Catalog Item"
        case "catalogVariant": return "Catalog Variant"
        case "catalogOption": return "Catalog Option"
        case "catalogOptionValue": return "Catalog Option Value"
        case "catalogVariantOptionValue": return "Catalog Variant Option Value"
        case "catalogItemTag": return "Catalog Item Tag"
        case "catalogSnapshot": return "Catalog Snapshot"
        case "catalogSnapshotItem": return "Catalog Snapshot Item"
        case "catalogOrder": return "Catalog Order"
        case "catalogOrderItem": return "Catalog Order Item"
        case "companyDefaultProduct": return "Default Product"
        case "productOption": return "Product Option"
        case "productOptionValue": return "Product Option Value"
        case "productPricingModifier": return "Pricing Modifier"
        case "productMaterial": return "Product Material"
        case "timeEntry": return "Time Entry"
        case "signatureCapture": return "Signature"
        case "formSubmission": return "Form"
        default: return entityType.capitalized
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
