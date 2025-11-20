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
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)

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
        HStack(spacing: 12) {
            // Magnifying glass icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
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
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isSearchFocused ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - States

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
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
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
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
            VStack(spacing: 12) {
                // Results header
                HStack {
                    Text("\(searchResults.count) RESULT\(searchResults.count == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

                // Search results
                ForEach(searchResults) { item in
                    NavigationLink(destination: item.destination) {
                        searchResultRow(for: item)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func searchResultRow(for item: SearchableSettingItem) -> some View {
        HStack(spacing: 16) {
            // Category icon
            Image(systemName: item.categoryIcon)
                .font(.system(size: 20))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(item.categoryTitle)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
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
