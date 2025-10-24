//
//  UniversalSearchBar.swift
//  OPS
//
//  Created by Assistant on 2025-09-29.
//

import SwiftUI
import SwiftData

enum ProjectFilterOption: String, CaseIterable {
    case all = "All"
    case rfq = "RFQ"
    case estimated = "Estimated"
    case accepted = "Accepted"
    case inProgress = "In Progress"
    case completed = "Completed"
    case closed = "Closed"

    var status: Status? {
        switch self {
        case .all: return nil
        case .rfq: return .rfq
        case .estimated: return .estimated
        case .accepted: return .accepted
        case .inProgress: return .inProgress
        case .completed: return .completed
        case .closed: return .closed
        }
    }
}

enum TaskFilterOption: String, CaseIterable {
    case all = "All"
    case scheduled = "Scheduled"
    case inProgress = "In Progress"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var status: TaskStatus? {
        switch self {
        case .all: return nil
        case .scheduled: return .scheduled
        case .inProgress: return .inProgress
        case .completed: return .completed
        case .cancelled: return .cancelled
        }
    }
}


struct UniversalSearchBar: View {
    let section: JobBoardSection
    @Binding var searchText: String
    @Binding var showingFilters: Bool
    var onFilterTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .font(.system(size: 16))

                    TextField(placeholderText, text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .autocorrectionDisabled(true)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)

                if section != .clients {
                    Button(action: {
                        if let onFilterTap = onFilterTap {
                            onFilterTap()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showingFilters.toggle()
                            }
                        }
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 24))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }

        }
    }

    private var placeholderText: String {
        switch section {
        case .dashboard:
            return "Search..."
        case .clients:
            return "Search clients..."
        case .projects:
            return "Search projects..."
        case .tasks:
            return "Search tasks..."
        }
    }
}