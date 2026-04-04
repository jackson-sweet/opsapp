// OPS/OPS/DeckBuilder/Views/ShareActionSheet.swift

import SwiftUI
import UIKit

/// Wraps UIActivityViewController for SwiftUI share sheet presentation
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
