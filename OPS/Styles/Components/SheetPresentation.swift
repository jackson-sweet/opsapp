//
//  SheetPresentation.swift
//  OPS
//
//  Shared sheet presentation modifiers for consistent sheet behavior across the app.
//

import SwiftUI

/// Applies full-width page sizing on iOS 18+ so sheets don't show a gap at the edges
/// when presented over another sheet or at .medium detent.
private struct PageSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}

extension View {
    /// Standard OPS sheet presentation: dark background, hidden drag indicator, full-width page sizing.
    ///
    /// Usage:
    /// ```swift
    /// .opsSheet(detents: [.medium, .large])
    /// ```
    func opsSheet(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(.hidden)
            .presentationBackground(OPSStyle.Colors.background)
            .modifier(PageSizingModifier())
    }
}
