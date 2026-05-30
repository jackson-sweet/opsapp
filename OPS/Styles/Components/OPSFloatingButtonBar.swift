//
//  OPSFloatingButtonBar.swift
//  OPS
//
//  Standardized container for sticky bottom action bars that float over
//  scrollable content. Frosted material backdrop, hairline top border,
//  tokenized padding, and safe-area aware. Use anywhere a row of CTAs
//  needs to sit at the bottom of a sheet, form, or detail view above
//  scrollable content.
//
//      ZStack(alignment: .bottom) {
//          ScrollView { ... }
//              .padding(.bottom, 120)   // footer clearance
//
//          OPSFloatingButtonBar {
//              HStack(spacing: OPSStyle.Layout.spacing3) {
//                  Button("CANCEL") { ... }.opsSecondaryButtonStyle()
//                  Button("SAVE")   { ... }.opsPrimaryButtonStyle()
//              }
//          }
//      }
//
//  For composite footers with validation errors, totals, or other rows
//  above the button cluster, pass everything inside the trailing closure —
//  the bar wraps it all in a single frosted surface.
//

import SwiftUI

struct OPSFloatingButtonBar<Content: View>: View {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let respectsBottomSafeArea: Bool
    let content: Content

    init(
        horizontalPadding: CGFloat = OPSStyle.Layout.spacing3_5,
        verticalPadding: CGFloat = OPSStyle.Layout.spacing3,
        respectsBottomSafeArea: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.respectsBottomSafeArea = respectsBottomSafeArea
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, horizontalPadding)
                .padding(.top, verticalPadding)
                .padding(.bottom, respectsBottomSafeArea ? verticalPadding : 0)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                OPSStyle.Colors.background.opacity(0.55)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .ignoresSafeArea(edges: respectsBottomSafeArea ? .bottom : [])
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Preview

#Preview("Two buttons") {
    ZStack(alignment: .bottom) {
        OPSStyle.Colors.background.ignoresSafeArea()

        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<20) { i in
                    Text("Row \(i)")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }
            }
            .padding()
            .padding(.bottom, 120)
        }

        OPSFloatingButtonBar {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Button("SAVE DRAFT") { }
                    .opsSecondaryButtonStyle()
                Button("SUBMIT") { }
                    .opsPrimaryButtonStyle()
            }
        }
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
}

#Preview("With validation row") {
    ZStack(alignment: .bottom) {
        OPSStyle.Colors.background.ignoresSafeArea()

        OPSFloatingButtonBar {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(OPSStyle.Icons.exclamationmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Text("Amount is required")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                }
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    Button("SAVE DRAFT") { }
                        .opsSecondaryButtonStyle()
                    Button("SUBMIT") { }
                        .opsPrimaryButtonStyle()
                }
            }
        }
    }
}
