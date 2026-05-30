//
//  ClientPickerSheet.swift
//  OPS
//
//  Simple client picker for reassigning a project's client.
//

import SwiftUI
import SwiftData

struct ClientPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataController: DataController
    @Query private var allClients: [Client]

    let currentClientId: String?
    let companyId: String
    let onSelect: (Client) -> Void

    @State private var searchText = ""

    private var filteredClients: [Client] {
        let companyClients = allClients.filter {
            $0.companyId == companyId && $0.deletedAt == nil
        }
        if searchText.isEmpty {
            return companyClients.sorted { $0.name < $1.name }
        }
        return companyClients
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 8) {
                        Image(OPSStyle.Icons.search)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        TextField("Search clients", text: $searchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // Client list
                    VStack(spacing: 0) {
                        if filteredClients.isEmpty {
                            Text("No clients found")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(filteredClients) { client in
                                let isCurrent = client.id == currentClientId

                                Button(action: {
                                    if !isCurrent {
                                        onSelect(client)
                                        dismiss()
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        UserAvatar(client: client, size: 32)

                                        Text(client.name)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)

                                        Spacer()

                                        if isCurrent {
                                            StatusBadgePill(
                                                text: "CURRENT",
                                                color: OPSStyle.Colors.tertiaryText,
                                                size: .small
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(isCurrent)

                                if client.id != filteredClients.last?.id {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.cardBorderSubtle)
                                        .frame(height: 1)
                                        .padding(.leading, 60)
                                }
                            }
                        }
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                }
            }
            .background(OPSStyle.Colors.background)
            .standardSheetToolbar(
                title: "Change Client",
                actionText: "",
                isActionEnabled: false,
                onCancel: { dismiss() },
                onAction: {}
            )
        }
    }
}
