//
//  ContactPicker.swift
//  OPS
//
//  UIKit bridge for accessing device contacts.
//
//  Bug 5d5df5b0 — importing a contact during a site visit tore the whole visit
//  down and left an empty intake form behind.
//
//  Root cause: the picker used to be SwiftUI `.sheet` content.
//  `CNContactPickerViewController` retires ITSELF once the user picks or
//  cancels, so SwiftUI is left holding a binding that still says "presented".
//  Flipping that binding afterwards makes SwiftUI dismiss a modal UIKit has
//  already taken down — and that dismissal lands on the NEXT modal up the chain.
//  During a site visit the next modal up is the whole capture console
//  (a `.fullScreenCover`), so the visit vanished. It is timing-dependent, which
//  is why picking almost always killed it and cancelling sometimes did.
//
//  Fix: the picker never enters SwiftUI's modal stack. This view is an invisible
//  anchor that presents and dismisses the picker through UIKit, and the binding
//  is a plain flag SwiftUI never acts on. SwiftUI cannot dismiss a modal it
//  never presented.
//
//  Usage — attach as a zero-size background, NEVER as `.sheet` content:
//
//      .background(
//          ContactPicker(isPresented: $showingContactPicker) { contact in … }
//      )
//

import SwiftUI
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onContactSelected: (CNContact) -> Void

    func makeUIViewController(context: Context) -> AnchorViewController {
        let anchor = AnchorViewController()
        // SwiftUI can run `updateUIViewController` before this anchor is in a
        // window, and a controller with no window cannot present. Retry the
        // moment it lands.
        anchor.onWindowChange = { [weak anchor] in
            guard let anchor else { return }
            context.coordinator.presentIfRequested(from: anchor)
        }
        return anchor
    }

    func updateUIViewController(_ anchor: AnchorViewController, context: Context) {
        context.coordinator.parent = self
        if isPresented {
            context.coordinator.requestPresentation(from: anchor)
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }

    /// Invisible, non-interactive anchor whose only job is to own the picker's
    /// UIKit presentation and to say when it is attached to a window.
    final class AnchorViewController: UIViewController {
        var onWindowChange: (() -> Void)?

        override func loadView() {
            let anchorView = AnchorView()
            anchorView.backgroundColor = .clear
            anchorView.isUserInteractionEnabled = false
            anchorView.onWindowChange = { [weak self] in self?.onWindowChange?() }
            view = anchorView
        }
    }

    private final class AnchorView: UIView {
        var onWindowChange: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            onWindowChange?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker
        private weak var presentedPicker: CNContactPickerViewController?
        private var isPresenting = false
        private var presentationRequested = false

        init(_ parent: ContactPicker) {
            self.parent = parent
        }

        /// The caller asked for the picker. It goes up as soon as the anchor is
        /// in a window — which may be now, or may be a layout pass later.
        func requestPresentation(from anchor: UIViewController) {
            presentationRequested = true
            presentIfRequested(from: anchor)
        }

        func presentIfRequested(from anchor: UIViewController) {
            guard presentationRequested else { return }
            present(from: anchor)
        }

        private func present(from anchor: UIViewController) {
            guard presentedPicker == nil, !isPresenting else { return }
            guard anchor.view.window != nil else { return }

            let picker = CNContactPickerViewController()
            picker.delegate = self

            // Which properties the picker shows on a contact's card.
            picker.displayedPropertyKeys = [
                CNContactGivenNameKey,
                CNContactFamilyNameKey,
                CNContactEmailAddressesKey,
                CNContactPhoneNumbersKey,
                CNContactPostalAddressesKey,
                CNContactJobTitleKey,
                CNContactOrganizationNameKey
            ]

            presentedPicker = picker
            isPresenting = true
            anchor.present(picker, animated: true) { [weak self] in
                self?.isPresenting = false
            }
        }

        /// Only for a programmatic close — after a pick or a cancel the picker
        /// has already retired itself and `presentedPicker` is nil.
        func dismissIfNeeded() {
            presentationRequested = false
            guard let picker = presentedPicker else { return }
            presentedPicker = nil
            picker.presentingViewController?.dismiss(animated: true)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            finish(with: contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            finish(with: nil)
        }

        /// UIKit has already taken the picker down. Sync the flag — which
        /// dismisses nothing, because SwiftUI never presented anything — then
        /// hand the contact over on the next runloop turn, so the caller's state
        /// write lands after the transition rather than inside it.
        private func finish(with contact: CNContact?) {
            presentedPicker = nil
            presentationRequested = false
            parent.isPresented = false
            guard let contact else { return }
            let deliver = parent.onContactSelected
            DispatchQueue.main.async { deliver(contact) }
        }
    }
}
