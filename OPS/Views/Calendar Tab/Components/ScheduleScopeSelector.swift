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
                // Team member chips with avatar + initials
                ForEach(viewModel.availableTeamMembers, id: \.id) { member in
                    let isSelected: Bool = {
                        if case .member(let id) = viewModel.scheduleScope {
                            return id == member.id
                        }
                        return false
                    }()

                    memberChip(member: member, isSelected: isSelected) {
                        viewModel.updateScheduleScope(.member(member.id))
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    @ViewBuilder
    private func memberChip(member: TeamMember, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                action()
            }
        }) {
            HStack(spacing: 6) {
                TeamMemberAvatar(teamMember: member, size: 22)

                Text(member.initials)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(
                        isSelected
                            ? OPSStyle.Colors.primaryText
                            : OPSStyle.Colors.tertiaryText
                    )
            }
            .padding(.vertical, 6)
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }
}
