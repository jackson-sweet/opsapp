import SwiftUI
import OPSDesignKit

struct DecksUpgradeSurface: View {
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text(OPSDecksUpgradeCopy.title)
                .font(OPSStyle.Typography.section)
                .foregroundStyle(OPSStyle.Colors.text)

            Text(OPSDecksUpgradeCopy.body)
                .font(OPSStyle.Typography.caption)
                .foregroundStyle(OPSStyle.Colors.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing4)
        .background(OPSStyle.Colors.glassApprox)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    DecksUpgradeSurface()
        .preferredColorScheme(.dark)
        .padding(OPSStyle.Layout.spacing4)
        .background(OPSStyle.Colors.background)
}
