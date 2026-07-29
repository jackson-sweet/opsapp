//
//  ContactPicker.swift
//  OPS
//
//  UIKit bridge for accessing device contacts
//

import SwiftUI
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    let onContactSelected: (CNContact) -> Void

    /// REQUIRED — the presenting view owns dismissal, and nothing else does.
    ///
    /// Bug 5d5df5b0: this bridge used to fire THREE dismissal signals per pick
    /// (the selection handler flipping the caller's binding, an imperative
    /// `picker.dismiss(animated:)`, and the dismiss completion flipping the
    /// binding again). A `CNContactPickerViewController` inside a SwiftUI
    /// `.sheet` is a CHILD of the sheet's host, not a presented controller, so
    /// `dismiss(animated:)` walks UP the presentation chain — and once SwiftUI
    /// has already begun retiring the sheet, that walk lands on whatever modal
    /// sits above it. During a site visit, that was the capture console's
    /// `fullScreenCover`: importing a contact tore down the whole visit.
    ///
    /// One owner. UIKit never dismisses itself here; the binding does.
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        
        // Specify which contact properties we want to fetch
        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey,
            CNContactPostalAddressesKey,
            CNContactJobTitleKey,
            CNContactOrganizationNameKey
        ]
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker
        
        init(_ parent: ContactPicker) {
            self.parent = parent
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onContactSelected(contact)
            parent.onDismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.onDismiss()
        }
    }
}