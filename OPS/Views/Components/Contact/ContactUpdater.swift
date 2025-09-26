//
//  ContactUpdater.swift
//  OPS
//
//  UIKit bridge for adding data to existing contacts
//

import SwiftUI
import Contacts
import ContactsUI

struct ContactUpdater: UIViewControllerRepresentable {
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let jobTitle: String?
    let organization: String?
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
        let parent: ContactUpdater
        
        init(_ parent: ContactUpdater) {
            self.parent = parent
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            // Create a mutable copy of the selected contact
            let mutableContact = contact.mutableCopy() as! CNMutableContact
            
            // Add new data to the contact
            if let email = parent.email, !email.isEmpty {
                let emailAddress = CNLabeledValue(
                    label: CNLabelWork,
                    value: email as NSString
                )
                mutableContact.emailAddresses.append(emailAddress)
            }
            
            if let phone = parent.phone, !phone.isEmpty {
                let phoneNumber = CNLabeledValue(
                    label: CNLabelPhoneNumberMain,
                    value: CNPhoneNumber(stringValue: phone)
                )
                mutableContact.phoneNumbers.append(phoneNumber)
            }
            
            if let address = parent.address, !address.isEmpty {
                let postalAddress = CNMutablePostalAddress()
                
                // Try to parse the address string
                let components = address.components(separatedBy: ", ")
                if components.count > 0 {
                    postalAddress.street = components[0]
                }
                if components.count > 1 {
                    postalAddress.city = components[1]
                }
                if components.count > 2 {
                    postalAddress.state = components[2]
                }
                if components.count > 3 {
                    postalAddress.postalCode = components[3]
                }
                
                let workAddress = CNLabeledValue(
                    label: CNLabelWork,
                    value: postalAddress as CNPostalAddress
                )
                mutableContact.postalAddresses.append(workAddress)
            }
            
            // Update job title if not already set
            if let jobTitle = parent.jobTitle, !jobTitle.isEmpty, mutableContact.jobTitle.isEmpty {
                mutableContact.jobTitle = jobTitle
            }
            
            // Update organization if not already set
            if let organization = parent.organization, !organization.isEmpty, mutableContact.organizationName.isEmpty {
                mutableContact.organizationName = organization
            }
            
            // Save the updated contact
            let store = CNContactStore()
            let saveRequest = CNSaveRequest()
            saveRequest.update(mutableContact)
            
            do {
                try store.execute(saveRequest)
                picker.dismiss(animated: true) { [weak self] in
                    self?.parent.onDismiss?()
                }
            } catch {
                picker.dismiss(animated: true) { [weak self] in
                    self?.parent.onDismiss?()
                }
            }
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.parent.onDismiss?()
            }
        }
    }
}