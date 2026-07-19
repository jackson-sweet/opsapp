// OPS/OPS/DeckBuilder/Views/VinylOrderMessageComposeView.swift
//
// MFMessageComposeViewController wrapper for texting a vinyl order.
// Extracted verbatim from VinylOrderSheet; shared with the bulk order
// wizard's TEXT ORDER action.

import MessageUI
import SwiftUI
import UIKit

struct VinylOrderMessageComposeView: UIViewControllerRepresentable {
    let body: String
    let onCompletion: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.body = body
        controller.recipients = nil
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onCompletion: (MessageComposeResult) -> Void

        init(onCompletion: @escaping (MessageComposeResult) -> Void) {
            self.onCompletion = onCompletion
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true)
            onCompletion(result)
        }
    }
}
