//
//  InventoryMethodChoiceView.swift
//  OPS
//
//  Full-screen method choice for inventory setup wizard Step 1.
//  Presents "Add Items Manually" and "Import from Spreadsheet" options.
//

import SwiftUI

struct InventoryMethodChoiceView: View {
    let onManual: () -> Void
    let onImport: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            // Scrim
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { /* Prevent tap-through */ }

            // Card
            VStack(alignment: .leading, spacing: 0) {
                // Icon + Title
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.wizardAccent)

                    Text("SET UP YOUR INVENTORY")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.bottom, OPSStyle.Layout.spacing3)

                // Description
                Text("Track your materials, supplies, and equipment. Get alerts when stock runs low.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
                    .padding(.bottom, 28)

                // Add Items Manually button
                Button {
                    TutorialHaptics.lightTap()
                    onManual()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.invertedText)

                        Text("ADD ITEMS MANUALLY")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.invertedText)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.invertedText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .frame(height: 56)
                    .background(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(.bottom, OPSStyle.Layout.spacing2_5)

                // Import from Spreadsheet button
                Button {
                    TutorialHaptics.lightTap()
                    onImport()
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("IMPORT FROM SPREADSHEET")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .frame(height: 56)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .padding(.bottom, OPSStyle.Layout.spacing4)

                // Skip for Now
                Button {
                    TutorialHaptics.lightTap()
                    onSkip()
                } label: {
                    Text("SKIP FOR NOW")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
            .padding(28)
            .glassDense()
            .padding(.horizontal, OPSStyle.Layout.spacing4)
        }
    }
}
