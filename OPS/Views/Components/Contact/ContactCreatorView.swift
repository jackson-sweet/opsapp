//
//  ContactCreatorView.swift
//  OPS
//
//  Creates a new contact in the device's address book
//

import SwiftUI
import Contacts
import ContactsUI

struct ContactCreatorView: UIViewControllerRepresentable {
    let name: String
    let email: String?
    let phone: String?
    let address: String?
    let jobTitle: String?
    let organization: String?
    
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        
        // Parse name into components
        let nameComponents = name.components(separatedBy: " ")
        if !nameComponents.isEmpty {
            contact.givenName = nameComponents.first ?? ""
            if nameComponents.count > 1 {
                contact.familyName = nameComponents.dropFirst().joined(separator: " ")
            }
        }
        
        // Add email if available
        if let email = email, !email.isEmpty {
            let emailAddress = CNLabeledValue(
                label: CNLabelWork,
                value: email as NSString
            )
            contact.emailAddresses = [emailAddress]
        }
        
        // Add phone if available
        if let phone = phone, !phone.isEmpty {
            let phoneNumber = CNLabeledValue(
                label: CNLabelPhoneNumberMain,
                value: CNPhoneNumber(stringValue: phone)
            )
            contact.phoneNumbers = [phoneNumber]
        }
        
        // Add address if available
        if let address = address, !address.isEmpty {
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
            
            let homeAddress = CNLabeledValue(
                label: CNLabelWork,
                value: postalAddress as CNPostalAddress
            )
            contact.postalAddresses = [homeAddress]
        }
        
        // Add job title if available
        if let jobTitle = jobTitle, !jobTitle.isEmpty {
            contact.jobTitle = jobTitle
        }
        
        // Add organization if available
        if let organization = organization, !organization.isEmpty {
            contact.organizationName = organization
        }
        
        // Create the contact view controller
        let contactViewController = CNContactViewController(forNewContact: contact)
        contactViewController.delegate = context.coordinator
        
        // Wrap in navigation controller
        let navigationController = UINavigationController(rootViewController: contactViewController)
        
        return navigationController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CNContactViewControllerDelegate {
        let parent: ContactCreatorView
        
        init(_ parent: ContactCreatorView) {
            self.parent = parent
        }
        
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}