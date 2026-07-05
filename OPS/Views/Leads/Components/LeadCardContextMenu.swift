//
//  LeadCardContextMenu.swift
//  OPS
//
//  The long-press menu shared by the triage queue (LeadsTabView) and the
//  by-stage list (PipelineStageListView) — extracted so the two never drift.
//  Edit + Archive are unchanged; Discard is added for non-terminal leads only
//  (a closed deal — won/lost/discarded — can't be junk-discarded). All actions
//  are gated by `canManage` (pipeline.manage).
//

import SwiftUI

struct LeadCardContextMenu: View {
    let lead: Opportunity
    let canManage: Bool
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDiscard: () -> Void   // sets the host's discard `target`

    var body: some View {
        if canManage {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: onArchive) {
                Label("Archive", systemImage: "archivebox")
            }
            if !lead.stage.isTerminal {
                Button(role: .destructive, action: onDiscard) {
                    Label("Discard", systemImage: "nosign")
                }
            }
        }
    }
}
