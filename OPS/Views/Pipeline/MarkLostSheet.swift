//
//  MarkLostSheet.swift
//  OPS
//
//  Bottom sheet to mark an opportunity as lost — requires a loss reason.
//

import SwiftUI

struct MarkLostSheet: View {
    let opportunity: Opportunity
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lossReason = ""

    private var isValid: Bool {
        !lossReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                Text("MARK AS LOST")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("This will move \(opportunity.contactName) to the Lost stage. Please provide a reason.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text("LOSS REASON")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextEditor(text: $lossReason)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                Spacer()

                Button("MARK AS LOST") {
                    onConfirm(lossReason.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .opsDestructiveButtonStyle()
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.5)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(OPSStyle.Layout.largeCornerRadius)
        .presentationDragIndicator(.visible)
    }
}
