//
//  CustomTabBar.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-21.
//

import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [TabItem]
    
    @State private var selectedIndicatorOffset: CGFloat = 0
    @State private var tabWidth: CGFloat = 0
    @State private var iconWidth: CGFloat = 28 // SF Symbols 28pt size
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab bar background with ultra thin blur
            BlurView(style: .systemUltraThinMaterialDark)
                .frame(height: 80)
                .ignoresSafeArea(.all, edges: .bottom)
            
            VStack(spacing: 0) {
                // Sliding indicator bar - sized to match icon width
                HStack {
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: iconWidth, height: 3)
                        .cornerRadius(1.5)
                        .offset(x: selectedIndicatorOffset)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedIndicatorOffset)
                    
                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                
                // Tab items
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        TabBarItem(
                            tab: tab,
                            isSelected: selectedTab == index,
                            action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedTab = index
                                    updateIndicatorPosition(for: index)
                                }
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        if tabWidth == 0 {
                                            tabWidth = geometry.size.width
                                            updateIndicatorPosition(for: selectedTab)
                                        }
                                    }
                                    .onChange(of: geometry.size) { _, newSize in
                                        tabWidth = newSize.width
                                        updateIndicatorPosition(for: selectedTab)
                                    }
                            }
                        )
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            // Set initial position after a brief delay to ensure layout is complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateIndicatorPosition(for: selectedTab)
            }
        }
    }
    
    private func updateIndicatorPosition(for index: Int) {
        // Center the indicator under the icon
        let tabCenter = CGFloat(index) * tabWidth + (tabWidth / 2)
        let indicatorCenter = iconWidth / 2
        selectedIndicatorOffset = tabCenter - indicatorCenter
    }
}

struct TabBarItem: View {
    let tab: TabItem
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                
                if let title = tab.title {
                    Text(title)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                        .opacity(isSelected ? 1.0 : 0.8)
                }
            }
        }
        .frame(height: 50)
        .contentShape(Rectangle()) // Make entire area tappable for field use
    }
}

struct TabItem: Identifiable {
    let id = UUID()
    let iconName: String
    let title: String?
    
    init(iconName: String, title: String? = nil) {
        self.iconName = iconName
        self.title = title
    }
}

// Preview
struct CustomTabBar_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                CustomTabBar(
                    selectedTab: .constant(0),
                    tabs: [
                        TabItem(iconName: "house.fill", title: "Home"),
                        TabItem(iconName: "calendar", title: "Schedule"),
                        TabItem(iconName: "gearshape.fill", title: "Settings")
                    ]
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}