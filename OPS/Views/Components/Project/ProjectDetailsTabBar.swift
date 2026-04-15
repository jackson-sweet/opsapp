//
//  ProjectDetailsTabBar.swift
//  OPS
//
//  Custom 3-tab segmented control: ACTIVITY | DETAILS | EXPENSES
//  Kosugi 12pt caps, tracked. Active tab gets accent underline.
//

import SwiftUI

struct ProjectDetailsTabBar: View {
    @Binding var selectedTab: ProjectDetailTab
    var visibleTabs: [ProjectDetailTab] = ProjectDetailTab.allCases

    var body: some View {
        GeometryReader { geometry in
            let tabWidth = geometry.size.width / CGFloat(visibleTabs.count)

            ZStack(alignment: .bottomLeading) {
                // Background line
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .offset(y: 0)

                // Tab labels
                HStack(spacing: 0) {
                    ForEach(visibleTabs, id: \.self) { tab in
                        Button(action: {
                            withAnimation(OPSStyle.Animation.fast) {
                                selectedTab = tab
                            }
                        }) {
                            Text(tab.rawValue)
                                .font(OPSStyle.Typography.smallCaption)
                                .tracking(1)
                                .textCase(.uppercase)
                                .foregroundColor(
                                    selectedTab == tab
                                        ? OPSStyle.Colors.primaryText
                                        : OPSStyle.Colors.tertiaryText
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Sliding accent underline
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: tabWidth, height: 2)
                    .offset(x: tabWidth * CGFloat(visibleTabs.firstIndex(of: selectedTab) ?? 0))
                    .animation(OPSStyle.Animation.fast, value: selectedTab)
            }
        }
        .frame(height: 44)
    }
}
