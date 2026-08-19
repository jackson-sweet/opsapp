//
//  PendingWorkDetailSheet.swift
//  OPS
//
//  SYNC RECOVERY · T6 — the half-sheet behind a PENDING WORK row (spec §4/§6.2).
//  Shows the piece of work member-by-member, turns a server rejection into a
//  calm SYS block (raw error tucked behind a DETAILS disclosure), and offers the
//  three recovery moves: RETRY NOW, EXPORT, DISCARD. Pure — every action is a
//  closure the screen wrapper wires; all copy via `SyncStatusCopy.PendingWork`.
//

import SwiftUI

struct PendingWorkDetailSheet: View {
    let item: RecoveryItem
    let now: Date
    let onRetry: () -> Void
    let onExport: () -> Void
    let onDiscard: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardConfirm = false
    @State private var showRawDetails = false
    @State private var isDiscarding = false
    @State private var discardError: String?

    private var isQuarantined: Bool {
        if case .quarantinedVisit = item { return true }
        return false
    }
    private var isParked: Bool { item.tone == .parked && !isQuarantined }
    private var isRetryable: Bool { item.tone >= .attention && !isQuarantined }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle

            Text(PendingWorkVisuals.title(for: item))
                .font(OPSStyle.Typography.section)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3_5)

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                    memberList

                    if isParked {
                        parkedBlock
                    }

                    if !diagnosticLines.isEmpty {
                        detailsDisclosure
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }

            actions
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isDiscarding)
    }

    // MARK: - Handle (§6.2)

    private var handle: some View {
        Capsule()
            .fill(OPSStyle.Colors.text.opacity(0.30))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, OPSStyle.Layout.spacing2)
    }

    // MARK: - Member list

    @ViewBuilder
    private var memberList: some View {
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if index > 0 {
                    Divider().background(OPSStyle.Colors.lineSoft)
                }
                detailLineRow(line)
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private func detailLineRow(_ line: DetailLine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: PendingWorkVisuals.glyphName(line.tone))
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                .foregroundColor(PendingWorkVisuals.toneColor(line.tone))
                .frame(width: 16, height: 16)

            Text(line.label)
                .font(OPSStyle.Typography.miniLabelBold)
                .tracking(0.8)
                .foregroundColor(OPSStyle.Colors.text2)

            Spacer(minLength: OPSStyle.Layout.spacing2)

            Text(line.statusText)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(PendingWorkVisuals.statusColor(line.statusTone))
                .lineLimit(1)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Parked block

    private var parkedBlock: some View {
        // A record deleted in OPS is a different event from a rejected write,
        // and retrying it can never work — the block names which one happened.
        let detail = SyncStatusCopy.PendingWork.parkedDetail(
            lastError: rawErrors.first
        )
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(detail.label)
                .font(OPSStyle.Typography.metadata)
                .tracking(0.8)
                .foregroundColor(OPSStyle.Colors.rose)

            Text(detail.body)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .fill(OPSStyle.Colors.roseSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .stroke(OPSStyle.Colors.roseLine, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Raw error disclosure

    private var detailsDisclosure: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Button {
                withAnimation(OPSStyle.Animation.panel) { showRawDetails.toggle() }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text("DETAILS")
                        .font(OPSStyle.Typography.miniLabelBold)
                        .tracking(0.8)
                        .foregroundColor(OPSStyle.Colors.text3)
                    Image(systemName: showRawDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text3)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showRawDetails {
                Text(diagnosticLines.joined(separator: "\n\n"))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OPSStyle.Layout.spacing2_5)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            if isDiscarding {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(OPSStyle.Colors.text3)
                    Text(SyncStatusCopy.PendingWork.deletingStatus)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let discardError {
                Text(discardError)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isRetryable {
                Button {
                    onRetry()
                    dismiss()
                } label: {
                    Text("RETRY NOW")
                }
                .opsPrimaryButtonStyle()
                .disabled(isDiscarding)
            }

            Button {
                // Dismiss first — the share sheet presents from the screen
                // wrapper, which can't stack a sheet under this one. The wrapper
                // chains the share presentation after the dismiss settles.
                onExport()
                dismiss()
            } label: {
                Text(SyncStatusCopy.PendingWork.exportAction)
            }
            .opsSecondaryButtonStyle()
            .disabled(isDiscarding)

            if let scope = discardScope {
                Button(role: scope.isDestructive ? .destructive : nil) {
                    showDiscardConfirm = true
                } label: {
                    Text(SyncStatusCopy.PendingWork.discardActionLabel(for: scope))
                }
                .modifier(DiscardButtonStyle(isDestructive: scope.isDestructive))
                .disabled(isDiscarding)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .padding(.bottom, OPSStyle.Layout.spacing3_5)
        .background(OPSStyle.Colors.background)
        .confirmationDialog(
            discardConfirmationTitle,
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button(
                discardActionLabel,
                role: (discardScope?.isDestructive ?? true) ? .destructive : nil
            ) {
                Task { @MainActor in
                    guard !isDiscarding else { return }
                    isDiscarding = true
                    discardError = nil
                    let succeeded = await onDiscard()
                    isDiscarding = false
                    if succeeded {
                        dismiss()
                    } else if let scope = discardScope {
                        discardError =
                            SyncStatusCopy.PendingWork.failureMessage(for: scope)
                    } else {
                        discardError = SyncStatusCopy.PendingWork.discardFailure
                    }
                }
            }
            Button(
                SyncStatusCopy.PendingWork.cancelAction,
                role: .cancel
            ) {}
        } message: {
            Text(discardConfirmationBody)
        }
    }

    /// The scope this row's discard covers — nil when the row deliberately
    /// omits a discard entirely.
    private var discardScope: RecoveryDiscardScope? {
        item.discardPolicy.confirmationScope
    }

    private var discardConfirmationTitle: String {
        guard let scope = discardScope else {
            return SyncStatusCopy.PendingWork.discardConfirmTitle
        }
        return SyncStatusCopy.PendingWork.discardConfirmationTitle(for: scope)
    }

    private var discardActionLabel: String {
        guard let scope = discardScope else {
            return SyncStatusCopy.PendingWork.deleteAction
        }
        return SyncStatusCopy.PendingWork.discardActionLabel(for: scope)
    }

    private var discardConfirmationBody: String {
        guard let scope = discardScope else {
            return SyncStatusCopy.PendingWork.discardConfirmBody
        }
        return SyncStatusCopy.PendingWork.discardConfirmationBody(for: scope)
    }

    // MARK: - Lines model

    private struct DetailLine {
        let label: String
        let statusText: String
        let statusTone: SyncStatusTone
        let tone: RecoveryTone
    }

    /// One line per bundle member, or one line for a loose item.
    private var lines: [DetailLine] {
        switch item {
        case .bundle(let bundle):
            return bundle.members.map { member in
                let status = SyncStatusCopy.PendingWork.statusLine(
                    statusRaw: member.status.statusRaw,
                    lastError: member.status.lastError,
                    secondsUntilRetry: PendingWorkVisuals.secondsUntilRetry(member.status.nextEligibleAt, now: now)
                )
                return DetailLine(
                    label: SyncStatusCopy.PendingWork.memberLabel(member.role),
                    statusText: status.text,
                    statusTone: status.tone,
                    tone: member.tone
                )
            }
        default:
            let status = PendingWorkVisuals.statusLine(for: item, now: now)
            return [DetailLine(
                label: PendingWorkVisuals.title(for: item),
                statusText: status.text,
                statusTone: status.tone,
                tone: item.tone
            )]
        }
    }

    /// What DETAILS actually shows: one plain sentence per distinct cause.
    ///
    /// This block used to print `rawErrors` verbatim, which meant a business
    /// owner reading `PostgrestError(detail: nil, hint: nil, code:
    /// Optional("PGRST116"), message: "Cannot coerce the result to a single
    /// JSON object")` on his own phone. The raw text still exists and still
    /// travels — EXPORT carries it untouched for support — but it never renders
    /// here. `SyncStatusCopy` stays the single chokepoint for every word the
    /// operator reads.
    private var diagnosticLines: [String] {
        SyncStatusCopy.PendingWork.diagnostics(rawErrors)
    }

    /// Raw server errors, deduped. Kept raw on purpose: `parkedDetail` and the
    /// diagnostic rules classify by matching the writer's own markers, and the
    /// export payload needs the untouched text.
    private var rawErrors: [String] {
        let collected: [String?]
        switch item {
        case .bundle(let bundle):
            collected = bundle.members.map { $0.status.lastError }
        default:
            collected = [PendingWorkVisuals.displayStatus(for: item).lastError]
        }
        var seen = Set<String>()
        return collected.compactMap { raw in
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard !seen.contains(raw) else { return nil }
            seen.insert(raw)
            return raw
        }
    }
}

// MARK: - Discard button styling

/// The two button styles are distinct view modifiers, so the destructive vs
/// secondary choice has to be made through a modifier rather than a ternary
/// inside the builder. A stopped send must not wear the destructive treatment.
private struct DiscardButtonStyle: ViewModifier {
    let isDestructive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isDestructive {
            content.opsDestructiveButtonStyle()
        } else {
            content.opsSecondaryButtonStyle()
        }
    }
}
