//
//  ColumnMappingView.swift
//  OPS
//
//  Interactive column-to-field mapping for spreadsheet import
//  Tactical minimalist design
//

import SwiftUI

struct ColumnMappingView: View {
    let spreadsheetData: SpreadsheetData
    @Binding var mappings: [ColumnMapping]
    /// Existing company tags — shown as chips in the bulk-tag picker.
    let availableTags: [InventoryTag]
    /// Tags the user wants applied to EVERY imported item (bug f60d9de8).
    /// Merged with per-row column-mapped tags in SpreadsheetImportSheet
    /// during performImport().
    @Binding var bulkTagNames: Set<String>
    let onContinue: () -> Void

    @State private var errorMessage: String?
    @State private var newTagDraft: String = ""
    @FocusState private var newTagFocused: Bool

    private var hasNameMapping: Bool {
        mappings.contains { $0.field == .name }
    }

    /// Existing tags the user hasn't picked yet — shown as chips to toggle.
    private var unpickedAvailableTags: [InventoryTag] {
        let pickedLower = Set(bulkTagNames.map { $0.lowercased() })
        return availableTags
            .filter { !pickedLower.contains($0.name.lowercased()) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Info banner
            infoBanner

            // Mappings list + bulk-tag picker
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach($mappings) { $mapping in
                        columnMappingRow(mapping: $mapping)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing2)

                bulkTagsSection
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, 120)
            }

            Spacer()

            // Continue button
            continueButton
        }
    }

    // MARK: - Info Banner

    private var infoBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "info.circle")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("Map each column to an inventory field. Name is required.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 10)
        .background(OPSStyle.Colors.background)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Column Mapping Row

    private func columnMappingRow(mapping: Binding<ColumnMapping>) -> some View {
        let isNameField = mapping.wrappedValue.field == .name
        let isSkipped = mapping.wrappedValue.field == .skip

        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Header and sample
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mapping.wrappedValue.headerName)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    if !mapping.wrappedValue.sampleValue.isEmpty {
                        Text("e.g. \"\(mapping.wrappedValue.sampleValue)\"")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Required indicator for name
                if isNameField {
                    Text("REQUIRED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.successStatus)
                }
            }

            // Field selector
            Menu {
                ForEach(InventoryImportField.allCases) { field in
                    Button(action: {
                        mapping.wrappedValue.field = field
                    }) {
                        HStack {
                            Text(field.rawValue)
                            Spacer()
                            if mapping.wrappedValue.field == field {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(mapping.wrappedValue.field.rawValue)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(isSkipped ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, 10)
                .background(OPSStyle.Colors.background)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(isNameField ? OPSStyle.Colors.successStatus.opacity(0.5) : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Bulk Tags Section

    /// Lets the user tag every imported item without needing a tags column in
    /// the spreadsheet. Existing tags render as chips that toggle on tap; new
    /// tag names can be typed into the inline field and are created during
    /// import (SpreadsheetImportSheet.performImport handles the lookup-or-create).
    private var bulkTagsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("[ APPLY TAGS TO ALL ITEMS ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1.2)
            }

            Text("Everything you import gets these tags in addition to anything mapped from a Tags column.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Currently-selected tags
            if !bulkTagNames.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(bulkTagNames).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { name in
                        selectedTagChip(name)
                    }
                }
            }

            // New-tag input
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField("New tag…", text: $newTagDraft)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .focused($newTagFocused)
                    .onSubmit { addDraftTag() }
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.background)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(newTagFocused ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )

                Button(action: addDraftTag) {
                    Text("ADD")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(canAddDraftTag ? .black : OPSStyle.Colors.tertiaryText)
                        .tracking(1.1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(canAddDraftTag ? Color.white : OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(canAddDraftTag ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(!canAddDraftTag)
            }

            // Existing tags the user can one-tap add
            if !unpickedAvailableTags.isEmpty {
                Text("TAP TO ADD EXISTING TAG")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .tracking(1.0)
                    .padding(.top, OPSStyle.Layout.spacing1)

                FlowLayout(spacing: 6) {
                    ForEach(unpickedAvailableTags) { tag in
                        existingTagChip(tag)
                    }
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1),
            alignment: .top
        )
    }

    private var canAddDraftTag: Bool {
        let trimmed = newTagDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return !bulkTagNames.contains(where: { $0.lowercased() == trimmed.lowercased() })
    }

    private func addDraftTag() {
        let trimmed = newTagDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Dedupe case-insensitively — keep the first casing the user typed.
        let lower = trimmed.lowercased()
        if bulkTagNames.contains(where: { $0.lowercased() == lower }) {
            newTagDraft = ""
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        bulkTagNames.insert(trimmed)
        newTagDraft = ""
    }

    private func selectedTagChip(_ name: String) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bulkTagNames.remove(name)
        }) {
            HStack(spacing: 5) {
                Text(name)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.modalRadius)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(name) from bulk tags")
    }

    private func existingTagChip(_ tag: InventoryTag) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            bulkTagNames.insert(tag.name)
        }) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(tag.name)
                    .font(OPSStyle.Typography.smallCaption)
            }
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(OPSStyle.Colors.background)
            .cornerRadius(OPSStyle.Layout.modalRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.modalRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(tag.name) to bulk tags")
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            if let error = errorMessage {
                Text(error)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
            }

            if !hasNameMapping {
                Text("Please map a column to 'Name' to continue")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            Button(action: {
                if hasNameMapping {
                    onContinue()
                } else {
                    errorMessage = "Name mapping is required"
                }
            }) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("CONTINUE")
                    Image(systemName: "arrow.right")
                }
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(hasNameMapping ? .black : OPSStyle.Colors.tertiaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(hasNameMapping ? Color.white : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(hasNameMapping ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .disabled(!hasNameMapping)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background)
    }
}

#Preview {
    let sampleData = SpreadsheetData(
        headers: ["Item Name", "Qty", "Description", "SKU"],
        rows: [
            SpreadsheetRow(values: ["2x4 Lumber", "100", "Standard pine 2x4", "LUM-2X4-8"]),
            SpreadsheetRow(values: ["Drywall Sheet", "50", "4x8 drywall", "DRY-4X8"])
        ],
        sourceFileName: "inventory.csv"
    )

    let mappings = SpreadsheetParser.suggestMappings(for: sampleData)

    return ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        ColumnMappingView(
            spreadsheetData: sampleData,
            mappings: .constant(mappings),
            availableTags: [],
            bulkTagNames: .constant([]),
            onContinue: { }
        )
    }
}
