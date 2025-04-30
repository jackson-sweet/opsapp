//
//  SplashScreen.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI

struct SplashScreen: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                // Logo
                VStack(spacing: OPSStyle.Layout.spacing5) {
                    // OPS logo
                    ZStack {
                        // Logo shape - a stylized "P" with square corners
                        Image("AppIcon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .foregroundColor(Color(.gray))
                            .opacity(isAnimating ? 1 : 0)
                    }
                    
                    // App name
                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .opacity(isAnimating ? 1 : 0)
                }
                
                Spacer()
                
                // Version info
                Text("v1.0.0")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, OPSStyle.Layout.spacing3)
                    .opacity(isAnimating ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(Animation.easeIn(duration: 0.8)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    SplashScreen()
        .preferredColorScheme(.dark)
}
