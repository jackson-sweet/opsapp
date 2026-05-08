//
//  CatalogImportSheet.swift
//  OPS
//
//  Multi-step CSV import for catalog families + variants. Replaces the
//  prior `CatalogImportStub`. Four steps stitched together by a single
//  `Step` enum: PICK → MAP → PREVIEW → APPLY.
//
//  Atomic by construction — the preview step calls
//  `catalog_import_validate` (no writes). Only on user confirm does
//  `catalog_import_apply` run, and that RPC is fully transactional, so
//  the user never observes a half-imported state. RETRY is safe — a
//  re-applied payload either lands or re-fails the same way.
//
//  Layout matches `QuickAddProductSheet`: backgroundGradient,
//  NavigationStack, large detent. Top progress strip walks the four
//  steps as a tactical chip strip.
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

    // MARK: - File / parse state

    @State private var isShowingFilePicker: Bool = false
    @State private var pickedFileName: String? = nil
    @State private var parsed: CSVParseResult? = nil
    @State private var parseError: String? = nil

    // MARK: - Mapping state

    @State private var mapping = CatalogImportColumnMapping()

    // MARK: - Preview / apply state

    @State private var localErrors: [CatalogImportError] = []
    @State private var serverErrors: [CatalogImportError] = []
    @State private var pendingPayload: CatalogImportPayload? = nil
    @State private var pendingTotalsFamilies: Int = 0
    @State private var pendingTotalsVariants: Int = 0

    @State private var isValidating: Bool = false
    @State private var isApplying: Bool = false

    @State private var applyResult: CatalogImportResult? = nil
    @State private var applyError: String? = nil

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

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
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

    // MARK: - Header strip

    private var closeLabel: String {
        step == .apply && applyResult?.success == true ? "Done" : "Cancel"
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
                    Image(systemName: "chevron.right")
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

    // MARK: - Step 0: pick

    private var pickStep: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            VStack(spacing: OPSStyle.Layout.spacing1) {
                Text("// SELECT CSV")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("One row per variant. Header row required.")
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

                    mapRow(label: "FAMILY NAME *", binding: bindingFor(\.familyName))
                    mapRow(label: "QUANTITY *", binding: bindingFor(\.quantity))
                    Divider().background(OPSStyle.Colors.separator)

                    Text("// FAMILY-LEVEL")
                        .font(OPSStyle.Typography.sectionLabel)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    mapRow(label: "DESCRIPTION", binding: bindingFor(\.familyDescription))
                    mapRow(label: "CATEGORY", binding: bindingFor(\.category))
                    mapRow(label: "DEFAULT UNIT", binding: bindingFor(\.defaultUnit))
                    mapRow(label: "DEFAULT PRICE", binding: bindingFor(\.defaultPrice))
                    mapRow(label: "DEFAULT UNIT COST", binding: bindingFor(\.defaultUnitCost))

                    Divider().background(OPSStyle.Colors.separator)
                    Text("// VARIANT-LEVEL")
                        .font(OPSStyle.Typography.sectionLabel)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    mapRow(label: "SKU", binding: bindingFor(\.sku))
                    mapRow(label: "VARIANT UNIT", binding: bindingFor(\.variantUnit))
                    mapRow(label: "PRICE OVERRIDE", binding: bindingFor(\.priceOverride))
                    mapRow(label: "UNIT COST OVERRIDE", binding: bindingFor(\.unitCostOverride))
                    mapRow(label: "WARNING THRESHOLD", binding: bindingFor(\.warningThreshold))
                    mapRow(label: "CRITICAL THRESHOLD", binding: bindingFor(\.criticalThreshold))
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
                .buttonStyle(PrimaryStepButton(disabled: !mapping.isReadyToMap))
                .disabled(!mapping.isReadyToMap)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(Color.black.opacity(0.15))
        }
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
                    Image(systemName: "chevron.down")
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

    private func bindingFor(_ keyPath: WritableKeyPath<CatalogImportColumnMapping, String?>) -> Binding<String?> {
        Binding(
            get: { mapping[keyPath: keyPath] },
            set: { mapping[keyPath: keyPath] = $0 }
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
                    } else if !localErrors.isEmpty || !serverErrors.isEmpty {
                        let combined = localErrors + serverErrors
                        Text("// \(combined.count) ISSUE\(combined.count == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.panelTitle)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                        Text("Fix the CSV (or remap columns) and try again. Nothing was imported.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            ForEach(combined) { err in
                                errorRow(err)
                            }
                        }
                    } else if let payload = pendingPayload {
                        Text("// READY")
                            .font(OPSStyle.Typography.panelTitle)
                            .foregroundColor(OPSStyle.Colors.successStatus)
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            HStack {
                                Text("FAMILIES")
                                    .font(OPSStyle.Typography.sectionLabel)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                Spacer()
                                Text("\(payload.families.count)")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            HStack {
                                Text("VARIANTS")
                                    .font(OPSStyle.Typography.sectionLabel)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                Spacer()
                                Text("\(payload.variants.count)")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }
                        .padding(OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
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

                if pendingPayload != nil && localErrors.isEmpty && serverErrors.isEmpty && !isValidating {
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

    private func errorRow(_ err: CatalogImportError) -> some View {
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
            } else if let result = applyResult, result.success {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(OPSStyle.Colors.successStatus)
                Text("// IMPORTED")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                if let totals = result.totals {
                    Text("\(totals.families) families  ·  \(totals.variants) variants")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
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
                Image(systemName: "exclamationmark.triangle")
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

    // MARK: - Actions

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
                self.mapping = CatalogImportColumnMapping.suggest(from: parsed.headers)
                step = .map
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch let e as CSVParseError {
                parseError = e.errorDescription ?? "Failed to parse CSV."
            } catch {
                parseError = error.localizedDescription
            }
        }
    }

    private func runDryRun() {
        guard let parsed = parsed else { return }
        localErrors = []
        serverErrors = []
        pendingPayload = nil
        step = .preview
        isValidating = true

        let mapResult = CatalogCSVMapper.map(
            rows: parsed.rows,
            lineNumbers: parsed.lineNumbers,
            mapping: mapping,
            categories: companyCategoryTuples,
            units: companyUnitTuples
        )
        if !mapResult.errors.isEmpty {
            localErrors = mapResult.errors
            isValidating = false
            return
        }
        guard let payload = mapResult.payload else {
            isValidating = false
            localErrors = [.mapping(rowIndex: -1, field: "payload", reason: "Mapper produced no payload.")]
            return
        }
        pendingPayload = payload
        pendingTotalsFamilies = payload.families.count
        pendingTotalsVariants = payload.variants.count

        Task {
            await performValidate(payload)
        }
    }

    @MainActor
    private func performValidate(_ payload: CatalogImportPayload) async {
        defer { isValidating = false }
        guard !companyId.isEmpty else {
            serverErrors = [CatalogImportError(scope: "payload", rowIndex: -1, field: "company", reason: "No active company.")]
            return
        }
        let repo = CatalogImportRepository(companyId: companyId)
        do {
            let result = try await repo.validate(payload)
            if !result.success {
                serverErrors = result.errors ?? []
            }
        } catch {
            serverErrors = [CatalogImportError(scope: "payload", rowIndex: -1, field: "network", reason: error.localizedDescription)]
        }
    }

    private func runApply() {
        guard let payload = pendingPayload else { return }
        applyResult = nil
        applyError = nil
        step = .apply
        isApplying = true
        Task {
            await performApply(payload)
        }
    }

    @MainActor
    private func performApply(_ payload: CatalogImportPayload) async {
        defer { isApplying = false }
        guard !companyId.isEmpty else {
            applyError = "No active company."
            return
        }
        let repo = CatalogImportRepository(companyId: companyId)
        do {
            let result = try await repo.apply(payload)
            if result.success {
                applyResult = result
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Trigger a catalog resync so the new rows show up in
                // Stock without a manual pull.
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
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
