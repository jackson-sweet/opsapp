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
    case active = "Active"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var status: TaskStatus? {
        switch self {
        case .all: return nil
        case .active: return .active
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
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.search)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))

                    TextField(placeholderText, text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .autocorrectionDisabled(true)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, 10)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                )

                if section == .projects || section == .tasks {
                    Button(action: {
                        if let onFilterTap = onFilterTap {
                            onFilterTap()
                        } else {
                            withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                                showingFilters.toggle()
                            }
                        }
                    }) {
                        Image(systemName: OPSStyle.Icons.filter)
                            .font(.system(size: OPSStyle.Layout.IconSize.lg))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }

        }
        .background(.clear)
       
    }

    private var placeholderText: String {
        switch section {
        case .projects:
            return "Search projects..."
        case .tasks:
            return "Search tasks..."
        case .myTasks:
            return "Search tasks..."
        case .myProjects:
            return "Search projects..."
        default:
            return "Search..."
        }
    }
}
