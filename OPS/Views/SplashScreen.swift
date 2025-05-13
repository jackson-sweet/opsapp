//
//  SplashScreen.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI

struct SplashScreen: View {
    @State private var isAnimating = false
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var backgroundGradientAmount: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Background with gradient animation
            Color(.black)
            
            // Main content
            VStack {
                Spacer()
                
                // Animated logo section
                VStack(spacing: 24) {
                    // OPS logo with animation
                    ZStack {
                        // Logo with scale animation
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .opacity(logoOpacity)
                    }
                    
                    // App name with delayed fade in
                    VStack(spacing: 4) {
                        Text("OPS")
                            .font(OPSStyle.Typography.largeTitle)
                            .foregroundColor(.white)
                        
                        Text("Built by trades, for trades.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .opacity(textOpacity)
                }
                
                Spacer()
                
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            // Sequence of animations
            
            // Start with background gradient
            withAnimation(Animation.easeOut(duration: 1.2)) {
                backgroundGradientAmount = 1.0
            }
            
            // Then animate logo
            withAnimation(Animation.spring(response: 0.8, dampingFraction: 0.6).delay(0.3)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            // Finally fade in text
            withAnimation(Animation.easeIn(duration: 0.7).delay(0.7)) {
                textOpacity = 1.0
            }
        }
    }
}

#Preview {
    SplashScreen()
        .preferredColorScheme(.dark)
}
