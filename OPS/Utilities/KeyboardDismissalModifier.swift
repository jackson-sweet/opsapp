//
//  KeyboardDismissalModifier.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


//
//  KeyboardDismissalModifier.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI

// Extension to hide keyboard when tapping outside text fields
// This is especially useful for field workers who may be using the app in challenging environments

struct KeyboardDismissalModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle()) // Ensure the entire area is tappable
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        self.modifier(KeyboardDismissalModifier())
    }
}