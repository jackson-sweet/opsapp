//
//  View+ErrorToast.swift
//  OPS
//
//  Bridges a ViewModel error string to the canonical Toast system. Replaces the
//  repeated `.alert("Error", isPresented:)` boilerplate with a single modifier
//  that presents an on-voice error toast and clears the binding.
//
//  Usage:
//    .errorToast($viewModel.error, label: Feedback.Err.operationFailed)
//    .errorToast($viewModel.error, label: Feedback.Err.locationRequired,
//                actionLabel: "OPEN SETTINGS") { openAppSettings() }
//

import SwiftUI

extension View {
    /// FYI error → auto-dismiss error toast. When `trigger` becomes non-nil/
    /// non-empty, presents an error toast with `label` and clears the binding.
    func errorToast(_ trigger: Binding<String?>, label: String) -> some View {
        modifier(ErrorToastModifier(trigger: trigger, label: label, actionLabel: nil, action: nil))
    }

    /// Single-action error → manual-dismiss error toast with a tap-through.
    func errorToast(
        _ trigger: Binding<String?>,
        label: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        modifier(ErrorToastModifier(trigger: trigger, label: label, actionLabel: actionLabel, action: action))
    }
}

private struct ErrorToastModifier: ViewModifier {
    @Binding var trigger: String?
    let label: String
    let actionLabel: String?
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        content.onChange(of: trigger) { _, newValue in
            guard let value = newValue, !value.isEmpty else { return }
            if let actionLabel, let action {
                ToastCenter.shared.present(
                    Toast(label: label, tone: .error, autoDismissAfter: 0,
                          action: ToastAction(label: actionLabel, handler: action)))
            } else {
                ToastCenter.shared.present(Toast(label: label, tone: .error))
            }
            trigger = nil
        }
    }
}
