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
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        TextField("Search clients", text: $searchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)

                    // Client list
                    VStack(spacing: 0) {
                        if filteredClients.isEmpty {
                            Text("No clients found")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.vertical, OPSStyle.Layout.spacing3_5)
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
                                    HStack(spacing: OPSStyle.Layout.spacing2_5) {
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
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                    .glassSurface()
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
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
