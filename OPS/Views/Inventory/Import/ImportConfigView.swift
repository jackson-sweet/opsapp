//
//  ImportConfigView.swift
//  OPS
//
//  Configuration step for spreadsheet import - orientation and mode selection
//  Tactical minimalist design
//

import SwiftUI

enum DataOrientation: String, CaseIterable {
    case rowsAreItems = "rows"
    case columnsAreItems = "columns"

    var title: String {
        switch self {
        case .rowsAreItems: return "Rows"
        case .columnsAreItems: return "Columns"
        }
    }

    var description: String {
        switch self {
        case .rowsAreItems: return "Each row is a separate item"
        case .columnsAreItems: return "Each column is a separate item"
        }
    }

    var icon: String {
        switch self {
        case .rowsAreItems: return "arrow.down.square"
        case .columnsAreItems: return "arrow.right.square"
        }
    }
}

enum ImportMode: String, CaseIterable {
    case multipleItems = "multiple"
    case variations = "variations"
    case singleItem = "single"

    var title: String {
        switch self {
        case .multipleItems: return "Multiple Items"
        case .variations: return "Items with Variations"
        case .singleItem: return "Single Item"
        }
    }

    func description(for orientation: DataOrientation) -> String {
        switch self {
        case .multipleItems:
            switch orientation {
            case .rowsAreItems:
                return "Each row is a separate item with fields in columns"
            case .columnsAreItems:
                return "Each column is a separate item with fields in rows"
            }
        case .variations:
            switch orientation {
            case .rowsAreItems:
                return "Rows are items, columns are variations (e.g. colors, sizes)"
            case .columnsAreItems:
                return "Columns are items, rows are variations (e.g. colors, sizes)"
            }
        case .singleItem:
            return "Map fields for one item only"
        }
    }

    var icon: String {
        switch self {
        case .multipleItems: return "square.stack.3d.up"
        case .variations: return "square.grid.2x2"
        case .singleItem: return "square"
        }
    }
}

struct ImportConfigView: View {
    let spreadsheetData: SpreadsheetData
    @Binding var orientation: DataOrientation
    @Binding var importMode: ImportMode
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    // File info
                    fileInfoSection

                    // Orientation selection
                    orientationSection

                    // Import mode selection
                    importModeSection

                    Spacer()
                        .frame(height: 120)
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }

            // Continue button
            continueButton
        }
    }

    // MARK: - File Info Section

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("FILE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: 0) {
                infoRow(label: "Name", value: spreadsheetData.sourceFileName)
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: 1)
                infoRow(label: "Rows", value: "\(spreadsheetData.rowCount)")
                Rectangle()
                    .fill(OPSStyle.Colors.cardBorder)
                    .frame(height: 1)
                infoRow(label: "Columns", value: "\(spreadsheetData.columnCount)")
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 10)
    }

    // MARK: - Orientation Section

    private var orientationSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("DATA ORIENTATION")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            Text("How are items arranged in your spreadsheet?")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: 1) {
                ForEach(DataOrientation.allCases, id: \.self) { option in
                    optionRow(
                        title: option.title,
                        description: option.description,
                        isSelected: orientation == option
                    ) {
                        orientation = option
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Import Mode Section

    private var importModeSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("IMPORT MODE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            Text("Are you importing multiple items or fields for one item?")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: 1) {
                ForEach(ImportMode.allCases, id: \.self) { option in
                    optionRow(
                        title: option.title,
                        description: option.description(for: orientation),
                        isSelected: importMode == option
                    ) {
                        importMode = option
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Option Row

    private func optionRow(
        title: String,
        description: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(description)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 12)
            .background(isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("CONTINUE")
                Image(systemName: "arrow.right")
            }
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background)
    }
}

#Preview {
    let sampleData = SpreadsheetData(
        headers: ["Name", "Qty", "SKU"],
        rows: [
            SpreadsheetRow(values: ["Lumber", "100", "LUM-01"]),
            SpreadsheetRow(values: ["Drywall", "50", "DRY-01"])
        ],
        sourceFileName: "inventory.csv"
    )

    return ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        ImportConfigView(
            spreadsheetData: sampleData,
            orientation: .constant(.rowsAreItems),
            importMode: .constant(.multipleItems),
            onContinue: { }
        )
    }
}
