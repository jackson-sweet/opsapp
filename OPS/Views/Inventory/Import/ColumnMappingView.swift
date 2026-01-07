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
    let onContinue: () -> Void

    @State private var errorMessage: String?

    private var hasNameMapping: Bool {
        mappings.contains { $0.field == .name }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Info banner
            infoBanner

            // Mappings list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach($mappings) { $mapping in
                        columnMappingRow(mapping: $mapping)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing2)
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
                .font(.system(size: 12))
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

        return VStack(alignment: .leading, spacing: 8) {
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
                        .font(.system(size: 10))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(OPSStyle.Colors.background)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isNameField ? OPSStyle.Colors.successStatus.opacity(0.5) : OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 12)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1),
            alignment: .bottom
        )
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
                        .stroke(hasNameMapping ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: 1)
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
            onContinue: { }
        )
    }
}
