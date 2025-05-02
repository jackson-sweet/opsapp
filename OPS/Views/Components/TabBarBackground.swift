//
//  TabBarBackground.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI

struct TabBarBackground: View {
    var body: some View {
        ZStack {
            // Blur effect
            BlurView(style: .systemThinMaterialDark)
            
            // Semi-transparent overlay
            Color(OPSStyle.Colors.cardBackgroundDark)
                .opacity(0.3)
        }
        .frame(height: 96)
        .edgesIgnoringSafeArea(.bottom)
    }
}