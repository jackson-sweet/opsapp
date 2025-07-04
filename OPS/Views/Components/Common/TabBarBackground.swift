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
            BlurView(style: .systemUltraThinMaterialDark)
            
            // Semi-transparent overlay
            Color(OPSStyle.Colors.cardBackgroundDark)
                .opacity(0.5)
        }
        .frame(height: 96)
        .edgesIgnoringSafeArea(.bottom)
    }
}
