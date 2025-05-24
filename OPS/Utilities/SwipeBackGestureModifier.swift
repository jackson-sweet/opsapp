//
//  SwipeBackGestureModifier.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-22.
//

import SwiftUI

struct SwipeBackGestureModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @GestureState private var dragAmount: CGSize = .zero
    @State private var isDragging = false
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture()
                    .updating($dragAmount) { value, state, _ in
                        // Only track horizontal swipes from the left edge
                        if value.startLocation.x < 30 && value.translation.width > 0 {
                            state = value.translation
                        }
                    }
                    .onChanged { value in
                        // Detect if this is a swipe from the left edge
                        if value.startLocation.x < 30 && value.translation.width > 0 {
                            isDragging = true
                        }
                    }
                    .onEnded { value in
                        // If the swipe is more than 100 points, trigger navigation back
                        if value.startLocation.x < 30 && value.translation.width > 100 {
                            dismiss()
                        }
                        isDragging = false
                    }
            )
            .offset(x: isDragging ? min(dragAmount.width, UIScreen.main.bounds.width * 0.3) : 0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: isDragging)
    }
}

