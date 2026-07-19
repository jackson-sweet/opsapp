//
//  ClientPickerSheet.swift
//  OPS
//
//  Simple client picker for reassigning a project's client. Bug 388663d4 —
//  the picker also indexes the operator's phone contacts: a contact that
//  matches the search but isn't in OPS yet shows an "IN CONTACTS" badge, and
//  tapping it creates the client in the background before reassigning.
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
    // Bug 388663d4 — device address book blended into the picker. Loaded
    // lazily on the first keystroke; degrades to empty when access is denied.
    @StateObject private var phoneContacts = PhoneContactsProvider()
    @State private var didPreparePhoneContacts = false
    @State private var isImporting = false
    @State private var importError: String?

    /// All non-deleted clients for this company — the source for both the
    /// visible list and the "already in OPS" dedupe of phone contacts.
    private var companyClients: [Client] {
        allClients.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }

    private var filteredClients: [Client] {
        if searchText.isEmpty {
            return companyClients.sorted { $0.name < $1.name }
        }
        return companyClients
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    /// Device contacts matching the search that aren't already in OPS. Only
    /// while searching — an empty field lists existing clients, not the whole
    /// address book.
    private var phoneContactMatches: [PhoneContactSuggestion] {
        guard phoneContacts.canRead, !searchText.isEmpty else { return [] }
        let matches = PhoneContactSearch.matching(phoneContacts.suggestions, query: searchText)
        guard !matches.isEmpty else { return [] }
        let identity = ClientIdentityIndex(clients: companyClients)
        return PhoneContactSearch.notInOps(matches, existing: identity)
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

                    // Client list (+ phone contacts not yet in OPS)
                    clientList
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
            .onChange(of: searchText) { _, newValue in
                // Warm the device-contacts index on the first real keystroke.
                if !newValue.isEmpty && !didPreparePhoneContacts {
                    didPreparePhoneContacts = true
                    Task { await phoneContacts.prepare() }
                }
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    @ViewBuilder
    private var clientList: some View {
        let clientRows = filteredClients
        let phoneRows = Array(phoneContactMatches.prefix(10))

        VStack(spacing: 0) {
            if clientRows.isEmpty && phoneRows.isEmpty {
                Text("No clients found")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.vertical, OPSStyle.Layout.spacing3_5)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(clientRows) { client in
                    clientRow(client)
                    if client.id != clientRows.last?.id || !phoneRows.isEmpty {
                        rowDivider
                    }
                }
                ForEach(phoneRows) { suggestion in
                    phoneContactRow(suggestion)
                    if suggestion.id != phoneRows.last?.id {
                        rowDivider
                    }
                }
            }
        }
    }

    private func clientRow(_ client: Client) -> some View {
        let isCurrent = client.id == currentClientId

        return Button(action: {
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
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCurrent)
    }

    /// A device-contact row (with an avatar, to match the client rows above).
    /// Tapping it creates the OPS client in the background, then assigns it to
    /// the project via `onSelect`.
    private func phoneContactRow(_ suggestion: PhoneContactSuggestion) -> some View {
        PhoneContactRow(suggestion: suggestion, showsAvatar: true, isDisabled: isImporting) {
            importContact(suggestion)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorderSubtle)
            .frame(height: 1)
            .padding(.leading, 60)
    }

    /// Bug 388663d4 — create the OPS client from a device contact, then hand
    /// the saved model to `onSelect` so the project is reassigned to it.
    private func importContact(_ suggestion: PhoneContactSuggestion) {
        guard !isImporting else { return }
        isImporting = true
        #if !targetEnvironment(simulator)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let result = try await phoneContacts.importClient(
                    from: suggestion,
                    companyId: companyId,
                    dataController: dataController
                )
                #if !targetEnvironment(simulator)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                onSelect(result.client)
                dismiss()
            } catch {
                importError = "Couldn't add this contact. Try again."
                #if !targetEnvironment(simulator)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                #endif
            }
        }
    }
}
