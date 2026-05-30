//
//  ClientListView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-09-26.
//

import SwiftUI
import SwiftData

enum ClientFilter: String, CaseIterable {
    case all = "ALL"
    case new = "NEW"
}

struct ClientListView: View {
    @EnvironmentObject private var dataController: DataController
    @Query private var clients: [Client]
    let searchText: String
    @State private var showingCreateClient = false
    @State private var lastDraggedLetter: String? = nil
    @State private var activeFilter: ClientFilter = .all

    private var newClientsThreshold: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    private var newClientsCount: Int {
        clients.filter { ($0.createdAt ?? .distantPast) > newClientsThreshold }.count
    }

    init(searchText: String, companyId: String) {
        self.searchText = searchText
        _clients = Query(
            filter: #Predicate<Client> { client in
                client.companyId == companyId && client.deletedAt == nil
            },
            sort: [SortDescriptor(\Client.name)]
        )
    }

    private var sortedAndFilteredClients: [Client] {
        var filtered = searchText.isEmpty ? clients : clients.filter { client in
            client.name.localizedCaseInsensitiveContains(searchText) ||
            (client.email?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (client.phoneNumber?.localizedCaseInsensitiveContains(searchText) ?? false)
        }

        if activeFilter == .new {
            filtered = filtered.filter { ($0.createdAt ?? .distantPast) > newClientsThreshold }
        }

        return filtered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var groupedClients: [String: [Client]] {
        Dictionary(grouping: sortedAndFilteredClients) { client in
            let firstChar = client.name.prefix(1).uppercased()
            return firstChar.rangeOfCharacter(from: .letters) != nil ? firstChar : "#"
        }
    }

    private var allLetters: [String] {
        let letters = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) }
        return ["#"] + letters
    }

    private var sectionTitles: [String] {
        allLetters.filter { groupedClients[$0]?.isEmpty == false }
    }

    var body: some View {
        VStack(spacing: 0) {
            if clients.isEmpty {
                JobBoardEmptyState(
                    icon: OPSStyle.Icons.client,
                    title: "No Clients Yet",
                    subtitle: "Add your first client to get started"
                )
                .frame(maxHeight: .infinity)
            } else {
                // Filter chips
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(ClientFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            withAnimation(OPSStyle.Animation.fast) {
                                activeFilter = filter
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(filter.rawValue)
                                    .font(OPSStyle.Typography.captionBold)
                                if filter == .new && newClientsCount > 0 {
                                    Text("\(newClientsCount)")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(
                                                activeFilter == filter
                                                ? Color.black.opacity(0.3)
                                                : OPSStyle.Colors.primaryAccent.opacity(0.3)
                                            )
                                        )
                                }
                            }
                            .foregroundColor(activeFilter == filter ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .fill(activeFilter == filter ? OPSStyle.Colors.primaryText : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(activeFilter == filter ? .clear : OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }
                .padding(.bottom, OPSStyle.Layout.spacing2)

                if activeFilter == .new && sortedAndFilteredClients.isEmpty {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        Spacer()
                        Image(OPSStyle.Icons.client)
                            .font(.system(size: 44))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("NO NEW CLIENTS")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("[no clients added in the last 7 days]")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(sectionTitles, id: \.self) { letter in
                                Section(header: sectionHeader(letter: letter)) {
                                    ForEach(groupedClients[letter] ?? []) { client in
                                        UniversalJobBoardCard(cardType: .client(client))
                                            .environmentObject(dataController)
                                    }
                                }
                                .id(letter)
                            }
                        }
                        .padding(.trailing, 32)
                        .padding(.top, 12)
                        .padding(.bottom, 120)
                    }
                    .overlay(alignment: .trailing) {
                        alphabetIndex(proxy: proxy)

                    }
                }
                } // end activeFilter empty check
            }
        }
        .trackScreen("JobBoard.Clients")
    }

    private func sectionHeader(letter: String) -> some View {
        HStack(spacing: 8) {
            Text("[ \(letter) ]")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Rectangle()
                .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, 8)
        .background(Gradient(colors: [.clear, OPSStyle.Colors.background, .clear]))
    }
    private func alphabetIndex(proxy: ScrollViewProxy) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 2) {
                ForEach(allLetters, id: \.self) { letter in
                    Button(action: {
                        if sectionTitles.contains(letter) {
                            withAnimation {
                                proxy.scrollTo(letter, anchor: .top)
                            }
                        }
                    }) {
                        Text(letter)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(
                                sectionTitles.contains(letter)
                                ? OPSStyle.Colors.primaryAccent
                                : OPSStyle.Colors.tertiaryText.opacity(0.3)
                            )
                            .frame(width: 20, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 120)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(at: value.location, in: geometry, proxy: proxy)
                    }
                    .onEnded { _ in
                        lastDraggedLetter = nil
                    }
            )
        }
        .frame(width: 28)
    }

    private func handleDrag(at location: CGPoint, in geometry: GeometryProxy, proxy: ScrollViewProxy) {
        let letterHeight: CGFloat = 18 // spacing (2) + text height (16)

        // Calculate which letter index based on drag position
        let adjustedY = location.y - 8 // Account for top padding
        let index = Int(adjustedY / letterHeight)

        // Make sure index is within bounds
        guard index >= 0 && index < allLetters.count else { return }

        let letter = allLetters[index]

        // Only scroll if the section exists and it's a different letter than last time
        if sectionTitles.contains(letter) && letter != lastDraggedLetter {
            // Update the last dragged letter
            lastDraggedLetter = letter

            // Provide haptic feedback only when changing letters
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            // Scroll to the letter without animation for more responsive dragging
            proxy.scrollTo(letter, anchor: .top)
        }
    }
}

