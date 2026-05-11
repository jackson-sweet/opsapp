//
//  LeadActionSheet.swift
//  OPS
//
//  Bottom sheet of less-common actions for a lead. Triggered by ⋯ on LeadCardView.
//

import SwiftUI

struct LeadActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let opportunity: Opportunity
    let canManage: Bool
    var onMoveToStage: (PipelineStage) -> Void
    var onEdit: () -> Void
    var onLogActivity: () -> Void
    var onAddFollowUp: () -> Void
    var onOpenDetail: () -> Void
    var onArchive: () -> Void
    var onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        if canManage {
                            section(title: "MOVE TO STAGE") {
                                ForEach(PipelineStage.allCases) { stage in
                                    if stage != opportunity.stage {
                                        actionRow(label: stage.displayName, icon: "arrow.forward.circle") {
                                            onMoveToStage(stage); dismiss()
                                        }
                                    }
                                }
                            }
                        }

                        section(title: "ACTIONS") {
                            actionRow(label: "OPEN DETAIL", icon: "doc.text") { onOpenDetail(); dismiss() }
                            if canManage {
                                actionRow(label: "EDIT", icon: "pencil") { onEdit(); dismiss() }
                                actionRow(label: "LOG ACTIVITY", icon: "text.bubble") { onLogActivity(); dismiss() }
                                actionRow(label: "ADD FOLLOW-UP", icon: "calendar.badge.plus") { onAddFollowUp(); dismiss() }
                            }
                        }

                        if canManage {
                            section(title: "ARCHIVE") {
                                actionRow(label: "ARCHIVE", icon: "archivebox", tint: OPSStyle.Colors.warningStatus) {
                                    onArchive(); dismiss()
                                }
                                actionRow(label: "DELETE", icon: "trash", tint: OPSStyle.Colors.errorStatus) {
                                    onDelete(); dismiss()
                                }
                            }
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            VStack(spacing: 0) { content() }
                .background(OPSStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
    }

    @ViewBuilder
    private func actionRow(label: String, icon: String, tint: Color = OPSStyle.Colors.primaryText, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(tint)
                    .frame(width: 28)
                Text(label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(tint)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
