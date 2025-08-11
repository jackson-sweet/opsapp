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
    let onDismiss: (() -> Void)?
    
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
            picker.dismiss(animated: true) { [weak self] in
                self?.parent.onDismiss?()
            }
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.parent.onDismiss?()
            }
        }
    }
}