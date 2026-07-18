//
//  LeadActivityHistoryView.swift
//  OPS
//
//  VIEW ALL → destination for the lead's activity stream (Leads redesign
//  spec §5.10): the SAME merged rows the dossier caps at six, uncapped.
//

import SwiftUI
import UIKit

struct LeadActivityHistoryView: View {
    let activities: [Activity]
    let transitions: [StageTransition]

    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Set<String> = []

    private var entries: [LeadStreamEntry] {
        LeadStreamEntry.merged(activities: activities, transitions: transitions)
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        PanelSectionHeader(label: "ACTIVITY", count: entries.count)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.top, OPSStyle.Layout.spacing2_5)
                            .padding(.bottom, 10)

                        VStack(spacing: 0) {
                            ForEach(entries) { entry in
                                LeadStreamRow(
                                    entry: entry,
                                    isExpanded: expanded.contains(entry.id),
                                    onToggle: { toggle(entry.id) }
                                )
                                if entry.id != entries.last?.id {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.surfaceInput)
                                        .frame(height: 1)
                                        .padding(.horizontal, 14)
                                }
                            }
                        }
                        .commandCard()
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, 100)   // clears the tab bar
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarHidden(true)
    }

    private var navBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .regular))
                    Text("LEAD")
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .fontWeight(.semibold)
                        .kerning(1.4)
                        .textCase(.uppercase)
                }
                .foregroundColor(OPSStyle.Colors.text2)
                .padding(.leading, OPSStyle.Layout.spacing1)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Back to lead")

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(height: 52)
    }

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(OPSStyle.Animation.curve(OPSStyle.Animation.durationHover)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }
}
