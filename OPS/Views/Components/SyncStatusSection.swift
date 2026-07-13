//
//  SyncStatusSection.swift
//  OPS
//
//  Collapsible sync status section for the notifications sheet.
//
//  Design intent (bug dbada8f5): stay quiet and honest. Count every outstanding
//  change — queued AND failed — so the header can never disagree with the list
//  below it. Speak plain language via SyncStatusCopy (never a raw column name or
//  Postgres error). Give stuck changes a working retry / dismiss with real
//  44pt touch targets. Calm tan for "needs a look", rose only when truly stuck.
//

import SwiftUI

struct SyncStatusSection: View {
    @EnvironmentObject private var dataController: DataController
    @State private var isExpanded: Bool = false

    /// Access sync state from the engine (SyncEngine is @Observable).
    private var syncEngine: SyncEngine {
        dataController.syncEngine
    }

    var body: some View {
        // Read tracked engine state so the view re-renders when sync changes,
        // then fetch the live operation lists for display.
        let isSyncing = syncEngine.isSyncing
        let pending = syncEngine.getPendingOperations()
        let failed = syncEngine.getFailedOperations()
        // Reading pendingOperationCount keeps the @Observable subscription live
        // so the panel re-renders as operations move between pending/failed/done.
        let trackedCount = syncEngine.pendingOperationCount
        let hasContent = !pending.isEmpty || !failed.isEmpty || isSyncing || trackedCount > 0

        if hasContent {
            VStack(spacing: 0) {
                Button {
                    withAnimation(OPSStyle.Animation.standard) {
                        isExpanded.toggle()
                    }
                } label: {
                    headerRow(pendingCount: pending.count, failedCount: failed.count, isSyncing: isSyncing)
                }
                .buttonStyle(PlainButtonStyle())

                if isExpanded {
                    expandedContent(pending: pending, failed: failed)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .glassSurface()
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Header Row

    private func headerRow(pendingCount: Int, failedCount: Int, isSyncing: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            headerIcon(isSyncing: isSyncing, hasFailures: failedCount > 0)
                .frame(width: 20, height: 20)

            Text(SyncStatusCopy.header(pendingCount: pendingCount, failedCount: failedCount, isSyncing: isSyncing))
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func headerIcon(isSyncing: Bool, hasFailures: Bool) -> some View {
        if isSyncing {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .rotationEffect(.degrees(isSyncing ? 360 : 0))
                .animation(
                    .linear(duration: 1.5).repeatForever(autoreverses: false),
                    value: isSyncing
                )
        } else if hasFailures {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.tan)
        } else {
            Image(systemName: "clock")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Expanded Content

    private func expandedContent(pending: [SyncOperation], failed: [SyncOperation]) -> some View {
        // Queued first, then failed — deduped by id, capped at 15 rows.
        let items = pending + failed
        let uniqueItems = Array(Dictionary(grouping: items) { $0.id }.values.compactMap(\.first))
        let shown = Array(uniqueItems.prefix(15))
        let overflow = uniqueItems.count - shown.count

        return VStack(spacing: 0) {
            Divider()
                .background(OPSStyle.Colors.line)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            ForEach(Array(shown.enumerated()), id: \.element.id) { index, operation in
                if index > 0 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.vertical, 2)
                }
                operationRow(for: operation)
            }

            if overflow > 0 {
                Text("+ \(overflow) more")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }

            // Retry all — clears the failed state and re-queues.
            if !failed.isEmpty {
                Button {
                    for op in failed {
                        op.status = "pending"
                        op.retryCount = 0
                        op.lastError = nil
                    }
                    try? dataController.modelContext?.save()
                    Task { await syncEngine.triggerSync() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                        Text("RETRY ALL (\(failed.count))")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, OPSStyle.Layout.spacing2)
            }
        }
    }

    // MARK: - Operation Row

    private func operationRow(for operation: SyncOperation) -> some View {
        let state = SyncStatusCopy.status(
            status: operation.status,
            retryCount: operation.retryCount,
            canRetry: operation.canRetry,
            rawError: operation.lastError
        )

        return HStack(spacing: 10) {
            statusIcon(for: state.tone)
                .frame(width: 16, height: 16)

            // Human title + plain-language status — no raw fields, no raw errors.
            VStack(alignment: .leading, spacing: 3) {
                Text(SyncStatusCopy.title(
                    entityType: operation.entityType,
                    operationType: operation.operationType,
                    changedFields: operation.getChangedFields()
                ))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

                Text(state.text)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(color(for: state.tone))
                    .lineLimit(1)
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            Text(timeAgo(from: operation.createdAt))
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            // Retry — failed only.
            if operation.status == "failed" {
                actionButton(system: "arrow.clockwise", tint: OPSStyle.Colors.primaryAccent, glyphSize: 12) {
                    operation.status = "pending"
                    operation.retryCount = 0
                    operation.lastError = nil
                    try? dataController.modelContext?.save()
                    Task { await syncEngine.triggerSync() }
                }
            }

            // Dismiss — pending or failed (not in-progress).
            if operation.status != "inProgress" {
                actionButton(system: "xmark", tint: OPSStyle.Colors.tertiaryText, glyphSize: 10) {
                    withAnimation(OPSStyle.Animation.standard) {
                        syncEngine.cancelOperation(operation)
                    }
                }
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing1)
    }

    // MARK: - Row pieces

    @ViewBuilder
    private func statusIcon(for tone: SyncStatusTone) -> some View {
        switch tone {
        case .syncing:
            ProgressView()
                .scaleEffect(0.5)
                .tint(OPSStyle.Colors.primaryAccent)
        case .waiting:
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        case .attention:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundColor(OPSStyle.Colors.tan)
        case .stuck:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(OPSStyle.Colors.rose)
        }
    }

    /// Small glyph with a full 44pt touch target (field-first, gloves).
    private func actionButton(
        system: String,
        tint: Color,
        glyphSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(OPSStyle.Colors.surfaceActive)
                .clipShape(Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func color(for tone: SyncStatusTone) -> Color {
        switch tone {
        case .syncing:   return OPSStyle.Colors.primaryAccent
        case .waiting:   return OPSStyle.Colors.tertiaryText
        case .attention: return OPSStyle.Colors.tan
        case .stuck:     return OPSStyle.Colors.rose
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
