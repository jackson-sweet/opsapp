import SwiftUI

struct DeleteConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let itemName: String
    let message: String?
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Delete \(itemName)?", isPresented: $isPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: onConfirm)
            } message: {
                Text(message ?? "This will permanently delete this \(itemName.lowercased()). This action cannot be undone.")
            }
    }
}

extension View {
    func deleteConfirmation(
        isPresented: Binding<Bool>,
        itemName: String,
        message: String? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DeleteConfirmationModifier(
            isPresented: isPresented,
            itemName: itemName,
            message: message,
            onConfirm: onConfirm
        ))
    }
}
