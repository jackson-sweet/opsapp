//
//  CatalogManageHelpers.swift
//  OPS
//
//  Shared form/section helpers used by the catalog kebab manage sheets.
//  Kept narrow on purpose — Section / Field labels and a common
//  text-field style that all four sheets need.
//

import SwiftUI

@ViewBuilder
func CatalogSectionHeader(_ title: String) -> some View {
    Text("// \(title)")
        .font(OPSStyle.Typography.panelTitle)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}

@ViewBuilder
func CatalogFieldLabel(_ title: String) -> some View {
    Text(title)
        .font(OPSStyle.Typography.category)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}

struct CatalogTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
