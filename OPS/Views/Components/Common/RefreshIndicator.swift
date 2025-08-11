//
//  RefreshIndicator.swift
//  OPS
//
//  A centered loading indicator that transitions to a success checkmark
//

import SwiftUI

struct RefreshIndicator: View {
    @Binding var isPresented: Bool
    @State private var isLoading = true
    @State private var rotation: Double = 0
    
    var body: some View {
        if isPresented {
            ZStack {
                
                // Indicator container
                VStack(spacing: 16) {
                    ZStack {
                        
                        if isLoading {
                            // Loading spinner
                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(
                                    OPSStyle.Colors.primaryText,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .square)
                                )
                                .frame(width: 40, height: 40)
                                .rotationEffect(.degrees(rotation))
                                .onAppear {
                                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                        rotation = 360
                                    }
                                }
                        } else {
                            // Success checkmark
                            Image(systemName: "checkmark")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.successStatus)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    
                    Text(isLoading ? "Refreshing..." : "Projects Updated".uppercased())
                        .font(OPSStyle.Typography.status)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(24)
                .background(
                    ZStack {
                        BlurView(style: .systemUltraThinMaterialDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.85))
                    }
                )
                .scaleEffect(isPresented ? 1 : 0.8)
                .opacity(isPresented ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
            }
            .transition(.opacity)
            .onAppear {
                // Transition from loading to success after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoading = false
                    }
                    
                    // Auto-dismiss after showing success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
                }
            }
            .onDisappear {
                // Reset state for next use
                isLoading = true
                rotation = 0
            }
        }
    }
}

// View modifier for easy application
struct RefreshIndicatorModifier: ViewModifier {
    @Binding var isPresented: Bool
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            RefreshIndicator(isPresented: $isPresented)
                .zIndex(999)
        }
    }
}

extension View {
    func refreshIndicator(isPresented: Binding<Bool>) -> some View {
        modifier(RefreshIndicatorModifier(isPresented: isPresented))
    }
}
