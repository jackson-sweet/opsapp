//
//  StockView.swift
//  OPS
//
//  Stub placeholder for the STOCK segment of the CATALOG tab.
//

// FIXME(catalog): replace in Phase 6 Task 46

import SwiftUI

struct StockView: View {
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// STOCK")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("[Coming in Phase 6]")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
