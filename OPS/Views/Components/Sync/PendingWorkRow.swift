//
//  PendingWorkRow.swift
//  OPS
//
//  SYNC RECOVERY · T6 — the row/card vocabulary for the PENDING WORK recovery
//  screen (spec §4). Pure presentation: every entry renders from a
//  `RecoveryItem` value + a fixed `now`, so the whole screen is snapshot-testable
//  without a live engine. Row anatomy mirrors `SyncStatusPanel` (16pt status
//  glyph · Mohave primary · JBM status line · relative time · 44pt actions);
//  all copy comes from `SyncStatusCopy.PendingWork`, all visual values from
//  `OPSStyle`.
//

import SwiftUI

// MARK: - Shared visual language

/// Maps a recovery item's value state to the screen's shared visual tokens —
/// one place so every row/card/sheet reads identically. No copy here (that is
/// `SyncStatusCopy.PendingWork`); this is tone → colour + glyph + time only.
enum PendingWorkVisuals {

    /// Section-placement tone → row glyph / accent colour. Waiting is quiet
    /// neutral, attention is tan, parked is rose (out of auto-retries).
    static func toneColor(_ tone: RecoveryTone) -> Color {
        switch tone {
        case .waiting:   return OPSStyle.Colors.text3
        case .attention: return OPSStyle.Colors.tan
        case .parked:    return OPSStyle.Colors.rose
        }
    }

    /// Status-line tone (from `SyncStatusCopy`) → colour. Matches the panel's
    /// mapping so a status line reads the same on both surfaces.
    static func statusColor(_ tone: SyncStatusTone) -> Color {
        switch tone {
        case .syncing:   return OPSStyle.Colors.primaryAccent
        case .waiting:   return OPSStyle.Colors.text3
        case .attention: return OPSStyle.Colors.tan
        case .stuck:     return OPSStyle.Colors.rose
        }
    }

    /// SF Symbol for a tone's leading status glyph. `inProgress` is handled by
    /// the caller (it renders a spinner, not a glyph).
    static func glyphName(_ tone: RecoveryTone) -> String {
        switch tone {
        case .waiting:   return "clock"
        case .attention: return "exclamationmark.circle"
        case .parked:    return "exclamationmark.circle.fill"
        }
    }

    /// Whole-second countdown until an item next auto-retries, floored to 1s;
    /// nil when the item is not actively counting down (due now, failed, parked).
    static func secondsUntilRetry(_ nextEligibleAt: Date?, now: Date) -> Int? {
        guard let nextEligibleAt, nextEligibleAt > now else { return nil }
        return max(1, Int(nextEligibleAt.timeIntervalSince(now).rounded(.down)))
    }

    /// Compact relative age — "now" / "5m" / "3h" / "2d". Clock-free (takes
    /// `now`) so a fixed `now` yields a stable snapshot.
    static func relativeTime(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    /// The status payload a loose item / bundle shows on its single status line.
    /// A bundle speaks for its worst member (the one that set its tone).
    static func displayStatus(for item: RecoveryItem) -> RecoveryStatusPayload {
        switch item {
        case .op(let snapshot, _, let next):
            return RecoveryStatusPayload(
                statusRaw: snapshot.status,
                retryCount: snapshot.retryCount,
                lastError: snapshot.lastError,
                nextEligibleAt: next
            )
        case .autocreate(let snapshot, let tone, let next):
            return RecoveryStatusPayload(
                statusRaw: synthStatus(tone),
                retryCount: snapshot.attempts,
                lastError: snapshot.lastError,
                nextEligibleAt: next
            )
        case .photos(_, let tone):
            return RecoveryStatusPayload(
                statusRaw: tone == .attention ? "failed" : "local",
                retryCount: 0,
                lastError: nil,
                nextEligibleAt: nil
            )
        case .bundle(let bundle):
            let worst = bundle.members.first { $0.tone == bundle.tone } ?? bundle.members.first
            return worst?.status ?? RecoveryStatusPayload(
                statusRaw: synthStatus(bundle.tone), retryCount: 0, lastError: nil, nextEligibleAt: nil
            )
        case .draft, .orphanDesign:
            return RecoveryStatusPayload(statusRaw: "pending", retryCount: 0, lastError: nil, nextEligibleAt: nil)
        case .quarantinedVisit:
            return RecoveryStatusPayload(statusRaw: "quarantined", retryCount: 0, lastError: nil, nextEligibleAt: nil)
        }
    }

    /// Synthesises the op-status vocabulary from a tone so autocreates/photos/
    /// bundles speak one language to `SyncStatusCopy`.
    static func synthStatus(_ tone: RecoveryTone) -> String {
        switch tone {
        case .parked:    return "parked"
        case .attention: return "failed"
        case .waiting:   return "pending"
        }
    }

    /// The work's display title — named like a human action, all copy through
    /// `SyncStatusCopy`. Shared by the row and the detail sheet.
    static func title(for item: RecoveryItem) -> String {
        switch item {
        case .op(let snapshot, _, _):
            return SyncStatusCopy.title(
                entityType: snapshot.entityType,
                operationType: snapshot.operationType,
                changedFields: []
            )
        case .autocreate(let snapshot, _, _):
            return SyncStatusCopy.PendingWork.leadTitle(name: snapshot.name)
        case .photos(let grouped, _):
            return SyncStatusCopy.PendingWork.photosTitle(count: grouped.count)
        case .bundle(let bundle):
            return SyncStatusCopy.PendingWork.draftTitle(displayName: bundle.title)
        case .draft(let draft):
            return SyncStatusCopy.PendingWork.draftTitle(displayName: draft.displayName)
        case .orphanDesign(let design):
            return SyncStatusCopy.PendingWork.orphanTitle(title: design.title)
        case .quarantinedVisit:
            return SyncStatusCopy.PendingWork.quarantineTitle
        }
    }

    /// The plain status line + tone for any loose item / bundle, resolved once.
    static func statusLine(for item: RecoveryItem, now: Date) -> (text: String, tone: SyncStatusTone) {
        if case .quarantinedVisit = item {
            return (SyncStatusCopy.PendingWork.quarantineRow, .stuck)
        }
        let payload = displayStatus(for: item)
        return SyncStatusCopy.PendingWork.statusLine(
            statusRaw: payload.statusRaw,
            lastError: payload.lastError,
            secondsUntilRetry: secondsUntilRetry(payload.nextEligibleAt, now: now)
        )
    }
}

// MARK: - Leading status glyph

/// 16pt leading glyph — spinner while a save is in flight, else a tone glyph.
struct PendingWorkStatusGlyph: View {
    let tone: RecoveryTone
    let statusRaw: String

    var body: some View {
        Group {
            if statusRaw == "inProgress" {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(OPSStyle.Colors.primaryAccent)
            } else {
                Image(systemName: PendingWorkVisuals.glyphName(tone))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PendingWorkVisuals.toneColor(tone))
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Inline retry glyph (attention only)

/// Small retry glyph with a full 44pt touch target (field-first). Only rendered
/// for attention/parked rows — the single dominant action a scan row is allowed.
struct PendingWorkRetryGlyph: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 30, height: 30)
                .background(OPSStyle.Colors.surfaceActive)
                .clipShape(Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry")
    }
}

// MARK: - Loose entry row (op / autocreate / photos)

/// A single scan row for a loose sync item. Whole row taps to the detail sheet;
/// the trailing retry glyph is the one inline action (attention/parked only).
struct PendingWorkEntryRow: View {
    let item: RecoveryItem
    let now: Date
    let onTap: () -> Void
    let onRetry: () -> Void
    var showsRetry = true

    private var tone: RecoveryTone { item.tone }
    private var payload: RecoveryStatusPayload { PendingWorkVisuals.displayStatus(for: item) }
    private var title: String { PendingWorkVisuals.title(for: item) }
    private var statusLine: (text: String, tone: SyncStatusTone) {
        PendingWorkVisuals.statusLine(for: item, now: now)
    }

    var body: some View {
        HStack(spacing: 10) {
            PendingWorkStatusGlyph(tone: tone, statusRaw: payload.statusRaw)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Text(statusLine.text)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(PendingWorkVisuals.statusColor(statusLine.tone))
                    .lineLimit(1)
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            Text(PendingWorkVisuals.relativeTime(from: item.sortDate, now: now))
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)

            if showsRetry && tone >= .attention {
                PendingWorkRetryGlyph(action: onRetry)
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(statusLine.text)")
    }
}

// MARK: - Bundle card (site-visit work unit)

/// A work-unit bundle: title + member strip + worst-member status line, with an
/// inline retry glyph when the bundle needs a look. Taps to the detail sheet.
struct PendingWorkBundleCard: View {
    let bundle: SiteVisitBundle
    let now: Date
    let onTap: () -> Void
    let onRetry: () -> Void

    private var payload: RecoveryStatusPayload {
        PendingWorkVisuals.displayStatus(for: .bundle(bundle))
    }

    private var statusLine: (text: String, tone: SyncStatusTone) {
        PendingWorkVisuals.statusLine(for: .bundle(bundle), now: now)
    }

    var body: some View {
        HStack(spacing: 10) {
            PendingWorkStatusGlyph(tone: bundle.tone, statusRaw: payload.statusRaw)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(SyncStatusCopy.PendingWork.draftTitle(displayName: bundle.title))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: OPSStyle.Layout.spacing1)

                    Text(PendingWorkVisuals.relativeTime(from: bundle.createdAt, now: now))
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                }

                if bundle.siteVisitOperationIds.isEmpty {
                    memberStrip
                } else {
                    Text(SyncStatusCopy.PendingWork.siteVisitPacketSummary(
                        capturedItemCount: bundle.capturedItemCount,
                        blockedStage: bundle.blockedStage
                    ))
                    .font(OPSStyle.Typography.nanoLabel)
                    .tracking(0.8)
                    .foregroundColor(PendingWorkVisuals.toneColor(bundle.tone))
                }

                Text(statusLine.text)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(PendingWorkVisuals.statusColor(statusLine.tone))
                    .lineLimit(1)
            }

            if bundle.tone >= .attention {
                PendingWorkRetryGlyph(action: onRetry)
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bundle.title), \(statusLine.text)")
    }

    /// `CLIENT · LEAD · DECK · PHOTOS` — each member label tinted by its own
    /// tone with a small state glyph, separated by muted dots.
    private var memberStrip: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            ForEach(Array(bundle.members.enumerated()), id: \.element.id) { index, member in
                if index > 0 {
                    Text("·")
                        .font(OPSStyle.Typography.nanoLabel)
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
                HStack(spacing: 3) {
                    Text(SyncStatusCopy.PendingWork.memberLabel(member.role))
                        .font(OPSStyle.Typography.nanoLabel)
                        .tracking(0.8)
                        .foregroundColor(PendingWorkVisuals.toneColor(member.tone))
                    Image(systemName: PendingWorkVisuals.glyphName(member.tone))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(PendingWorkVisuals.toneColor(member.tone))
                }
            }
        }
    }
}

// MARK: - Draft row (uncommitted site visit)

/// A never-sent site-visit capture. Taps straight to resume — no detail sheet.
struct PendingWorkDraftRow: View {
    let draft: DraftSnapshot
    let now: Date
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(SyncStatusCopy.PendingWork.draftTitle(displayName: draft.displayName))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Text(SyncStatusCopy.PendingWork.draftRow)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityLabel("\(SyncStatusCopy.PendingWork.draftTitle(displayName: draft.displayName)), \(SyncStatusCopy.PendingWork.draftRow)")
    }
}

// MARK: - Orphan row (unlinked deck design)

/// A server-orphaned deck design. Thumb placeholder + title + inline LINK
/// shortcut; tapping the row opens the design in the builder.
struct PendingWorkOrphanRow: View {
    let design: OrphanDesignSnapshot
    let now: Date
    let onOpen: () -> Void
    let onLink: () -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(SyncStatusCopy.PendingWork.orphanTitle(title: design.title))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Text(SyncStatusCopy.PendingWork.orphanRow)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            Button(action: onLink) {
                Text(SyncStatusCopy.PendingWork.linkAction)
                    .font(OPSStyle.Typography.miniLabelBold)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .frame(minHeight: 32)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Link \(design.title)")
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    /// 32pt thumb block — filled state when a render exists, empty grid glyph
    /// otherwise. The pure row never loads remote images (snapshot-stable).
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
            .fill(design.hasThumbnail ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: design.hasThumbnail ? "square.grid.2x2.fill" : "square.grid.2x2")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
