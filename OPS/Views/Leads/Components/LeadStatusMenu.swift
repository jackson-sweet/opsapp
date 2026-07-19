//
//  LeadStatusMenu.swift
//  OPS
//
//  The ONE lead status dropdown (Leads redesign spec §6), hosted by two
//  chips: the detail nav-bar stage chip and the card's meta-row stage chip.
//  Native SwiftUI `Menu` — correct dropdown behavior, dimmed background,
//  44pt rows — whose label is provided by the host.
//
//  Contents: // SET STATUS section of the six open stages (current stage
//  checkmarked + disabled), WON →, then the guarded exits LOST / ARCHIVE /
//  DISCARD. Selection commits through the host's closures — the menu never
//  mutates; parents own moveToStage / convert / lost / archive / discard
//  routing and their confirmations.
//
//  Gating: stages + LOST/ARCHIVE/DISCARD require `canEdit`; WON requires
//  `canConvert`. A viewer with neither renders the label as plain content —
//  no menu, no dead affordance.
//

import SwiftUI
import UIKit

struct LeadStatusMenu<Label: View>: View {
    let lead: Opportunity
    let canEdit: Bool
    let canConvert: Bool
    /// Direct stage pick (open stages only — never .won).
    var onStage: (PipelineStage) -> Void
    var onWon: () -> Void      // parent routes to ConvertToProjectSheet
    var onLost: () -> Void     // parent routes to LostReasonSheet
    var onArchive: () -> Void  // parent shows OPSConfirm then archives
    var onDiscard: () -> Void  // parent runs leadDiscardFlow
    @ViewBuilder var label: () -> Label

    var body: some View {
        if canEdit || canConvert {
            Menu {
                menuContent
            } label: {
                label()
            }
            .accessibilityLabel("Status: \(lead.stage.displayName). Double-tap to change.")
        } else {
            label()
                .accessibilityLabel("Status: \(lead.stage.displayName)")
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if canEdit {
            Section("// SET STATUS") {
                ForEach(PipelineStage.openStages) { stage in
                    Button {
                        commit { onStage(stage) }
                    } label: {
                        if stage == lead.stage {
                            SwiftUI.Label(stage.displayName, systemImage: "checkmark")
                        } else {
                            Text(stage.displayName)
                        }
                    }
                    .disabled(stage == lead.stage)
                }
            }
        }
        if canConvert {
            Button { commit(onWon) } label: {
                SwiftUI.Label("WON →", systemImage: "checkmark.seal")
            }
        }
        if canEdit {
            Divider()
            Button(role: .destructive) { commit(onLost) } label: {
                Text("LOST")
            }
            Button { commit(onArchive) } label: {
                Text("ARCHIVE")
            }
            Button(role: .destructive) { commit(onDiscard) } label: {
                Text("DISCARD")
            }
        }
    }

    /// Medium impact on every selection — a status change is a commit moment
    /// (spec §10) — then the host's closure.
    private func commit(_ action: () -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        action()
    }
}

// MARK: - StageTag (shared chip label)

/// The earth-tone stage chip — promoted out of DetailHero so the detail nav
/// chip and the card's meta chip render the SAME tag. Mobile-contrast `-M`
/// token variants per MOBILE.md §1. Tone map (LEADS Phase 3 spec):
///
///   - .won                                   → olive
///   - .lost                                  → rose
///   - .quoted / .followUp / .negotiation     → tan
///   - .newLead / .qualifying / .quoting      → neutral
///
/// `detail` appends a mono qualifier inside the chip (`QUOTED · 9D`);
/// `showsChevron` adds the ▾ affordance when the chip hosts the status menu.
struct StageTag: View {
    let stage: PipelineStage
    var detail: String? = nil
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(stage.displayName)
            if let detail {
                Text("· \(detail)")
                    .monospacedDigit()
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
        }
        .font(OPSStyle.Typography.nanoLabel)
        .fontWeight(.semibold)
        .kerning(1.4)
        .foregroundColor(textColor)
        .textCase(.uppercase)
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var fillColor: Color {
        switch stage {
        case .won:                                   return OPSStyle.Colors.oliveFillM
        case .lost:                                  return OPSStyle.Colors.roseFillM
        case .quoted, .followUp, .negotiation:       return OPSStyle.Colors.tanFillM
        case .newLead, .qualifying, .quoting, .discarded:  return OPSStyle.Colors.surfaceHover
        }
    }

    private var borderColor: Color {
        switch stage {
        case .won:                                   return OPSStyle.Colors.oliveLineM
        case .lost:                                  return OPSStyle.Colors.roseLineM
        case .quoted, .followUp, .negotiation:       return OPSStyle.Colors.tanLineM
        case .newLead, .qualifying, .quoting, .discarded:  return OPSStyle.Colors.line
        }
    }

    private var textColor: Color {
        switch stage {
        case .won:                                   return OPSStyle.Colors.oliveTextM
        case .lost:                                  return OPSStyle.Colors.roseTextM
        case .quoted, .followUp, .negotiation:       return OPSStyle.Colors.tanTextM
        case .newLead, .qualifying, .quoting, .discarded:  return OPSStyle.Colors.text2
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadStatusMenu / hosts") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        VStack(spacing: 28) {
            LeadStatusMenu(
                lead: Opportunity.preview(contactName: "Helen Calloway", stage: .quoted),
                canEdit: true,
                canConvert: true,
                onStage: { _ in }, onWon: {}, onLost: {}, onArchive: {}, onDiscard: {}
            ) {
                StageTag(stage: .quoted, detail: "9D", showsChevron: true)
            }

            // Viewer — plain label, no menu affordance.
            LeadStatusMenu(
                lead: Opportunity.preview(contactName: "Tom Liu", stage: .negotiation),
                canEdit: false,
                canConvert: false,
                onStage: { _ in }, onWon: {}, onLost: {}, onArchive: {}, onDiscard: {}
            ) {
                StageTag(stage: .negotiation)
            }
        }
    }
    .preferredColorScheme(.dark)
}
#endif
