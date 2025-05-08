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
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color(red: 0.1, green: 0.1, blue: 0.15).opacity(backgroundGradientAmount)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
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
                            .scaleEffect(logoScale)
                            .opacity(logoOpacity)
                    }
                    
                    // App name with delayed fade in
                    VStack(spacing: 4) {
                        Text("OPS")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Run your job site smarter")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .opacity(textOpacity)
                }
                
                Spacer()
                
                // Version info
                Text("v1.0.0")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.gray.opacity(0.7))
                    .padding(.bottom, 16)
                    .opacity(textOpacity)
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
