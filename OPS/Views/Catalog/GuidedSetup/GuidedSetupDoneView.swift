//
//  GuidedSetupDoneView.swift
//  OPS
//
//  Closing summary: what got built this run, ready for estimates. Fires the
//  §14 completion notification once on appear. The "View catalog" / "Done"
//  actions live in the flow container's bottom bar.
//

import SwiftUI

struct GuidedSetupDoneView: View {
    @ObservedObject var model: GuidedCatalogSetupModel

    private var hasResults: Bool { !model.savedLines.isEmpty || !model.savedAssemblies.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header

                if hasResults {
                    summaryCard
                    savedList
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.postCompletionNotification() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// DONE")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(hasResults ? "READY FOR ESTIMATES" : "ALL SET")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(hasResults
                 ? "These are in your catalog. Drop them on an estimate anytime."
                 : "Nothing saved this run. Add to your catalog whenever you're ready.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("// THIS RUN")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(GuidedCatalogSetupModel.summaryLine(services: model.savedServiceCount,
                                                     goods: model.savedGoodCount,
                                                     assemblies: model.savedAssemblyCount))
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var savedList: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            ForEach(model.savedAssemblies) { assembly in
                savedRow(name: assembly.name,
                         detail: assembly.marginPercent.map { "PACKAGE · \(Int($0.rounded()))% margin" } ?? "PACKAGE",
                         sell: assembly.sell)
            }
            ForEach(model.savedLines) { line in
                savedRow(name: line.name, detail: line.kind.displayLabel, sell: line.sell)
            }
        }
    }

    private func savedRow(name: String, detail: String, sell: Double) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Text(model.formatMoney(sell))
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var emptyState: some View {
        Text("—")
            .font(OPSStyle.Typography.pageTitle)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, OPSStyle.Layout.spacing4)
    }
}

#Preview {
    let model = GuidedCatalogSetupModel(companyId: "preview", userId: "preview")
    model.savedAssemblies = [SavedAssembly(id: "a1", name: "Rail install", sell: 1500, marginPercent: 62)]
    model.savedLines = [
        SavedProductLine(id: "1", name: "Standard clean", kind: .service, sell: 200)
    ]
    return ZStack {
        OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
        GuidedSetupDoneView(model: model)
    }
}
