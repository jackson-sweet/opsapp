//
//  ActivityTimeline.swift
//  OPS
//
//  ONE activity stream on LeadDetailView (Leads redesign spec §5.10) —
//  activities and stage changes merge-sorted into a single reverse-
//  chronological rail. Rows:
//
//      ↓  Quote question — email               2D  ⌄
//         └ expanded: the note / email gist (inline, mono-quiet)
//      ●  Stage: QUOTING → QUOTED              4D
//      ↑  Text to Helen — text                 5D
//
//  Direction glyphs: ↓ steel inbound (their touch — the YOUR MOVE tone),
//  ↑ olive outbound (your touch landed), type icon otherwise. Rows with a
//  body unfold inline (150ms, reduced-motion aware). Capped at `maxItems`
//  with a VIEW ALL → N footer pushing the full history.
//
//  Empty state: a single muted `// NO ACTIVITY LOGGED` line inside the
//  card. Card itself always renders so the section heading stays anchored.
//

import SwiftUI
import UIKit

/// One stream entry — an activity or a stage change folded into the rail.
enum LeadStreamEntry: Identifiable {
    case activity(Activity)
    case stage(StageTransition)

    var id: String {
        switch self {
        case .activity(let a): return "a-\(a.id)"
        case .stage(let t):    return "s-\(t.id)"
        }
    }

    var date: Date {
        switch self {
        case .activity(let a): return a.createdAt
        case .stage(let t):    return t.transitionedAt
        }
    }

    /// Merge-sort both sources newest-first.
    static func merged(activities: [Activity], transitions: [StageTransition]) -> [LeadStreamEntry] {
        (activities.map(LeadStreamEntry.activity) + transitions.map(LeadStreamEntry.stage))
            .sorted { $0.date > $1.date }
    }
}

struct ActivityTimeline: View {
    let activities: [Activity]
    let transitions: [StageTransition]
    var maxItems: Int = 6
    var onViewAll: () -> Void = {}

    /// Inline-expanded rows, per presentation (never persisted).
    @State private var expanded: Set<String> = []

    private var entries: [LeadStreamEntry] {
        LeadStreamEntry.merged(activities: activities, transitions: transitions)
    }

    var body: some View {
        let entries = self.entries
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(label: "ACTIVITY", count: entries.isEmpty ? nil : entries.count)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 10)

            content(entries)
                .commandCard()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    @ViewBuilder
    private func content(_ entries: [LeadStreamEntry]) -> some View {
        if entries.isEmpty {
            EmptyLine(text: "// NO ACTIVITY LOGGED")
        } else {
            let shown = Array(entries.prefix(maxItems))
            VStack(spacing: 0) {
                ForEach(shown) { entry in
                    LeadStreamRow(
                        entry: entry,
                        isExpanded: expanded.contains(entry.id),
                        onToggle: { toggle(entry.id) }
                    )
                    if entry.id != shown.last?.id {
                        Rectangle()
                            .fill(OPSStyle.Colors.surfaceInput)
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                }

                if entries.count > maxItems {
                    Rectangle()
                        .fill(OPSStyle.Colors.lineSoft)
                        .frame(height: 1)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onViewAll()
                    } label: {
                        HStack(spacing: 6) {
                            Text("VIEW ALL")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                            Spacer(minLength: 0)
                            Text("\(entries.count)")
                                .monospacedDigit()
                        }
                        .font(.custom("JetBrainsMono-Medium", size: 9.5))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all \(entries.count) activities")
                }
            }
        }
    }

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(OPSStyle.Animation.curve(OPSStyle.Animation.durationHover)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}

// MARK: - Row (shared with LeadActivityHistoryView)

struct LeadStreamRow: View {
    let entry: LeadStreamEntry
    let isExpanded: Bool
    var onToggle: () -> Void = {}

    var body: some View {
        switch entry {
        case .activity(let activity):
            activityRow(activity)
        case .stage(let transition):
            stageRow(transition)
        }
    }

    // MARK: Activity row

    @ViewBuilder
    private func activityRow(_ activity: Activity) -> some View {
        let body = expandableBody(activity)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if body != nil { onToggle() }
            } label: {
                HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2_5) {
                    glyph(activity)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(titleText(activity))
                            .font(.custom("Mohave-Medium", size: 14))
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let metadata = metadataText(activity) {
                            Text(metadata)
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(metadataColor(activity))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(Self.ageString(entry.date))
                        .font(OPSStyle.Typography.nanoLabel)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .kerning(1.0)
                        .textCase(.uppercase)
                        .monospacedDigit()

                    if body != nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.textMute)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(body == nil)
            .accessibilityLabel(accessibilityLabel(activity, hasBody: body != nil))

            if isExpanded, let body {
                Text(body)
                    .font(.custom("Mohave-Regular", size: 12.5))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.leading, 20 + OPSStyle.Layout.spacing2_5)
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)
                    .transition(.opacity)
            }
        }
    }

    /// Direction glyph — ↓ steel inbound (their move tone), ↑ olive outbound,
    /// the type icon otherwise.
    @ViewBuilder
    private func glyph(_ activity: Activity) -> some View {
        switch activity.direction {
        case "inbound":
            Text("↓")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.opsAccent)
        case "outbound":
            Text("↑")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.oliveTextM)
        default:
            Image(systemName: activity.type.icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(OPSStyle.Colors.text3)
        }
    }

    private func titleText(_ activity: Activity) -> String {
        if let subject = activity.subject, !subject.isEmpty { return subject }
        if let body = activity.displayBody, !body.isEmpty { return body }
        return activity.type.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    /// The inline-expandable body — only when it adds something beyond the
    /// title line.
    private func expandableBody(_ activity: Activity) -> String? {
        guard let subject = activity.subject, !subject.isEmpty else { return nil }
        guard let body = activity.displayBody, !body.isEmpty, body != subject else { return nil }
        return body
    }

    /// Duration and/or outcome, joined with a middot.
    private func metadataText(_ activity: Activity) -> String? {
        let duration = activity.durationMinutes.flatMap(formatDuration)
        let outcome = activity.outcome.flatMap(formatOutcome)
        switch (duration, outcome) {
        case let (.some(d), .some(o)): return "\(d) · \(o)"
        case let (.some(d), .none):    return d
        case let (.none, .some(o)):    return o
        case (.none, .none):           return nil
        }
    }

    private func metadataColor(_ activity: Activity) -> Color {
        guard let outcome = activity.outcome else { return OPSStyle.Colors.text3 }
        return outcomeColor(outcome)
    }

    private func formatDuration(_ minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainder) min"
    }

    private func formatOutcome(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// Semantic allowlist ONLY — never color by anything else. Defaults to text3.
    private func outcomeColor(_ raw: String) -> Color {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        let positive: Set<String> = ["connected", "answered", "reached", "spoke"]
        let negative: Set<String> = [
            "no answer", "voicemail", "left voicemail", "declined", "not interested", "no show"
        ]
        if positive.contains(normalized) { return OPSStyle.Colors.oliveTextM }
        if negative.contains(normalized) { return OPSStyle.Colors.roseTextM }
        return OPSStyle.Colors.text3
    }

    private func accessibilityLabel(_ activity: Activity, hasBody: Bool) -> String {
        var parts: [String] = []
        switch activity.direction {
        case "inbound":  parts.append("Inbound")
        case "outbound": parts.append("Outbound")
        default:         break
        }
        parts.append(titleText(activity))
        parts.append(Self.ageString(entry.date).lowercased())
        if hasBody { parts.append(isExpanded ? "expanded" : "collapsed") }
        return parts.joined(separator: ", ")
    }

    // MARK: Stage row (folded-in transition)

    private func stageRow(_ transition: StageTransition) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text("●")
                .font(.system(size: 6))
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(width: 20)

            HStack(spacing: 5) {
                Text("Stage:")
                    .font(.custom("Mohave-Regular", size: 13))
                    .foregroundColor(OPSStyle.Colors.text3)
                if let from = transition.fromStage {
                    Text(from.shortLabel)
                        .font(OPSStyle.Typography.nanoLabel)
                        .fontWeight(.semibold)
                        .kerning(1.0)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .textCase(.uppercase)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
                Text(transition.toStage.displayName)
                    .font(OPSStyle.Typography.nanoLabel)
                    .fontWeight(.semibold)
                    .kerning(1.0)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.ageString(entry.date))
                .font(OPSStyle.Typography.nanoLabel)
                .foregroundColor(OPSStyle.Colors.textMute)
                .kerning(1.0)
                .textCase(.uppercase)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stageAccessibilityLabel(transition))
    }

    private func stageAccessibilityLabel(_ transition: StageTransition) -> String {
        let from = transition.fromStage.map { "\($0.displayName) to " } ?? ""
        return "Stage change, \(from)\(transition.toStage.displayName), \(Self.ageString(entry.date).lowercased())"
    }

    // MARK: Age

    static func ageString(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60      { return "NOW" }
        let mins = Int(interval / 60)
        if mins < 60          { return "\(mins)M" }
        let hours = mins / 60
        if hours < 24         { return "\(hours)H" }
        let days = hours / 24
        if days < 7           { return "\(days)D" }
        let weeks = days / 7
        if weeks < 5          { return "\(weeks)W" }
        let months = days / 30
        return "\(months)MO"
    }
}

// MARK: - Empty inline line (private)

private struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(OPSStyle.Typography.miniLabel)
            .kerning(1.6)
            .foregroundColor(OPSStyle.Colors.textMute)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
    }
}
