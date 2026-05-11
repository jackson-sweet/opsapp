//
//  LostReasonSheet.swift
//  OPS
//
//  Modal sheet that captures lost_reason + optional lost_notes when a lead is
//  marked Lost. Required field: reason (LossReason picker). Optional: notes.
//

import SwiftUI

struct LostReasonSheet: View {
    @Environment(\.dismiss) private var dismiss

    let opportunityTitle: String
    var onConfirm: (LossReason, String?) -> Void

    @State private var selectedReason: LossReason = .price
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        Text("MARK LOST")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text(opportunityTitle.uppercased())
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("REASON")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            VStack(spacing: 0) {
                                ForEach(LossReason.allCases) { reason in
                                    Button(action: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedReason = reason
                                    }) {
                                        HStack {
                                            Text(reason.displayName)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                            Spacer()
                                            if selectedReason == reason {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            }
                                        }
                                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if reason != LossReason.allCases.last {
                                        Divider().background(OPSStyle.Colors.cardBorder)
                                    }
                                }
                            }
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("NOTES (OPTIONAL)")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            TextEditor(text: $notes)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .scrollContentBackground(.hidden)
                                .padding(OPSStyle.Layout.spacing2)
                                .frame(minHeight: 120)
                                .background(OPSStyle.Colors.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CONFIRM") {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        onConfirm(selectedReason, notes.isEmpty ? nil : notes)
                        dismiss()
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
