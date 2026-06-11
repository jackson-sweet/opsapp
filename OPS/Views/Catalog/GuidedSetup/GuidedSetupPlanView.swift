//
//  GuidedSetupPlanView.swift
//  OPS
//
//  Shows the tailored setup plan derived from the survey: the ordered list of
//  modules this business needs, each optional, with a rough time. The "START"
//  CTA lives in the flow container's bottom bar.
//

import SwiftUI

struct GuidedSetupPlanView: View {
    @ObservedObject var model: GuidedCatalogSetupModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(Array(model.modules.enumerated()), id: \.offset) { item in
                        moduleRow(number: item.offset + 1, kind: item.element)
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// YOUR SETUP")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("HERE'S THE PLAN")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Built for how you work. Skip anything. Add more later.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moduleRow(number: Int, kind: SetupModuleKind) -> some View {
        let info = Self.info(for: kind)
        return HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
            Text(String(format: "%02d", number))
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(info.subtitle)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: OPSStyle.Layout.spacing2)

            Text(info.time)
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    static func info(for kind: SetupModuleKind) -> (title: String, subtitle: String, time: String) {
        switch kind {
        case .assembly: return ("JOB PACKAGES", "Fixed-price jobs — materials and labor, all in.", "~5 min")
        case .services: return ("YOUR SERVICES", "Name them and set your rates.", "~2 min")
        case .goods:    return ("YOUR GOODS", "The products you sell.", "~2 min")
        case .stock:    return ("YOUR STOCK", "Count what's on hand. Set reorder points.", "~3 min")
        }
    }
}

#Preview {
    let model = GuidedCatalogSetupModel(companyId: "preview", userId: "preview")
    model.profile = BusinessProfile(sells: .mix, pricing: .fixedJob,
                                    materialUse: .heavy, inventory: .tracked, trackCost: true)
    return ZStack {
        OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
        GuidedSetupPlanView(model: model)
    }
}
