import SwiftUI

struct DeleteConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let itemName: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete \(itemName)?",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onConfirm)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
    }
}

extension View {
    func deleteConfirmation(
        isPresented: Binding<Bool>,
        itemName: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(DeleteConfirmationModifier(
            isPresented: isPresented,
            itemName: itemName,
            onConfirm: onConfirm
        ))
    }
}
