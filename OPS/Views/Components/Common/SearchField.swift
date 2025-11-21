//
//  SearchField.swift
//  OPS
//
//  Generic search field with dropdown suggestions
//

import SwiftUI

/// Generic search field component with predictive dropdown suggestions
///
/// Usage:
/// ```swift
/// SearchField(
///     selectedId: $selectedClientId,
///     items: availableClients,
///     placeholder: "Search for client",
///     leadingIcon: OPSStyle.Icons.client,
///     getId: { $0.id },
///     getDisplayText: { $0.name },
///     getSubtitle: { client in
///         client.projects.count > 0
///             ? "\(client.projects.count) project\(client.projects.count == 1 ? "" : "s")"
///             : nil
///     }
/// )
/// ```
struct SearchField<Item: Identifiable & Hashable>: View {
    // MARK: - Properties

    @Binding var selectedId: String?
    let items: [Item]
    let placeholder: String
    let leadingIcon: String?

    // Display configuration closures
    let getId: (Item) -> String
    let getDisplayText: (Item) -> String
    let getSubtitle: ((Item) -> String?)?
    let getLeadingIcon: ((Item) -> String)?
    let getLeadingIconColor: ((Item) -> Color)?
    let getLeadingAccessory: ((Item) -> AnyView)?

    // State
    @State private var searchText: String = ""
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

    // MARK: - Initializer

    init(
        selectedId: Binding<String?>,
        items: [Item],
        placeholder: String,
        leadingIcon: String? = nil,
        getId: @escaping (Item) -> String,
        getDisplayText: @escaping (Item) -> String,
        getSubtitle: ((Item) -> String?)? = nil,
        getLeadingIcon: ((Item) -> String)? = nil,
        getLeadingIconColor: ((Item) -> Color)? = nil,
        getLeadingAccessory: ((Item) -> AnyView)? = nil
    ) {
        self._selectedId = selectedId
        self.items = items
        self.placeholder = placeholder
        self.leadingIcon = leadingIcon
        self.getId = getId
        self.getDisplayText = getDisplayText
        self.getSubtitle = getSubtitle
        self.getLeadingIcon = getLeadingIcon
        self.getLeadingIconColor = getLeadingIconColor
        self.getLeadingAccessory = getLeadingAccessory
    }

    // MARK: - Computed Properties

    private var filteredItems: [Item] {
        if searchText.isEmpty {
            return items.sorted { getDisplayText($0) < getDisplayText($1) }
        }
        return items
            .filter { getDisplayText($0).localizedCaseInsensitiveContains(searchText) }
            .sorted { getDisplayText($0) < getDisplayText($1) }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search input field
            inputField

            // Suggestions dropdown
            if showingSuggestions && !filteredItems.isEmpty {
                suggestionsDropdown
            }
        }
        .animation(OPSStyle.Layout.SearchField.animationCurve, value: showingSuggestions)
        .onAppear {
            loadSelectedItem()
        }
    }

    // MARK: - Input Field

    private var inputField: some View {
        HStack {
            // Leading icon (fixed)
            if let icon = leadingIcon {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.SearchField.iconSize))
                    .foregroundColor(OPSStyle.Layout.SearchField.iconColor)
            }

            // Text field
            TextField(placeholder, text: $searchText)
                .font(OPSStyle.Layout.SearchField.textFont)
                .foregroundColor(OPSStyle.Layout.SearchField.textColor)
                .focused($isFocused)
                .onChange(of: searchText) { _, newValue in
                    showingSuggestions = !newValue.isEmpty
                }
                .onTapGesture {
                    showingSuggestions = true
                }

            // Clear button
            if !searchText.isEmpty {
                Button(action: clearSelection) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: OPSStyle.Layout.SearchField.clearButtonSize))
                        .foregroundColor(OPSStyle.Layout.SearchField.clearButtonColor)
                }
            }
        }
        .padding(OPSStyle.Layout.SearchField.inputPadding)
        .background(OPSStyle.Layout.SearchField.inputBackground)
        .cornerRadius(OPSStyle.Layout.SearchField.inputCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.SearchField.inputCornerRadius)
                .stroke(
                    OPSStyle.Layout.SearchField.inputBorderColor,
                    lineWidth: OPSStyle.Layout.SearchField.inputBorderWidth
                )
        )
    }

    // MARK: - Suggestions Dropdown

    private var suggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredItems.prefix(OPSStyle.Layout.SearchField.dropdownMaxResults)) { item in
                suggestionRow(for: item)

                if getId(item) != getId(filteredItems.prefix(OPSStyle.Layout.SearchField.dropdownMaxResults).last!) {
                    Divider()
                        .background(OPSStyle.Layout.SearchField.dividerColor)
                }
            }
        }
        .background(OPSStyle.Layout.SearchField.dropdownBackground)
        .cornerRadius(OPSStyle.Layout.SearchField.dropdownCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.SearchField.dropdownCornerRadius)
                .stroke(
                    OPSStyle.Layout.SearchField.dropdownBorderColor,
                    lineWidth: OPSStyle.Layout.SearchField.dropdownBorderWidth
                )
        )
        .shadow(
            color: OPSStyle.Layout.SearchField.dropdownShadowColor,
            radius: OPSStyle.Layout.SearchField.dropdownShadowRadius,
            x: OPSStyle.Layout.SearchField.dropdownShadowOffset.width,
            y: OPSStyle.Layout.SearchField.dropdownShadowOffset.height
        )
        .padding(.top, OPSStyle.Layout.SearchField.dropdownTopPadding)
        .transition(OPSStyle.Layout.SearchField.transition)
    }

    // MARK: - Suggestion Row

    private func suggestionRow(for item: Item) -> some View {
        Button(action: { selectItem(item) }) {
            HStack {
                // Leading accessory (e.g., color circle + icon for TaskType)
                if let getAccessory = getLeadingAccessory {
                    getAccessory(item)
                }
                // OR leading icon if no accessory
                else if let getIcon = getLeadingIcon, let getColor = getLeadingIconColor {
                    Image(systemName: getIcon(item))
                        .font(.system(size: OPSStyle.Layout.SearchField.rowIconSize))
                        .foregroundColor(getColor(item))
                }

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(getDisplayText(item))
                        .font(OPSStyle.Layout.SearchField.rowTitleFont)
                        .foregroundColor(OPSStyle.Layout.SearchField.rowTitleColor)
                        .lineLimit(1)

                    if let getSubtitle = getSubtitle, let subtitle = getSubtitle(item) {
                        Text(subtitle)
                            .font(OPSStyle.Layout.SearchField.rowSubtitleFont)
                            .foregroundColor(OPSStyle.Layout.SearchField.rowSubtitleColor)
                    }
                }

                Spacer()

                // Selection checkmark
                if selectedId == getId(item) {
                    Image(systemName: OPSStyle.Icons.checkmark)
                        .font(.system(size: OPSStyle.Layout.SearchField.rowCheckmarkSize))
                        .foregroundColor(OPSStyle.Layout.SearchField.rowCheckmarkColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.SearchField.rowPaddingHorizontal)
            .padding(.vertical, OPSStyle.Layout.SearchField.rowPaddingVertical)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Actions

    private func selectItem(_ item: Item) {
        selectedId = getId(item)
        searchText = getDisplayText(item)
        showingSuggestions = false
        isFocused = false
    }

    private func clearSelection() {
        searchText = ""
        selectedId = nil
        showingSuggestions = false
    }

    private func loadSelectedItem() {
        if let id = selectedId,
           let item = items.first(where: { getId($0) == id }) {
            searchText = getDisplayText(item)
        }
    }
}
