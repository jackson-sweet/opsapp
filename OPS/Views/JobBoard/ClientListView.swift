//
//  ClientListView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-09-26.
//

import SwiftUI
import SwiftData

struct ClientListView: View {
    @EnvironmentObject private var dataController: DataController
    @Query private var clients: [Client]
    let searchText: String
    @State private var showingCreateClient = false
    @State private var lastDraggedLetter: String? = nil

    private var sortedAndFilteredClients: [Client] {
        let filtered = searchText.isEmpty ? clients : clients.filter { client in
            client.name.localizedCaseInsensitiveContains(searchText) ||
            (client.email?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (client.phoneNumber?.localizedCaseInsensitiveContains(searchText) ?? false)
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
                    icon: "person.2.fill",
                    title: "No Clients Yet",
                    subtitle: "Add your first client to get started"
                )
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
            }
        }
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
                            .font(.system(size: 10, weight: .medium))
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

