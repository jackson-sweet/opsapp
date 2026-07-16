//
//  LeadsWonChooserSheet.swift
//  OPS
//
//  Money & Leads redesign (2026-07-01) — the picker behind the WON · CONVERT
//  nudge when more than one deal is won-but-unconverted. A single unconverted
//  win goes straight to ConvertToProjectSheet; two or more land here first so
//  the operator sees every open win (value + how long it's sat) and picks which
//  to turn into a job. Tapping a row hands that lead to the convert flow.
//
//  Presented as a medium-detent sheet from LeadsTabView (`LeadsSheet.wonChooser`);
//  the parent owns the chooser → convert hand-off so only one sheet shows at a
//  time.
//

import SwiftUI

struct LeadsWonChooserSheet: View {
    /// Won leads with no project yet — `triageBuckets.unconvertedWon`.
    let leads: [Opportunity]
    /// Hands the chosen lead back to the parent to open the convert flow.
    var onPick: (Opportunity) -> Void

    @Environment(\.dismiss) private var dismiss

    private var totalValue: Double {
        leads.reduce(0) { $0 + ($1.actualValue ?? $1.estimatedValue ?? 0) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(leads.enumerated()), id: \.element.id) { idx, lead in
                            WonChooserRow(lead: lead) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onPick(lead)
                            }
                            if idx < leads.count - 1 {
                                Rectangle()
                                    .fill(OPSStyle.Colors.lineSoft)
                                    .frame(height: 1)
                                    .padding(.leading, 52)   // clears the leading glyph
                            }
                        }
                    }
                    .commandCard()
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Drag handle is provided by the parent's `.presentationDragIndicator`
            SheetTitleLabel(title: "CONVERT A WIN", size: .half)

            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("\(leads.count) WON · ")
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
                Text("\(BooksFormat.compact(totalValue)) UNCONVERTED")
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(OPSStyle.Typography.miniLabelBold)
            .tracking(1.4)
            .textCase(.uppercase)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, 14)
    }
}

// MARK: - Row

/// One unconverted-win row — olive check, contact + won-age/source subline,
/// value, and a chevron affordance. 56pt min height per MOBILE.md §7.1.
/// Internal (not private) so the snapshot harness can render the row list
/// directly — ImageRenderer does not resolve content inside a ScrollView.
struct WonChooserRow: View {
    let lead: Opportunity
    let action: () -> Void

    private var value: Double? {
        let v = lead.actualValue ?? lead.estimatedValue
        return (v ?? 0) > 0 ? v : nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous).fill(OPSStyle.Colors.oliveFillM))

                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.displayContactName)
                        .font(.custom("Mohave-Medium", size: 15))
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subline)
                        .font(.custom("JetBrainsMono-Regular", size: 9.5))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(value.map(BooksFormat.currency) ?? "—")
                    .font(.custom("JetBrainsMono-Medium", size: 14))
                    .foregroundColor(value != nil ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(lead.displayContactName), \(subline), convert to a project")
    }

    /// "WON 3D AGO · REFERRAL" — how long the win has waited, plus the source
    /// when present. Source is dropped when unknown so the line never trails a
    /// bare separator.
    private var subline: String {
        var parts = [wonAge]
        if let source = lead.source, !source.isEmpty {
            parts.append(source.replacingOccurrences(of: "_", with: " ").uppercased())
        }
        return parts.joined(separator: " · ")
    }

    private var wonAge: String {
        let ref = lead.actualCloseDate ?? lead.stageEnteredAt ?? lead.updatedAt
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: ref),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        if days <= 0 { return "WON TODAY" }
        if days == 1 { return "WON 1D AGO" }
        return "WON \(days)D AGO"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadsWonChooserSheet") {
    let leads: [Opportunity] = [
        {
            let o = Opportunity.preview(title: "Roof tear-off, 28 sq", contactName: "Helen Calloway", stage: .won, estimatedValue: 14_200, daysInStage: 2)
            o.source = "referral"
            o.actualCloseDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())
            return o
        }(),
        {
            let o = Opportunity.preview(title: "Maple Lane porch", contactName: "Tom Liu", stage: .won, estimatedValue: 11_200, daysInStage: 5)
            o.source = "website"
            o.actualCloseDate = Date()
            return o
        }(),
        {
            let o = Opportunity.preview(title: "Skylight install", contactName: "Aimee Watari", stage: .won, estimatedValue: nil, daysInStage: 8)
            o.actualCloseDate = Calendar.current.date(byAdding: .day, value: -8, to: Date())
            return o
        }(),
    ]
    return Color.black
        .sheet(isPresented: .constant(true)) {
            LeadsWonChooserSheet(leads: leads, onPick: { _ in })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
}
#endif
