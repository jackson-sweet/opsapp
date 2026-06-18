//
//  StageTimeline.swift
//  OPS
//
//  Stage-history rail on LeadDetailView. Append-only — one row per
//  StageTransition record, ordered oldest → newest (so the eye reads
//  the path forward). The most-recent toStage is the only row drawn in
//  text-primary; prior transitions render text-3 so they read as past.
//
//      14D    NEW LEAD                          ← first transition, no from
//      11D    NEW → QUALIFYING
//       7D    QUAL → QUOTING
//       0D    QUOTING → QUOTED                  ← most recent (text-primary)
//
//  Age column is fixed 46pt left-aligned, mute mono. The chain uses the
//  shortLabel variant of PipelineStage so each cell stays compact.
//

import SwiftUI

struct StageTimeline: View {
    /// Pre-sorted transitions (oldest first). Caller is responsible for ordering.
    let transitions: [StageTransition]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(label: "STAGE HISTORY")
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 10)

            content
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    @ViewBuilder
    private var content: some View {
        if transitions.isEmpty {
            EmptyLine(text: "// NO STAGE CHANGES LOGGED")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(transitions.enumerated()), id: \.element.id) { idx, t in
                    StageRow(transition: t, isLatest: idx == transitions.count - 1)
                    if idx < transitions.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.03))  // no exact token
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .padding(.vertical, OPSStyle.Layout.spacing1)
        }
    }
}

// MARK: - Row (private)

private struct StageRow: View {
    let transition: StageTransition
    let isLatest: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(ageString)
                .font(.custom("JetBrainsMono-Regular", size: 9.5))
                .foregroundColor(OPSStyle.Colors.textMute)
                .kerning(1.0)
                .textCase(.uppercase)
                .monospacedDigit()
                .frame(width: 46, alignment: .leading)

            HStack(spacing: 6) {
                if let from = transition.fromStage {
                    Text(from.shortLabel)
                        .font(.custom("JetBrainsMono-Regular", size: 9.5))
                        .fontWeight(.semibold)
                        .kerning(1.26)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .textCase(.uppercase)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.textMute)
                }

                Text(transition.toStage.displayName)
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .fontWeight(.semibold)
                    .kerning(1.33)
                    .foregroundColor(isLatest ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private var ageString: String {
        let interval = Date().timeIntervalSince(transition.transitionedAt)
        if interval < 60     { return "NOW" }
        let mins = Int(interval / 60)
        if mins < 60         { return "\(mins)M" }
        let hours = mins / 60
        if hours < 24        { return "\(hours)H" }
        let days = hours / 24
        if days < 7          { return "\(days)D" }
        let weeks = days / 7
        if weeks < 5         { return "\(weeks)W" }
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
#Preview("StageTimeline / chain") {
    ScrollView {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            StageTimeline(transitions: [
                StageTransition(
                    companyId: "p", opportunityId: "p",
                    fromStage: nil, toStage: .newLead,
                    transitionedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())!
                ),
                StageTransition(
                    companyId: "p", opportunityId: "p",
                    fromStage: .newLead, toStage: .qualifying,
                    transitionedAt: Calendar.current.date(byAdding: .day, value: -11, to: Date())!
                ),
                StageTransition(
                    companyId: "p", opportunityId: "p",
                    fromStage: .qualifying, toStage: .quoting,
                    transitionedAt: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                ),
                StageTransition(
                    companyId: "p", opportunityId: "p",
                    fromStage: .quoting, toStage: .quoted,
                    transitionedAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                )
            ])
        }
        .padding(.vertical, OPSStyle.Layout.spacing3_5)
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("StageTimeline / empty") {
    ScrollView {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            StageTimeline(transitions: [])
        }
        .padding(.vertical, OPSStyle.Layout.spacing3_5)
    }
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
