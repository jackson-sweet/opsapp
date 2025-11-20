//
//  ClientSearchField.swift
//  OPS
//
//  Predictive search field for selecting clients
//

import SwiftUI

struct ClientSearchField: View {
    @Binding var selectedClientId: String?
    let availableClients: [Client]
    let placeholder: String

    @State private var searchText: String = ""
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

    private var filteredClients: [Client] {
        if searchText.isEmpty {
            return availableClients.sorted { $0.name < $1.name }
        }
        return availableClients
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    private var selectedClientName: String {
        guard let id = selectedClientId,
              let client = availableClients.first(where: { $0.id == id }) else {
            return ""
        }
        return client.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Client input field
            HStack {
                Image(systemName: OPSStyle.Icons.client)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField(placeholder, text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)
                    .focused($isFocused)
                    .onChange(of: searchText) { _, newValue in
                        if !newValue.isEmpty {
                            showingSuggestions = true
                        } else {
                            showingSuggestions = false
                        }
                    }
                    .onTapGesture {
                        showingSuggestions = true
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        selectedClientId = nil
                        showingSuggestions = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )

            // Suggestions dropdown
            if showingSuggestions && !filteredClients.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredClients.prefix(5)) { client in
                        Button(action: {
                            selectClient(client)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .lineLimit(1)

                                    if client.projects.count > 0 {
                                        Text("\(client.projects.count) project\(client.projects.count == 1 ? "" : "s")")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                }

                                Spacer()

                                if selectedClientId == client.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())

                        if client.id != filteredClients.prefix(5).last?.id {
                            Divider()
                                .background(OPSStyle.Colors.tertiaryText.opacity(0.3))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
                .shadow(color: OPSStyle.Colors.shadowColor, radius: 8, x: 0, y: 4)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingSuggestions)
        .onAppear {
            if let id = selectedClientId,
               let client = availableClients.first(where: { $0.id == id }) {
                searchText = client.name
            }
        }
    }

    private func selectClient(_ client: Client) {
        selectedClientId = client.id
        searchText = client.name
        showingSuggestions = false
        isFocused = false
    }
}
