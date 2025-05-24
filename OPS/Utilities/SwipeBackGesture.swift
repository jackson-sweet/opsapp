//
//  SwipeBackGesture.swift
//  OPS
//
//  Created for enabling swipe-back navigation in views with hidden navigation bars
//

import SwiftUI

struct SwipeBackGesture: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @GestureState private var dragOffset: CGSize = .zero
    @State private var isSwipingBack = false
    
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        // Only track horizontal swipes from left edge
                        if value.startLocation.x < 20 && value.translation.width > 0 {
                            state = value.translation
                        }
                    }
                    .onEnded { value in
                        // Detect swipe from left edge
                        if value.startLocation.x < 20 && value.translation.width > 100 {
                            // Swipe detected - navigate back
                            dismiss()
                        }
                    }
            )
            .offset(x: dragOffset.width > 0 ? dragOffset.width : 0)
            .animation(.interactiveSpring(), value: dragOffset)
    }
}

// Alternative implementation using UIKit for more native feel
struct NativeSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Enable interactive pop gesture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let nav = uiViewController.navigationController {
                nav.interactivePopGestureRecognizer?.isEnabled = true
                nav.interactivePopGestureRecognizer?.delegate = nil
            }
        }
    }
}

extension View {
    /// Adds swipe-back gesture support to views with hidden navigation bars
    func swipeBackGesture() -> some View {
        self.modifier(SwipeBackGesture())
    }
    
    /// Enables native iOS swipe-back gesture even with hidden navigation bar
    func enableNativeSwipeBack() -> some View {
        self.background(NativeSwipeBack())
    }
}