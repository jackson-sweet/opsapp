//
//  ExpenseBulkCTABar.swift
//  OPS
//
//  The console's floating bulk-commit bar — APPROVE ALL / PAY ALL with the
//  dollar figure in the label so the operator commits to a number, not a
//  count. One per screen, olive (semantic positive commit), confirm dialog
//  behind it at the call site.
//

import SwiftUI

struct ExpenseBulkCTABar: View {
    let label: String
    /// Extra bottom padding when the global tab bar is visible (tab-root use).
    var bottomInset: CGFloat = 0
    let action: () -> Void

    var body: some View {
        OPSFloatingButtonBar(
            horizontalPadding: OPSStyle.Layout.spacing3,
            verticalPadding: OPSStyle.Layout.spacing2
        ) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                action()
            } label: {
                Text(label)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.successStatus)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.bottom, bottomInset)
    }
}
