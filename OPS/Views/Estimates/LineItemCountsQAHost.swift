//
//  LineItemCountsQAHost.swift
//  OPS
//
//  DEBUG-only harness for count options on estimate line items. Launch with
//  `-OPS_LINE_ITEM_COUNTS_QA` (new line) or add `-OPS_LINE_ITEM_COUNTS_QA_EDIT`
//  (existing line).
//
//  Seeds the shape of Canpro's "Picket Rail — Level" into an in-memory store —
//  four selects and five integer counts, the counts still carrying the
//  catalogue defaults production held before 2026-09-17 (1, 1, 0, 0, 0) so the
//  harness proves none of them is honoured — and presents the REAL
//  `LineItemEditSheet` over this card.
//
//  The view model is never set up, so a save that passes the sheet's gate
//  writes nothing and the sheet closes: SHEET CLOSED is the assertion surface
//  for "the save went through".
//

#if DEBUG
import SwiftData
import SwiftUI

struct LineItemCountsQAHost: View {
    @StateObject private var viewModel = EstimateViewModel()

    @State private var isPresentingSheet = false
    @State private var editingLine: EstimateLineItem?
    @State private var product: Product?
    @State private var isReady = false

    static let estimateId = "qa_line_item_counts_estimate"

    private static let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create line item counts QA container: \(error.localizedDescription)")
        }
    }()

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                Text("// LINE ITEM COUNTS QA")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.text)

                Text(isPresentingSheet ? "SHEET PRESENTED" : "SHEET CLOSED")
                    .font(OPSStyle.Typography.dataValueLg)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .accessibilityIdentifier("qa_line_item_sheet_state")

                Button {
                    isPresentingSheet = true
                } label: {
                    Text("OPEN LINE ITEM")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                        .nestedCard()
                }
                .buttonStyle(.plain)
                .disabled(!isReady)
                .accessibilityIdentifier("qa_line_item_open")

                Spacer()
            }
            .padding(OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing5)
        }
        .preferredColorScheme(.dark)
        .modelContainer(Self.modelContainer)
        .sheet(isPresented: $isPresentingSheet) {
            LineItemEditSheet(
                estimateId: Self.estimateId,
                viewModel: viewModel,
                editing: editingLine,
                // The estimate form hands no product in when it opens an
                // existing line; the sheet must find it from the line.
                product: editingLine == nil ? product : nil
            )
            .modelContainer(Self.modelContainer)
        }
        .task { prepare() }
    }

    @MainActor
    private func prepare() {
        guard !isReady else { return }
        let context = Self.modelContainer.mainContext
        let seeded = LineItemCountsQAFixture.seed(into: context)
        product = seeded.product
        if LineItemCountsQARuntime.opensExistingLine() {
            editingLine = seeded.existingLine
        }
        try? context.save()
        isReady = true
        isPresentingSheet = true
    }
}

enum LineItemCountsQAFixture {
    static let productId = "qa_canpro_picket_rail_level"

    struct Seeded {
        let product: Product
        let existingLine: EstimateLineItem
    }

    @MainActor
    static func seed(into context: ModelContext) -> Seeded {
        let product = Product(
            id: productId,
            companyId: "qa_line_item_counts_company",
            name: "Picket Rail — Level",
            type: .material,
            kind: .good,
            basePrice: 70,
            pricingUnit: .linearFoot
        )
        context.insert(product)

        let selects: [(id: String, name: String, defaultValue: String, values: [String])] = [
            ("qa_opt_color", "Color", "Black", ["Black", "White", "Bronze"]),
            ("qa_opt_mount", "Mount Type", "Side mount", ["Side mount", "Top mount"]),
            ("qa_opt_height", "Height", "42\"", ["36\"", "42\""]),
            ("qa_opt_lag", "Lag length", "3\"", ["3\"", "4\""]),
        ]
        var sortOrder = 0
        for select in selects {
            context.insert(ProductOption(
                id: select.id, productId: productId, name: select.name,
                kind: .select, affectsRecipe: true, required: true,
                defaultValue: select.defaultValue, sortOrder: sortOrder
            ))
            for (index, value) in select.values.enumerated() {
                context.insert(ProductOptionValue(
                    id: "\(select.id)_\(index)", optionId: select.id, value: value, sortOrder: index
                ))
            }
            sortOrder += 1
        }

        let counts: [(id: String, name: String, defaultValue: String)] = [
            ("qa_opt_left", "Left ends", "1"),
            ("qa_opt_right", "Right ends", "1"),
            ("qa_opt_corners", "Corners", "0"),
            ("qa_opt_45", "45° corners", "0"),
            ("qa_opt_wall", "Wall returns", "0"),
        ]
        for count in counts {
            context.insert(ProductOption(
                id: count.id, productId: productId, name: count.name,
                kind: .integer, affectsRecipe: true, required: true,
                defaultValue: count.defaultValue, sortOrder: sortOrder
            ))
            sortOrder += 1
        }

        // An existing line saved before counts were required: two counts on it
        // (one of them a real 0), the rest never entered.
        let existingLine = EstimateLineItem(
            id: "qa_line_item_counts_existing",
            estimateId: LineItemCountsQAHost.estimateId,
            name: "Picket Rail — Level",
            type: .material,
            quantity: 20,
            unitPrice: 70,
            configuredOptionsJSON: #"{"qa_opt_color":"qa_opt_color_1","qa_opt_left":2,"qa_opt_right":0}"#,
            resolvedUnitPrice: 70,
            resolvedOptionsLabel: "White · 2 left ends"
        )
        existingLine.productId = productId
        existingLine.unit = ProductPricingUnit.linearFoot.rawValue
        context.insert(existingLine)

        return Seeded(product: product, existingLine: existingLine)
    }
}
#endif
