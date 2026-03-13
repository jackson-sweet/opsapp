//
//  ScheduleScopeSelector.swift
//  OPS
//
//  Quick team/user filter for the schedule calendar and task list.
//  Shown to admin/office crew only.
//

import SwiftUI

struct ScheduleScopeSelector: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Team member chips only (ALL/MINE toggle moved to header)
                ForEach(viewModel.availableTeamMembers, id: \.id) { member in
                    let isSelected: Bool = {
                        if case .member(let id) = viewModel.scheduleScope {
                            return id == member.id
                        }
                        return false
                    }()

                    scopeChip(label: member.initials, isSelected: isSelected) {
                        viewModel.updateScheduleScope(.member(member.id))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func scopeChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                action()
            }
        }) {
            Text(label)
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(
                    isSelected
                        ? OPSStyle.Colors.cardBackgroundDark
                        : OPSStyle.Colors.secondaryText
                )
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(isSelected ? OPSStyle.Colors.primaryText : .clear)
                )
        }
    }
}
