//
//  CatalogImportSheet.swift
//  OPS
//
//  Multi-step CSV import for catalog families + variants AND for
//  service/product rows. Two tabs at the top — STOCK | PRODUCTS — pick
//  the target. Each tab shares the same four-step flow:
//  PICK → MAP → PREVIEW → APPLY, with its own parser/mapper/repository
//  and its own column-mapping config.
//
//  Atomic by construction — preview calls *_validate (no writes), apply
//  calls *_apply (full transaction). The user never observes a half-
//  imported state, and RETRY is safe — a re-applied payload either
//  lands or re-fails the same way.
//
//  Layout matches `QuickAddProductSheet`: backgroundGradient,
//  NavigationStack, large detent. Top: tab switch, then progress strip.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CatalogImportSheet: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss

    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]

    // MARK: - Tab state

    enum Tab: Int, CaseIterable, Hashable {
        case stock, products

        var label: String {
            switch self {
            case .stock:    return "STOCK"
            case .products: return "PRODUCTS"
            }
        }
    }

    @State private var tab: Tab = .stock

    // MARK: - Step state

    enum Step: Int, CaseIterable {
        case pick, map, preview, apply

        var label: String {
            switch self {
            case .pick:    return "PICK"
            case .map:     return "MAP"
            case .preview: return "PREVIEW"
            case .apply:   return "APPLY"
            }
        }
    }

    @State private var step: Step = .pick

    // MARK: - File / parse state (shared)

    @State private var isShowingFilePicker: Bool = false
    @State private var pickedFileName: String? = nil
    @State private var parsed: CSVParseResult? = nil
    @State private var parseError: String? = nil

    // MARK: - STOCK tab state

    @State private var stockMapping = CatalogImportColumnMapping()
    @State private var stockLocalErrors: [CatalogImportError] = []
    @State private var stockServerErrors: [CatalogImportError] = []
    @State private var stockPendingPayload: CatalogImportPayload? = nil

    @State private var stockApplyResult: CatalogImportResult? = nil

    // MARK: - PRODUCTS tab state

    @State private var productsMapping = ProductsImportColumnMapping()
    @State private var productsLocalErrors: [ProductsImportError] = []
    @State private var productsServerErrors: [ProductsImportError] = []
    @State private var productsPendingPayload: ProductsImportPayload? = nil

    @State private var productsApplyResult: ProductsImportResult? = nil

    // MARK: - Shared apply / progress state

    @State private var isValidating: Bool = false
    @State private var isApplying: Bool = false
    @State private var applyError: String? = nil

    // MARK: - Derived

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyCategoryTuples: [(id: String, name: String)] {
        allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .map { ($0.id, $0.name) }
    }

    private var companyUnitTuples: [(id: String, display: String)] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .map { ($0.id, $0.display) }
    }

    /// Did the apply for the active tab complete successfully? Drives the
    /// "Done" close-button label.
    private var activeApplySucceeded: Bool {
        switch tab {
        case .stock:    return stockApplyResult?.success == true
        case .products: return productsApplyResult?.success == true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    tabStrip
                    progressStrip

                    Group {
                        switch step {
                        case .pick:    pickStep
                        case .map:     mapStep
                        case .preview: previewStep
                        case .apply:   applyStep
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("IMPORT CATALOG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(closeLabel) { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .disabled(isApplying)
                }
            }
        }
        .presentationDetents([.large])
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.commaSeparatedText, UTType(filenameExtension: "csv") ?? .data],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
    }

    // MARK: - Header strips

    private var closeLabel: String {
        step == .apply && activeApplySucceeded ? "Done" : "Cancel"
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    guard tab != t else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    switchTab(to: t)
                } label: {
                    Text(t.label)
                        .font(OPSStyle.Typography.sectionLabel)
                        .foregroundColor(
                            tab == t
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(
                                    tab == t
                                        ? OPSStyle.Colors.primaryAccent
                                        : Color.clear
                                )
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .disabled(isApplying || isValidating)
            }
        }
        .background(Color.black.opacity(0.25))
    }

    private var progressStrip: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(Step.allCases, id: \.self) { s in
                Text(s.label)
                    .font(OPSStyle.Typography.sectionLabel)
                    .foregroundColor(
                        s.rawValue <= step.rawValue
                            ? OPSStyle.Colors.primaryText
                            : OPSStyle.Colors.tertiaryText
                    )
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .background(
                        Rectangle()
                            .fill(
                                s.rawValue == step.rawValue
                                    ? OPSStyle.Colors.primaryAccent.opacity(0.18)
                                    : Color.clear
                            )
                    )
                    .overlay(alignment: .bottom) {
                        if s.rawValue == step.rawValue {
                            Rectangle()
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(height: 2)
                        }
                    }
                if s != Step.allCases.last {
                    Image(OPSStyle.Icons.chevronRight)
                        .font(.caption2)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(Color.black.opacity(0.15))
    }

    /// Flush all per-tab state when switching, so a half-finished import
    /// in tab A never bleeds into tab B (and the user never sees the
    /// other tab's error list).
    private func switchTab(to newTab: Tab) {
        tab = newTab
        step = .pick
        parsed = nil
        pickedFileName = nil
        parseError = nil
        stockLocalErrors = []
        stockServerErrors = []
        stockPendingPayload = nil
        stockApplyResult = nil
        productsLocalErrors = []
        productsServerErrors = []
        productsPendingPayload = nil
        productsApplyResult = nil
        applyError = nil
        isValidating = false
        isApplying = false
    }

    // MARK: - Step 0: pick

    private var pickStep: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            Image(OPSStyle.Icons.download)
                .font(.system(size: 56, weight: .light))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            VStack(spacing: OPSStyle.Layout.spacing1) {
                Text("// SELECT CSV")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(pickSubtitle)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isShowingFilePicker = true
            } label: {
                Text("CHOOSE FILE")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .frame(maxWidth: 280)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }

            if let err = parseError {
                Text(err)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else if let name = pickedFileName {
                Text("LOADED  \(name)")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()
        }
        .padding(OPSStyle.Layout.spacing3)
    }

    private var pickSubtitle: String {
        switch tab {
        case .stock:
            return "One row per variant. Header row required."
        case .products:
            return "One row per product. Header row required."
        }
    }

    // MARK: - Step 1: map

    private var mapStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    Text("// MAP COLUMNS")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    if let parsed = parsed {
                        Text("\(parsed.rows.count) rows  ·  \(parsed.headers.count) columns detected")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    switch tab {
                    case .stock:    stockMapFields
                    case .products: productsMapFields
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button("BACK") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    step = .pick
                }
                .buttonStyle(SecondaryStepButton())

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    runDryRun()
                } label: {
                    Text("PREVIEW")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryStepButton(disabled: !isMapReady))
                .disabled(!isMapReady)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(Color.black.opacity(0.15))
        }
    }

    private var isMapReady: Bool {
        switch tab {
        case .stock:    return stockMapping.isReadyToMap
        case .products: return productsMapping.isReadyToMap
        }
    }

    @ViewBuilder
    private var stockMapFields: some View {
        mapRow(label: "FAMILY NAME *", binding: stockBindingFor(\.familyName))
        mapRow(label: "QUANTITY *", binding: stockBindingFor(\.quantity))
        Divider().background(OPSStyle.Colors.separator)

        Text("// FAMILY-LEVEL")
            .font(OPSStyle.Typography.sectionLabel)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
        mapRow(label: "DESCRIPTION", binding: stockBindingFor(\.familyDescription))
        mapRow(label: "CATEGORY", binding: stockBindingFor(\.category))
        mapRow(label: "DEFAULT UNIT", binding: stockBindingFor(\.defaultUnit))
        mapRow(label: "DEFAULT PRICE", binding: stockBindingFor(\.defaultPrice))
        mapRow(label: "DEFAULT UNIT COST", binding: stockBindingFor(\.defaultUnitCost))

        Divider().background(OPSStyle.Colors.separator)
        Text("// VARIANT-LEVEL")
            .font(OPSStyle.Typography.sectionLabel)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
        mapRow(label: "SKU", binding: stockBindingFor(\.sku))
        mapRow(label: "VARIANT UNIT", binding: stockBindingFor(\.variantUnit))
        mapRow(label: "PRICE OVERRIDE", binding: stockBindingFor(\.priceOverride))
        mapRow(label: "UNIT COST OVERRIDE", binding: stockBindingFor(\.unitCostOverride))
        mapRow(label: "WARNING THRESHOLD", binding: stockBindingFor(\.warningThreshold))
        mapRow(label: "CRITICAL THRESHOLD", binding: stockBindingFor(\.criticalThreshold))
    }

    @ViewBuilder
    private var productsMapFields: some View {
        mapRow(label: "NAME *", binding: productsBindingFor(\.name))
        mapRow(label: "BASE PRICE *", binding: productsBindingFor(\.basePrice))
        Divider().background(OPSStyle.Colors.separator)

        Text("// OPTIONAL")
            .font(OPSStyle.Typography.sectionLabel)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
        mapRow(label: "DESCRIPTION", binding: productsBindingFor(\.description))
        mapRow(label: "UNIT COST", binding: productsBindingFor(\.unitCost))
        mapRow(label: "CATEGORY", binding: productsBindingFor(\.category))
        mapRow(label: "UNIT", binding: productsBindingFor(\.unit))
        mapRow(label: "PRICING UNIT", binding: productsBindingFor(\.pricingUnit))
        mapRow(label: "SKU", binding: productsBindingFor(\.sku))
        mapRow(label: "KIND", binding: productsBindingFor(\.kind))
        mapRow(label: "TYPE", binding: productsBindingFor(\.type))
        mapRow(label: "TAXABLE", binding: productsBindingFor(\.isTaxable))
    }

    @ViewBuilder
    private func mapRow(label: String, binding: Binding<String?>) -> some View {
        let headers = parsed?.headers ?? []
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.sectionLabel)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("— None —") { binding.wrappedValue = nil }
                ForEach(headers, id: \.self) { h in
                    Button(h) { binding.wrappedValue = h }
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(binding.wrappedValue ?? "—")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(
                            binding.wrappedValue == nil
                                ? OPSStyle.Colors.tertiaryText
                                : OPSStyle.Colors.primaryText
                        )
                    Image(OPSStyle.Icons.chevronDown)
                        .font(.caption2)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    private func stockBindingFor(_ keyPath: WritableKeyPath<CatalogImportColumnMapping, String?>) -> Binding<String?> {
        Binding(
            get: { stockMapping[keyPath: keyPath] },
            set: { stockMapping[keyPath: keyPath] = $0 }
        )
    }

    private func productsBindingFor(_ keyPath: WritableKeyPath<ProductsImportColumnMapping, String?>) -> Binding<String?> {
        Binding(
            get: { productsMapping[keyPath: keyPath] },
            set: { productsMapping[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Step 2: preview

    private var previewStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    if isValidating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, OPSStyle.Layout.spacing4)
                        Text("// CHECKING")
                            .font(OPSStyle.Typography.sectionLabel)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if hasPreviewIssues {
                        Text("// \(previewErrorRows.count) ISSUE\(previewErrorRows.count == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.panelTitle)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                        Text("Fix the CSV (or remap columns) and try again. Nothing was imported.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            ForEach(previewErrorRows) { row in
                                errorRow(row)
                            }
                        }
                    } else if hasPreviewPayload {
                        Text("// READY")
                            .font(OPSStyle.Typography.panelTitle)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                        previewSummaryCard
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button("FIX & RETRY") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    step = .map
                }
                .buttonStyle(SecondaryStepButton())

                if hasPreviewPayload && !hasPreviewIssues && !isValidating {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        runApply()
                    } label: {
                        Text("APPLY")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryStepButton(disabled: false))
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(Color.black.opacity(0.15))
        }
    }

    private var hasPreviewIssues: Bool {
        switch tab {
        case .stock:
            return !stockLocalErrors.isEmpty || !stockServerErrors.isEmpty
        case .products:
            return !productsLocalErrors.isEmpty || !productsServerErrors.isEmpty
        }
    }

    private var hasPreviewPayload: Bool {
        switch tab {
        case .stock:    return stockPendingPayload != nil
        case .products: return productsPendingPayload != nil
        }
    }

    /// Unified row representation for the preview error list, abstracted
    /// across the two error DTO shapes. Both DTOs share the same fields
    /// — this is just a thin adapter so the view code can render them in
    /// one ForEach.
    private struct ErrorRow: Identifiable, Hashable {
        let id: String
        let scope: String
        let field: String
        let reason: String
    }

    private var previewErrorRows: [ErrorRow] {
        switch tab {
        case .stock:
            return (stockLocalErrors + stockServerErrors).map {
                ErrorRow(id: $0.id, scope: $0.scope, field: $0.field, reason: $0.reason)
            }
        case .products:
            return (productsLocalErrors + productsServerErrors).map {
                ErrorRow(id: $0.id, scope: $0.scope, field: $0.field, reason: $0.reason)
            }
        }
    }

    @ViewBuilder
    private var previewSummaryCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            switch tab {
            case .stock:
                if let p = stockPendingPayload {
                    summaryRow(label: "FAMILIES", value: "\(p.families.count)")
                    summaryRow(label: "VARIANTS", value: "\(p.variants.count)")
                }
            case .products:
                if let p = productsPendingPayload {
                    summaryRow(label: "PRODUCTS", value: "\(p.products.count)")
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.sectionLabel)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    private func errorRow(_ err: ErrorRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(err.scope.uppercased())
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                Text("·")
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(err.field.uppercased())
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            Text(err.reason)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.errorStatus)
                .frame(width: 2),
            alignment: .leading
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Step 3: apply

    private var applyStep: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            if isApplying {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(OPSStyle.Colors.primaryAccent)
                Text("// APPLYING")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else if applySucceeded {
                Image(OPSStyle.Icons.dealWon)
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(OPSStyle.Colors.successStatus)
                Text("// IMPORTED")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                applySuccessTotalsLabel
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Text("DONE")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(PrimaryStepButton(disabled: false))
                .padding(.top, OPSStyle.Layout.spacing3)
            } else if let err = applyError {
                Image(OPSStyle.Icons.alert)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                Text("// IMPORT FAILED")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(err)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Button("BACK") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        applyError = nil
                        step = .preview
                    }
                    .buttonStyle(SecondaryStepButton())

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        runApply()
                    } label: {
                        Text("RETRY")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryStepButton(disabled: false))
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing3)
    }

    private var applySucceeded: Bool { activeApplySucceeded }

    @ViewBuilder
    private var applySuccessTotalsLabel: some View {
        switch tab {
        case .stock:
            if let totals = stockApplyResult?.totals {
                Text("\(totals.families) families  ·  \(totals.variants) variants")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        case .products:
            if let totals = productsApplyResult?.totals {
                Text("\(totals.products) product\(totals.products == 1 ? "" : "s")")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }

    // MARK: - File picking (shared)

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        parseError = nil
        switch result {
        case .failure(let err):
            parseError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            // The picker hands back a security-scoped URL — wrap reads
            // accordingly so we don't get a "couldn't read file" error
            // on the second tap.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) ??
                                 String(data: data, encoding: .ascii) else {
                    parseError = "Could not decode file as UTF-8 or ASCII text."
                    return
                }
                let parsed = try CSVParser.parse(text)
                self.parsed = parsed
                self.pickedFileName = url.lastPathComponent
                switch tab {
                case .stock:
                    self.stockMapping = CatalogImportColumnMapping.suggest(from: parsed.headers)
                case .products:
                    self.productsMapping = ProductsImportColumnMapping.suggest(from: parsed.headers)
                }
                step = .map
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch let e as CSVParseError {
                parseError = e.errorDescription ?? "Failed to parse CSV."
            } catch {
                parseError = error.localizedDescription
            }
        }
    }

    // MARK: - Dry-run dispatcher

    private func runDryRun() {
        switch tab {
        case .stock:    runStockDryRun()
        case .products: runProductsDryRun()
        }
    }

    private func runStockDryRun() {
        guard let parsed = parsed else { return }
        stockLocalErrors = []
        stockServerErrors = []
        stockPendingPayload = nil
        step = .preview
        isValidating = true

        let mapResult = CatalogCSVMapper.map(
            rows: parsed.rows,
            lineNumbers: parsed.lineNumbers,
            mapping: stockMapping,
            categories: companyCategoryTuples,
            units: companyUnitTuples
        )
        if !mapResult.errors.isEmpty {
            stockLocalErrors = mapResult.errors
            isValidating = false
            return
        }
        guard let payload = mapResult.payload else {
            isValidating = false
            stockLocalErrors = [.mapping(rowIndex: -1, field: "payload",
                                        reason: "Mapper produced no payload.")]
            return
        }
        stockPendingPayload = payload

        Task { await performStockValidate(payload) }
    }

    private func runProductsDryRun() {
        guard let parsed = parsed else { return }
        productsLocalErrors = []
        productsServerErrors = []
        productsPendingPayload = nil
        step = .preview
        isValidating = true

        let mapResult = ProductsCSVMapper.map(
            rows: parsed.rows,
            lineNumbers: parsed.lineNumbers,
            mapping: productsMapping,
            categories: companyCategoryTuples,
            units: companyUnitTuples
        )
        if !mapResult.errors.isEmpty {
            productsLocalErrors = mapResult.errors
            isValidating = false
            return
        }
        guard let payload = mapResult.payload else {
            isValidating = false
            productsLocalErrors = [.mapping(rowIndex: -1, field: "payload",
                                            reason: "Mapper produced no payload.")]
            return
        }
        productsPendingPayload = payload

        Task { await performProductsValidate(payload) }
    }

    @MainActor
    private func performStockValidate(_ payload: CatalogImportPayload) async {
        defer { isValidating = false }
        guard !companyId.isEmpty else {
            stockServerErrors = [CatalogImportError(scope: "payload", rowIndex: -1,
                                                    field: "company", reason: "No active company.")]
            return
        }
        let repo = CatalogImportRepository(companyId: companyId)
        do {
            let result = try await repo.validate(payload)
            if !result.success {
                stockServerErrors = result.errors ?? []
            }
        } catch {
            stockServerErrors = [CatalogImportError(scope: "payload", rowIndex: -1,
                                                    field: "network", reason: error.localizedDescription)]
        }
    }

    @MainActor
    private func performProductsValidate(_ payload: ProductsImportPayload) async {
        defer { isValidating = false }
        guard !companyId.isEmpty else {
            productsServerErrors = [ProductsImportError(scope: "payload", rowIndex: -1,
                                                        field: "company", reason: "No active company.")]
            return
        }
        let repo = ProductsImportRepository(companyId: companyId)
        do {
            let result = try await repo.validate(payload)
            if !result.success {
                productsServerErrors = result.errors ?? []
            }
        } catch {
            productsServerErrors = [ProductsImportError(scope: "payload", rowIndex: -1,
                                                        field: "network", reason: error.localizedDescription)]
        }
    }

    // MARK: - Apply dispatcher

    private func runApply() {
        switch tab {
        case .stock:    runStockApply()
        case .products: runProductsApply()
        }
    }

    private func runStockApply() {
        guard let payload = stockPendingPayload else { return }
        stockApplyResult = nil
        applyError = nil
        step = .apply
        isApplying = true
        Task { await performStockApply(payload) }
    }

    private func runProductsApply() {
        guard let payload = productsPendingPayload else { return }
        productsApplyResult = nil
        applyError = nil
        step = .apply
        isApplying = true
        Task { await performProductsApply(payload) }
    }

    @MainActor
    private func performStockApply(_ payload: CatalogImportPayload) async {
        defer { isApplying = false }
        guard !companyId.isEmpty else {
            applyError = "No active company."
            return
        }
        let repo = CatalogImportRepository(companyId: companyId)
        do {
            let result = try await repo.apply(payload)
            if result.success {
                stockApplyResult = result
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("CatalogImportApplied"),
                    object: nil,
                    userInfo: [
                        "families": result.totals?.families ?? 0,
                        "variants": result.totals?.variants ?? 0
                    ]
                )
            } else {
                let issues = (result.errors ?? []).prefix(3).map(\.reason).joined(separator: " · ")
                applyError = issues.isEmpty ? "Server rejected the import." : issues
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        } catch {
            applyError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func performProductsApply(_ payload: ProductsImportPayload) async {
        defer { isApplying = false }
        guard !companyId.isEmpty else {
            applyError = "No active company."
            return
        }
        let repo = ProductsImportRepository(companyId: companyId)
        do {
            let result = try await repo.apply(payload)
            if result.success {
                productsApplyResult = result
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("ProductsImportApplied"),
                    object: nil,
                    userInfo: [
                        "products": result.totals?.products ?? 0
                    ]
                )
            } else {
                let issues = (result.errors ?? []).prefix(3).map(\.reason).joined(separator: " · ")
                applyError = issues.isEmpty ? "Server rejected the import." : issues
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        } catch {
            applyError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Button styles

private struct PrimaryStepButton: ButtonStyle {
    let disabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.button)
            .foregroundColor(OPSStyle.Colors.buttonText)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: 44)
            .background(
                disabled
                    ? OPSStyle.Colors.primaryAccent.opacity(0.4)
                    : OPSStyle.Colors.primaryAccent
            )
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.faster, value: configuration.isPressed)
    }
}

private struct SecondaryStepButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.button)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: 44)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.buttonBorder, lineWidth: 1)
            )
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.faster, value: configuration.isPressed)
    }
}
