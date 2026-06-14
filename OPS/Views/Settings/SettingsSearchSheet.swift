//
//  SettingsSearchSheet.swift
//  OPS
//
//  Search sheet for settings to avoid keyboard pushing content
//

import SwiftUI

struct SettingsSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    let allSearchableSettings: [SearchableSettingItem]

    // Filtered search results
    private var searchResults: [SearchableSettingItem] {
        guard !searchText.isEmpty else { return [] }
        return allSearchableSettings.filter { $0.matches(query: searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing3)

                    // Search results
                    if searchText.isEmpty {
                        emptySearchState
                    } else if searchResults.isEmpty {
                        noResultsState
                    } else {
                        searchResultsList
                    }
                }
            }
            .navigationTitle("Search Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .onAppear {
                // Auto-focus search field when sheet appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Magnifying glass icon
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Search text field
            TextField("Search settings...", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .focused($isSearchFocused)
                .autocapitalization(.none)
                .autocorrectionDisabled(true)

            // Clear button - only show when there's text
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isSearchFocused ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - States

    private var emptySearchState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, 60)

            Text("Search Settings")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Find profile, organization, or app settings")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, 60)

            Text("No Results Found")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Try a different search term")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchResultsList: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Results header
                HStack {
                    Text("\(searchResults.count) RESULT\(searchResults.count == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing1)

                // Search results
                ForEach(searchResults) { item in
                    NavigationLink(destination: item.destination) {
                        searchResultRow(for: item)
                    }
                }
            }
            .padding(.bottom, OPSStyle.Layout.spacing3_5)
        }
    }

    private func searchResultRow(for item: SearchableSettingItem) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // Category icon
            Image(systemName: item.categoryIcon)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(item.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(item.categoryTitle)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            // Chevron
            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }
}

// MARK: - Searchable Setting Item

struct SearchableSettingItem: Identifiable {
    let id = UUID()
    let title: String
    let categoryTitle: String
    let categoryIcon: String
    let keywords: [String]
    let destination: AnyView

    func matches(query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        return title.lowercased().contains(lowercasedQuery) ||
               categoryTitle.lowercased().contains(lowercasedQuery) ||
               keywords.contains { $0.lowercased().contains(lowercasedQuery) }
    }
}
