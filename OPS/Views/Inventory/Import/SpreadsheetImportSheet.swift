//
//  SpreadsheetImportSheet.swift
//  OPS
//
//  Main coordinator for importing inventory from spreadsheets
//  Tactical minimalist design
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SpreadsheetImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    // Import state
    @State private var importStep: ImportStep = .selectFile
    @State private var spreadsheetData: SpreadsheetData?
    @State private var processedData: SpreadsheetData? // After orientation transform
    @State private var columnMappings: [ColumnMapping] = []
    @State private var parsedItems: [ParsedInventoryItem] = []
    @State private var selectedItemIds: Set<UUID> = []

    // Configuration state
    @State private var dataOrientation: DataOrientation = .rowsAreItems
    @State private var importMode: ImportMode = .multipleItems

    // UI state
    @State private var isShowingFilePicker = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var importResult: ImportResult?
    @State private var currentImportIndex: Int = 0

    // Existing inventory for duplicate detection
    @Query private var existingItems: [InventoryItem]
    @Query private var existingTags: [InventoryTag]

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyItems: [InventoryItem] {
        existingItems.filter { $0.companyId == companyId }
    }

    private var companyTags: [InventoryTag] {
        existingTags.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }

    enum ImportStep {
        case selectFile
        case configure
        case mapColumns
        case preview
        case importing
        case complete
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: titleForStep,
                    onBackTapped: handleBack
                )

                // Progress indicator
                importProgressBar
                    .padding(.top, OPSStyle.Layout.spacing2)

                // Content based on step
                switch importStep {
                case .selectFile:
                    fileSelectionView
                case .configure:
                    if let data = spreadsheetData {
                        ImportConfigView(
                            spreadsheetData: data,
                            orientation: $dataOrientation,
                            importMode: $importMode,
                            onContinue: processConfiguration
                        )
                    }
                case .mapColumns:
                    if let data = processedData {
                        ColumnMappingView(
                            spreadsheetData: data,
                            mappings: $columnMappings,
                            onContinue: processMappings
                        )
                    }
                case .preview:
                    ImportPreviewView(
                        items: $parsedItems,
                        selectedItemIds: $selectedItemIds,
                        onImport: startImport
                    )
                case .importing:
                    importingView
                case .complete:
                    importCompleteView
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: supportedFileTypes,
            onCompletion: handleFileSelection
        )
        .interactiveDismissDisabled(importStep != .selectFile && importStep != .complete)
    }

    // MARK: - Computed Properties

    private var titleForStep: String {
        switch importStep {
        case .selectFile: return "Import"
        case .configure: return "Configure"
        case .mapColumns: return "Map Fields"
        case .preview: return "Preview"
        case .importing: return "Importing"
        case .complete: return "Complete"
        }
    }

    private var stepIndex: Int {
        switch importStep {
        case .selectFile: return 0
        case .configure: return 1
        case .mapColumns: return 2
        case .preview: return 3
        case .importing, .complete: return 4
        }
    }

    private var supportedFileTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText]
        if let xlsx = UTType(filenameExtension: "xlsx") {
            types.append(xlsx)
        }
        return types
    }

    // MARK: - Progress Bar

    private var importProgressBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(index <= stepIndex ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder)
                    .frame(height: 3)
                    .cornerRadius(1.5)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - File Selection View

    private var fileSelectionView: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()

            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text("IMPORT INVENTORY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Select a CSV or Excel file")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Button(action: { isShowingFilePicker = true }) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                    Text("SELECT FILE")
                }
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(.black)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
                .padding(.vertical, 14)
                .background(Color.white)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

            if isProcessing {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ProgressView()
                        .tint(OPSStyle.Colors.primaryText)
                    Text("Reading file...")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.top, OPSStyle.Layout.spacing2)
            }

            if let error = errorMessage {
                Text(error)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .padding(.top, OPSStyle.Layout.spacing2)
            }

            Spacer()

            // Supported formats info
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("SUPPORTED:")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text("CSV, XLSX")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
    }

    // MARK: - Importing View

    private var importingView: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()

            ProgressView()
                .scaleEffect(1.2)
                .tint(OPSStyle.Colors.primaryText)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text("IMPORTING")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("\(currentImportIndex) of \(selectedItemIds.count)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(OPSStyle.Colors.primaryText)
                        .frame(width: geometry.size.width * progressFraction, height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, OPSStyle.Layout.spacing5)

            Spacer()
        }
    }

    private var progressFraction: CGFloat {
        guard selectedItemIds.count > 0 else { return 0 }
        return CGFloat(currentImportIndex) / CGFloat(selectedItemIds.count)
    }

    // MARK: - Import Complete View

    private var importCompleteView: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()

            if let result = importResult {
                Image(systemName: result.errors == 0 ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundColor(result.errors == 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus)

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("IMPORT COMPLETE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Results summary
                    VStack(spacing: OPSStyle.Layout.spacing1) {
                        if result.created > 0 {
                            resultRow(text: "\(result.created) imported", color: OPSStyle.Colors.successStatus)
                        }
                        if result.skipped > 0 {
                            resultRow(text: "\(result.skipped) skipped", color: OPSStyle.Colors.tertiaryText)
                        }
                        if result.errors > 0 {
                            resultRow(text: "\(result.errors) failed", color: OPSStyle.Colors.errorStatus)
                        }
                    }
                }

                // Error details
                if !result.errorMessages.isEmpty {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        ForEach(result.errorMessages.prefix(5), id: \.self) { message in
                            Text(message)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        if result.errorMessages.count > 5 {
                            Text("+ \(result.errorMessages.count - 5) more errors")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                Text("DONE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
    }

    private func resultRow(text: String, color: Color) -> some View {
        Text(text)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(color)
    }

    // MARK: - Actions

    private func handleBack() {
        switch importStep {
        case .selectFile:
            dismiss()
        case .configure:
            importStep = .selectFile
            spreadsheetData = nil
            processedData = nil
            dataOrientation = .rowsAreItems
            importMode = .multipleItems
        case .mapColumns:
            importStep = .configure
            columnMappings = []
            processedData = nil
        case .preview:
            // Variations mode skips mapColumns, so go back to configure
            if importMode == .variations {
                importStep = .configure
            } else {
                importStep = .mapColumns
            }
            parsedItems = []
            selectedItemIds = []
        case .importing, .complete:
            dismiss()
        }
    }

    private func handleFileSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            parseFile(url: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func parseFile(url: URL) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                let data = try await SpreadsheetParser.parse(url: url)

                await MainActor.run {
                    spreadsheetData = data
                    isProcessing = false
                    importStep = .configure
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func processConfiguration() {
        guard let data = spreadsheetData else { return }

        // Apply orientation transformation if needed
        var workingData = data
        if dataOrientation == .columnsAreItems {
            workingData = SpreadsheetParser.transpose(data)
        }
        processedData = workingData

        // For variations mode, skip column mapping and go straight to preview
        if importMode == .variations {
            processVariations()
            return
        }

        // Generate mappings based on import mode
        if importMode == .singleItem {
            columnMappings = SpreadsheetParser.suggestRowMappings(for: workingData)
        } else {
            columnMappings = SpreadsheetParser.suggestMappings(for: workingData)
        }

        importStep = .mapColumns
    }

    private func processVariations() {
        guard let data = processedData else { return }

        // Parse variations (grid format: rows = items, columns = variations)
        // Data has already been transposed if orientation is columnsAreItems
        var items = SpreadsheetParser.parseVariations(from: data, includeVariationInName: false)

        // Check for duplicates
        items = SpreadsheetParser.checkDuplicates(items, existingItems: companyItems)

        parsedItems = items

        // Select all valid, non-duplicate items by default
        selectedItemIds = Set(items.filter { $0.isValid && !$0.isDuplicate }.map { $0.id })

        importStep = .preview
    }

    private func processMappings() {
        guard let data = processedData else { return }

        // Check that name column is mapped
        let hasNameMapping = columnMappings.contains { $0.field == .name }
        guard hasNameMapping else {
            errorMessage = "Please map a field to 'Name'"
            return
        }

        // Parse items based on import mode
        var items: [ParsedInventoryItem]
        if importMode == .singleItem {
            items = SpreadsheetParser.parseSingleItem(from: data, using: columnMappings)
        } else {
            items = SpreadsheetParser.parseItems(from: data, using: columnMappings)
        }

        // Check for duplicates
        items = SpreadsheetParser.checkDuplicates(items, existingItems: companyItems)

        parsedItems = items

        // Select all valid, non-duplicate items by default
        selectedItemIds = Set(items.filter { $0.isValid && !$0.isDuplicate }.map { $0.id })

        importStep = .preview
    }

    private func startImport() {
        importStep = .importing
        currentImportIndex = 0

        Task {
            await performImport()
        }
    }

    private func performImport() async {
        var created = 0
        var errors = 0
        var errorMessages: [String] = []

        let itemsToImport = parsedItems.filter { selectedItemIds.contains($0.id) }
        let skipped = parsedItems.count - itemsToImport.count

        for (index, item) in itemsToImport.enumerated() {
            await MainActor.run {
                currentImportIndex = index + 1
            }

            do {
                // Find unit ID if unit name provided
                var unitId: String? = nil
                if let unitName = item.unitName {
                    // Query for matching unit
                    let descriptor = FetchDescriptor<InventoryUnit>(
                        predicate: #Predicate<InventoryUnit> { unit in
                            unit.companyId == companyId && unit.deletedAt == nil
                        }
                    )
                    if let units = try? modelContext.fetch(descriptor) {
                        unitId = units.first(where: {
                            $0.display.lowercased() == unitName.lowercased()
                        })?.id
                    }
                }

                let newItem = InventoryItem(
                    id: UUID().uuidString,
                    name: item.name,
                    quantity: item.quantity,
                    companyId: companyId,
                    unitId: unitId,
                    itemDescription: item.description,
                    sku: item.sku,
                    notes: item.notes
                )

                modelContext.insert(newItem)

                // Apply tags from spreadsheet
                for tagName in item.tags {
                    let trimmedTagName = tagName.trimmingCharacters(in: .whitespaces)
                    guard !trimmedTagName.isEmpty else { continue }

                    // Look for existing tag (case-insensitive)
                    if let existingTag = companyTags.first(where: {
                        $0.name.lowercased() == trimmedTagName.lowercased()
                    }) {
                        newItem.addTag(existingTag)
                    } else {
                        // Create new tag
                        let newTag = InventoryTag(
                            id: UUID().uuidString,
                            name: trimmedTagName,
                            companyId: companyId
                        )
                        newTag.needsSync = true
                        modelContext.insert(newTag)
                        newItem.addTag(newTag)

                        // Create tag in Bubble asynchronously
                        Task {
                            do {
                                let tagDTO = InventoryTagDTO(
                                    id: newTag.id,
                                    name: trimmedTagName,
                                    warningThreshold: nil,
                                    criticalThreshold: nil,
                                    company: companyId
                                )
                                let createdTag = try await dataController.apiService.createTag(tagDTO)
                                await MainActor.run {
                                    newTag.id = createdTag.id
                                    newTag.needsSync = false
                                    newTag.lastSyncedAt = Date()
                                }
                            } catch {
                                print("[IMPORT] Failed to create tag '\(trimmedTagName)': \(error)")
                            }
                        }
                    }
                }

                // Create via API
                let dto = InventoryItemDTO.from(newItem)
                let createdDTO = try await dataController.apiService.createInventoryItem(dto)

                await MainActor.run {
                    newItem.id = createdDTO.id
                    newItem.lastSyncedAt = Date()
                }

                created += 1
            } catch {
                errors += 1
                errorMessages.append("Row \(item.rowIndex): \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            try? modelContext.save()
            importResult = ImportResult(
                created: created,
                skipped: skipped,
                errors: errors,
                errorMessages: errorMessages
            )
            importStep = .complete

            if created > 0 {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
}

#Preview {
    SpreadsheetImportSheet()
        .environmentObject(DataController())
}
