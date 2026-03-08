//
//  SyncStatusSection.swift
//  OPS
//
//  Collapsible sync status section for the notifications sheet.
//  Shows pending/failed operations with retry capability.
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 12) {
            // Status icon
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(OPSStyle.Colors.primaryAccent)
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
        VStack(spacing: 8) {
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 4)

            // Individual operation rows (show up to 10)
            let items = syncEngine.getPendingOperations().prefix(10)
            ForEach(Array(items.enumerated()), id: \.element.id) { _, operation in
                operationRow(for: operation)
            }

            if pendingCount > 10 {
                Text("+ \(pendingCount - 10) more")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
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
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Operation Row

    private func operationRow(for operation: SyncOperation) -> some View {
        HStack(spacing: 10) {
            // Status indicator
            statusIcon(for: operation)
                .frame(width: 16, height: 16)

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text(operationDescription(for: operation))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                if let error = operation.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Retry button for failed
            if operation.status == "failed" {
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
        }
        .padding(.vertical, 4)
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

    private func operationDescription(for operation: SyncOperation) -> String {
        let action: String
        switch operation.operationType {
        case "create": action = "Creating"
        case "update": action = "Updating"
        case "delete": action = "Deleting"
        default: action = "Syncing"
        }

        let entity = operation.entityType
            .replacingOccurrences(of: "projectTask", with: "task")
            .replacingOccurrences(of: "projectNote", with: "note")

        return "\(action) \(entity)"
    }
}
