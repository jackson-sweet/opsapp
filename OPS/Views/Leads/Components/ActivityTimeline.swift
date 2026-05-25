//
//  ActivityTimeline.swift
//  OPS
//
//  Recent activity rail on LeadDetailView. Renders the most-recent 5
//  activities for the opportunity. Each row:
//
//      ┌──┐
//      │📞│  ↓ Inbound call                                 5D
//      └──┘  6 min · asked about timing
//
//  Direction prefix (↓ inbound / ↑ outbound) is applied to the title.
//  Icon tile is tinted oliveTextM for inbound (the only color cue), text2
//  for outbound / undirected.
//
//  Empty state: a single muted `// NO ACTIVITY LOGGED` line inside the
//  card. Card itself always renders so the section heading stays anchored.
//

import SwiftUI

struct ActivityTimeline: View {
    /// Pre-sorted activities (newest first). Caller is responsible for ordering;
    /// the view trims to the first `maxItems`.
    let activities: [Activity]
    var maxItems: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(label: "RECENT ACTIVITY", hint: countHint)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            content
                .glassSurface()
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Card content

    @ViewBuilder
    private var content: some View {
        if activities.isEmpty {
            EmptyLine(text: "// NO ACTIVITY LOGGED")
        } else {
            let shown = Array(activities.prefix(maxItems))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { idx, activity in
                    ActivityRow(activity: activity)
                    if idx < shown.count - 1 {
                        Rectangle()
                            .fill(OPSStyle.Colors.surfaceInput)
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                }
            }
        }
    }

    // MARK: - Derived

    private var countHint: String? {
        if activities.isEmpty { return nil }
        let shown = min(activities.count, maxItems)
        if activities.count > maxItems {
            return "\(shown) OF \(activities.count)"
        }
        return String(format: "%02d", shown)
    }
}

// MARK: - Row (private)

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconTile

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.custom("Mohave-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let body = bodyText {
                    Text(body)
                        .font(.custom("Mohave-Regular", size: 12.5))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ageString)
                .font(.custom("JetBrainsMono-Regular", size: 9.5))
                .foregroundColor(OPSStyle.Colors.textMute)
                .kerning(1.0)
                .textCase(.uppercase)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Visual elements

    private var iconTile: some View {
        Image(systemName: iconName)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(iconTint)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
    }

    // MARK: - Derived

    private var iconName: String { activity.type.icon }

    private var iconTint: Color {
        activity.direction == "inbound"
            ? OPSStyle.Colors.oliveTextM
            : OPSStyle.Colors.text2
    }

    /// Title: optional ↓/↑ direction prefix + (subject ?? bodyText ?? type name).
    private var titleText: String {
        let prefix: String
        switch activity.direction {
        case "inbound":  prefix = "↓ "
        case "outbound": prefix = "↑ "
        default:         prefix = ""
        }

        if let subject = activity.subject, !subject.isEmpty {
            return prefix + subject
        }
        if let body = activity.displayBody, !body.isEmpty {
            return prefix + body
        }
        return prefix + activity.type.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }

    /// Body: rendered only if subject was used as title (so we don't duplicate).
    private var bodyText: String? {
        guard let subject = activity.subject, !subject.isEmpty else { return nil }
        guard let body = activity.displayBody, !body.isEmpty, body != subject else { return nil }
        return body
    }

    private var ageString: String {
        let interval = Date().timeIntervalSince(activity.createdAt)
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
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .kerning(1.6)
            .foregroundColor(OPSStyle.Colors.textMute)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ActivityTimeline / loaded") {
    ScrollView {
        VStack(spacing: 24) {
            ActivityTimeline(activities: [
                {
                    let a = Activity(opportunityId: "p", companyId: "p", type: .email,
                                     createdAt: Calendar.current.date(byAdding: .day, value: -4, to: Date())!)
                    a.direction = "outbound"
                    a.subject = "Quote — 28 sq tear-off"
                    a.bodyText = "Sent revised pricing with two roof options"
                    return a
                }(),
                {
                    let a = Activity(opportunityId: "p", companyId: "p", type: .call,
                                     createdAt: Calendar.current.date(byAdding: .day, value: -5, to: Date())!)
                    a.direction = "inbound"
                    a.subject = "Inbound call"
                    a.bodyText = "6 min · asked about timing"
                    return a
                }(),
                {
                    let a = Activity(opportunityId: "p", companyId: "p", type: .siteVisit,
                                     createdAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
                    a.direction = "outbound"
                    a.subject = "Site visit"
                    a.bodyText = "Walk + measure · 28 sq @ 4:12 pitch"
                    return a
                }(),
                {
                    let a = Activity(opportunityId: "p", companyId: "p", type: .note,
                                     createdAt: Calendar.current.date(byAdding: .day, value: -8, to: Date())!)
                    a.subject = "Internal note"
                    a.bodyText = "Homeowner mentioned competing quote from BlueSky"
                    return a
                }()
            ])
        }
        .padding(.vertical, 20)
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("ActivityTimeline / empty") {
    ScrollView {
        VStack(spacing: 24) {
            ActivityTimeline(activities: [])
        }
        .padding(.vertical, 20)
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
