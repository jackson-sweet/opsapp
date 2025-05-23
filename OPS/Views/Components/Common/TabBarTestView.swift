//
//  TabBarTestView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-21.
//

import SwiftUI

struct TabBarTestView: View {
    @State private var selectedTab = 0
    
    private let tabs = [
        TabItem(iconName: "house.fill"),
        TabItem(iconName: "calendar"), 
        TabItem(iconName: "gearshape.fill")
    ]
    
    var body: some View {
        ZStack {
            // Background matching app style
            OPSStyle.Colors.background
                .ignoresSafeArea()
            
            VStack {
                // Main content area
                Spacer()
                
                Text("Tab \(selectedTab + 1) Selected")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                // Custom tab bar
                CustomTabBar(selectedTab: $selectedTab, tabs: tabs)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct TabBarTestView_Previews: PreviewProvider {
    static var previews: some View {
        TabBarTestView()
    }
}