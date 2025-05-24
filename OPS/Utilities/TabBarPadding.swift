//
//  TabBarPadding.swift
//  OPS
//
//  View modifier to ensure consistent padding for tab bar across all views
//

import SwiftUI

struct TabBarPadding: ViewModifier {
    let additionalPadding: CGFloat
    
    init(additionalPadding: CGFloat = 0) {
        self.additionalPadding = additionalPadding
    }
    
    func body(content: Content) -> some View {
        content
            .padding(.bottom, 90 + additionalPadding) // Standard tab bar height + any additional
    }
}

extension View {
    /// Adds standard padding to account for the tab bar
    func tabBarPadding(additional: CGFloat = 0) -> some View {
        self.modifier(TabBarPadding(additionalPadding: additional))
    }
}