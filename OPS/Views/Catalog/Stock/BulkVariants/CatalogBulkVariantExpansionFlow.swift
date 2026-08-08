//
//  CatalogBulkVariantExpansionFlow.swift
//  OPS
//
//  Full-screen FAMILIES → CHANGE → REVIEW workflow for expanding one real
//  catalog option axis across many existing stock families.
//

import SwiftData
import SwiftUI

struct CatalogBulkVariantExpansionFlow: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allItems: [CatalogItem]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allOptions: [CatalogOption]
    @Query private var allValues: [CatalogOptionValue]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allJoins: [CatalogVariantOptionValue]

    @StateObject private var model: CatalogBulkVariantExpansionModel
    @State private var showExitChoices = false

    private let companyId: String

    init(companyId: String) {
        self.companyId = companyId
        _model = StateObject(wrappedValue: CatalogBulkVariantExpansionModel(companyId: companyId))
    }

    var body: some View {
        let state = catalogState
        let preview = makePreview(from: state.snapshots)

        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            if let completion = model.completion {
                completionView(completion)
            } else if permissionStore.can("catalog.manage") {
                flowContent(state: state, preview: preview)
            } else {
                permissionGate
            }
        }
        .trackScreen("Catalog.BulkAddVariants")
        .confirmationDialog(
            "Exit bulk variant setup?",
            isPresented: $showExitChoices,
            titleVisibility: .visible
        ) {
            Button("KEEP DRAFT") { dismiss() }
            Button("DISCARD DRAFT", role: .destructive) {
                model.discardDraft()
                dismiss()
            }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("Your selections and values can stay ready for later.")
        }
        .onAppear {
            model.removeUnavailableSelections(validFamilyIds: state.selectableFamilyIds)
        }
        .onChange(of: state.selectableFamilyIds) { _, validIds in
            model.removeUnavailableSelections(validFamilyIds: validIds)
        }
    }

    private func flowContent(
        state: CatalogBulkVariantCatalogState,
        preview: CatalogBulkVariantExpansionPreview
    ) -> some View {
        VStack(spacing: 0) {
            header
            stageHeader
            if !dataController.isConnected {
                offlineBanner
            }

            ScrollView {
                Group {
                    switch model.stage {
                    case .families:
                        CatalogBulkVariantFamilyStep(
                            model: model,
                            families: state.rows,
                            selectableFamilyIds: state.selectableFamilyIds
                        )
                    case .change:
                        CatalogBulkVariantChangeStep(
                            model: model,
                            optionSuggestions: optionSuggestions(from: state.snapshots),
                            existingValueSuggestions: existingValueSuggestions(from: state.snapshots)
                        )
                    case .review:
                        CatalogBulkVariantReviewStep(
                            model: model,
                            preview: preview,
                            isOnline: dataController.isConnected
                        )
                    }
                }
                .id(model.stage)
                .transition(OPSStyle.Animation.reduceMotion ? .opacity : stageTransition)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing4)
                .padding(.bottom, OPSStyle.Layout.spacing4)
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(OPSStyle.Animation.page, value: model.stage)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(preview: preview)
        }
    }

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// CATALOG")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("ADD VARIANTS")
                    .font(OPSStyle.Typography.screenTitle)
                    .foregroundColor(OPSStyle.Colors.text)
            }
            Spacer()
            Button {
                exitFlow()
            } label: {
                Image(systemName: OPSStyle.Icons.close)
            }
            .opsIconButtonStyle()
            .disabled(model.isSaving)
            .accessibilityLabel("Exit bulk variant setup")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    private var stageHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(Array(CatalogBulkVariantFlowStage.allCases.enumerated()), id: \.element.id) { index, stage in
                let currentIndex = CatalogBulkVariantFlowStage.allCases.firstIndex(of: model.stage) ?? 0
                let stageReached = index <= currentIndex
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("\(index + 1)")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(stageReached ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                        .frame(
                            width: OPSStyle.Layout.spacing4,
                            height: OPSStyle.Layout.spacing4
                        )
                        .background(stage == model.stage ? OPSStyle.Colors.surfaceSelected : OPSStyle.Colors.surfaceInput)
                        .clipShape(Circle())
                    Text(stage.label)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(stageReached ? OPSStyle.Colors.text2 : OPSStyle.Colors.textMute)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1), \(stage.label.lowercased())")
                .accessibilityAddTraits(stage == model.stage ? .isSelected : [])
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: OPSStyle.Layout.Border.standard)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.connectivityUnavailable)
                .foregroundColor(OPSStyle.Colors.tanTextM)
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// OFFLINE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                Text("Connect to add these variants. Your draft stays ready.")
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.text2)
            }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.tanFillM)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OPSStyle.Colors.tanLineM)
                .frame(height: OPSStyle.Layout.Border.standard)
        }
        .accessibilityElement(children: .combine)
    }

    private func bottomBar(preview: CatalogBulkVariantExpansionPreview) -> some View {
        OPSFloatingButtonBar(
            horizontalPadding: OPSStyle.Layout.spacing3,
            verticalPadding: OPSStyle.Layout.spacing2_5
        ) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                if model.stage != .families {
                    Button("BACK") {
                        model.goBack()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .opsSecondaryButtonStyle()
                    .disabled(model.isSaving)
                }

                switch model.stage {
                case .families:
                    Button("CONTINUE") {
                        model.advance()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .opsPrimaryButtonStyle(isDisabled: !model.canAdvance)
                    .disabled(!model.canAdvance)
                case .change:
                    Button("REVIEW") {
                        model.advance()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .opsPrimaryButtonStyle(isDisabled: !model.canAdvance)
                    .disabled(!model.canAdvance)
                case .review:
                    let canApply = model.canApply(
                        isOnline: dataController.isConnected,
                        canManage: permissionStore.can("catalog.manage"),
                        previewCanApply: preview.canApply
                    )
                    Button {
                        apply(preview)
                    } label: {
                        if model.isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.text3))
                                .accessibilityLabel("Adding variants")
                        } else {
                            Text("ADD VARIANTS · \(preview.newVariantCount)")
                        }
                    }
                    .opsPrimaryButtonStyle(isDisabled: !canApply)
                    .disabled(!canApply)
                }
            }
        }
    }

    private var permissionGate: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Text("// ACCESS RESTRICTED")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.text3)
            Text("Catalog management access is required.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text2)
                .multilineTextAlignment(.center)
            Button("CLOSE") { dismiss() }
                .opsPrimaryButtonStyle()
                .padding(.horizontal, OPSStyle.Layout.spacing4)
            Spacer()
        }
    }

    private func completionView(_ completion: CatalogBulkVariantCompletion) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()
            Image(systemName: OPSStyle.Icons.checkmarkCircle)
                .font(.system(size: OPSStyle.Layout.IconSize.xl, weight: .light))
                .foregroundColor(OPSStyle.Colors.oliveTextM)
                .accessibilityHidden(true)
            Text("VARIANTS ADDED")
                .font(OPSStyle.Typography.screenTitle)
                .foregroundColor(OPSStyle.Colors.text)
                .multilineTextAlignment(.center)
            Text("\(completion.newVariantCount) new variants across \(completion.familyCount) families. Existing stock and SKUs are unchanged.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
            Spacer()
            OPSFloatingButtonBar(
                horizontalPadding: OPSStyle.Layout.spacing3,
                verticalPadding: OPSStyle.Layout.spacing2_5
            ) {
                Button("DONE") { dismiss() }
                    .opsPrimaryButtonStyle()
            }
        }
    }

    private func exitFlow() {
        guard model.hasMeaningfulDraft else {
            dismiss()
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showExitChoices = true
    }

    private func apply(_ preview: CatalogBulkVariantExpansionPreview) {
        guard model.canApply(
            isOnline: dataController.isConnected,
            canManage: permissionStore.can("catalog.manage"),
            previewCanApply: preview.canApply
        ) else { return }

        model.beginApply()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let service = CatalogBulkVariantExpansionService(
            companyId: companyId,
            modelContext: modelContext,
            requestCatalogResync: {
                Task { @MainActor in
                    await dataController.syncEngine.triggerSync()
                }
            }
        )

        Task { @MainActor in
            do {
                let outcome = try await service.commit(
                    preview: preview,
                    idempotencyKey: model.idempotencyKey
                )
                switch outcome {
                case .committed(let response, _):
                    model.handleSuccess(
                        familyCount: response.familyCount,
                        newVariantCount: response.newVariantCount
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    await dataController.syncEngine.triggerSync()
                case .rejected(let code, let message):
                    let operatorMessage: String
                    switch code {
                    case "stale_catalog":
                        operatorMessage = "Catalog changed since this review. Check the refreshed variants before adding them."
                        await dataController.syncEngine.triggerSync()
                    case "permission_denied", "company_forbidden":
                        operatorMessage = "Catalog management access is required."
                    case "idempotency_conflict":
                        operatorMessage = "An earlier update was already recorded. Check the refreshed review before adding anything else."
                        await dataController.syncEngine.triggerSync()
                        model.renewIdempotencyKey()
                    default:
                        operatorMessage = message
                    }
                    model.handleRejection(code: code, message: operatorMessage)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            } catch {
                model.handleFailure(
                    message: "Couldn’t reach the catalog. Check your connection and try again."
                )
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private var catalogState: CatalogBulkVariantCatalogState {
        let items = allItems.filter {
            $0.companyId == companyId && $0.isActive && $0.deletedAt == nil
        }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        let itemIds = Set(items.map(\.id))
        let snapshots = CatalogBulkVariantSnapshotBuilder.makeFamilies(
            items: items,
            options: allOptions,
            values: allValues,
            variants: allVariants,
            joins: allJoins,
            selectedFamilyIds: itemIds
        )
        let snapshotsById = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let categoriesById = Dictionary(uniqueKeysWithValues: allCategories.filter {
            $0.companyId == companyId && $0.deletedAt == nil
        }.map { ($0.id, $0) })

        var selectableIds: Set<String> = []
        let rows = items.map { item -> CatalogBulkVariantFamilyRow in
            let snapshot = snapshotsById[item.id] ?? .init(id: item.id, name: item.name, options: [], variants: [])
            let issue = structuralIssue(for: snapshot)
            if issue == nil { selectableIds.insert(item.id) }
            let optionNames = snapshot.options.map(\.name)
            let axesText = optionNames.isEmpty ? "NO CURRENT OPTIONS" : optionNames.joined(separator: " · ")
            let categoryName = item.categoryId.flatMap { categoriesById[$0]?.name } ?? ""
            let searchParts = [item.name, categoryName]
                + snapshot.options.flatMap { option in [option.name] + option.values.map(\.value) }
            return CatalogBulkVariantFamilyRow(
                id: item.id,
                name: item.name,
                variantCount: snapshot.variants.count,
                axesText: axesText,
                searchText: searchParts.joined(separator: " "),
                isSelectable: issue == nil,
                issue: issue
            )
        }

        return .init(rows: rows, snapshots: snapshots, selectableFamilyIds: selectableIds)
    }

    private func structuralIssue(for family: CatalogBulkFamilySnapshot) -> String? {
        guard !family.variants.isEmpty else { return "No active variants to expand." }
        let probe = CatalogBulkVariantExpansionPlanner.makePreview(.init(
            axisName: "__OPS STRUCTURE CHECK__",
            existingValue: "__EXISTING__",
            newValues: ["__NEW__"],
            families: [family]
        ))
        return probe.canApply ? nil : probe.blockers.first?.message
    }

    private func makePreview(
        from snapshots: [CatalogBulkFamilySnapshot]
    ) -> CatalogBulkVariantExpansionPreview {
        let selected = snapshots.filter { model.selectedFamilyIds.contains($0.id) }
        return CatalogBulkVariantExpansionPlanner.makePreview(.init(
            axisName: model.axisName,
            existingValue: model.existingValue,
            newValues: model.newValues.map(\.text),
            families: selected
        ))
    }

    private func optionSuggestions(from snapshots: [CatalogBulkFamilySnapshot]) -> [String] {
        uniqueNames(
            snapshots
                .filter { model.selectedFamilyIds.contains($0.id) }
                .flatMap(\.options)
                .map(\.name)
        )
    }

    private func existingValueSuggestions(from snapshots: [CatalogBulkFamilySnapshot]) -> [String] {
        let axis = normalized(model.axisName)
        guard !axis.isEmpty else { return [] }
        let values = snapshots
            .filter { model.selectedFamilyIds.contains($0.id) }
            .flatMap(\.options)
            .filter { normalized($0.name) == axis }
            .flatMap(\.values)
            .map(\.value)
        return uniqueNames(values)
    }

    private func uniqueNames(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.filter {
            seen.insert(normalized($0)).inserted
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var stageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }
}

private struct CatalogBulkVariantCatalogState {
    let rows: [CatalogBulkVariantFamilyRow]
    let snapshots: [CatalogBulkFamilySnapshot]
    let selectableFamilyIds: Set<String>
}
