//
//  UIComponents.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

// MARK: - Loading Views

/// Full-screen loading view with logo for app initialization
struct SplashLoadingView: View {
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                    
                    HStack(alignment: .bottom){
                        // Logo
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                    }
                    .padding(.bottom, 40)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                        .scaleEffect(1.2)
                    
                    
                Spacer()
                
                // Version info
                Text("v1.0.0")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, OPSStyle.Layout.spacing3)
            }
        }
    }
}

/// Overlay loading view for in-progress operations
struct LoadingView: View {
    var message: String = "Processing..."
    var isFullScreen: Bool = false
    
    var body: some View {
        ZStack {
            if isFullScreen {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            } else {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
            }
            
            VStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                
                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(.white)
                        .padding(.top, 12)
                }
            }
            .padding(24)
            .background(Color(white: 0.1))
            .cornerRadius(12)
        }
    }
}
