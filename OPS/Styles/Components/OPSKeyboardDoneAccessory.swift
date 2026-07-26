//
//  OPSKeyboardDoneAccessory.swift
//  OPS
//
//  App-wide keyboard dismissal policy. SwiftUI's keyboard toolbar preference
//  does not cross every sheet, cover, or overlay-window boundary, but its text
//  inputs resolve to UITextField / UITextView on the supported deployment
//  target. Installing the accessory at that UIKit boundary guarantees one
//  canonical DONE action everywhere.
//

import UIKit

@MainActor
final class OPSKeyboardDoneAccessoryView: UIToolbar {
    private weak var editingResponder: UIResponder?

    init(editingResponder: UIResponder) {
        self.editingResponder = editingResponder

        super.init(frame: CGRect(
            x: .zero,
            y: .zero,
            width: .zero,
            height: OPSStyle.Layout.touchTargetMin
        ))

        barStyle = .black
        isTranslucent = true
        autoresizingMask = [.flexibleWidth]
        tintColor = UIColor(OPSStyle.Colors.primaryText)

        let doneItem = UIBarButtonItem(
            title: "DONE",
            style: .plain,
            target: self,
            action: #selector(dismissKeyboard)
        )
        doneItem.accessibilityLabel = "Done"
        doneItem.accessibilityIdentifier = "ops.keyboard.done"
        doneItem.setTitleTextAttributes(
            [
                .font: OPSStyle.Typography.uiButtonLabel,
                .foregroundColor: UIColor(OPSStyle.Colors.primaryText)
            ],
            for: .normal
        )

        items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            doneItem
        ]
    }

    required init?(coder: NSCoder) {
        return nil
    }

    @objc private func dismissKeyboard() {
        editingResponder?.resignFirstResponder()
    }
}

@MainActor
final class OPSKeyboardDoneAccessoryCoordinator: NSObject {
    static let shared = OPSKeyboardDoneAccessoryCoordinator()

    private let notificationCenter: NotificationCenter
    private var isStarted = false

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        notificationCenter.addObserver(
            self,
            selector: #selector(textFieldDidBeginEditing(_:)),
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(textViewDidBeginEditing(_:)),
            name: UITextView.textDidBeginEditingNotification,
            object: nil
        )
    }

    func stop() {
        guard isStarted else { return }
        notificationCenter.removeObserver(
            self,
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        notificationCenter.removeObserver(
            self,
            name: UITextView.textDidBeginEditingNotification,
            object: nil
        )
        isStarted = false
    }

    @objc private func textFieldDidBeginEditing(_ notification: Notification) {
        guard let textField = notification.object as? UITextField else { return }
        installAccessoryIfNeeded(on: textField)
    }

    @objc private func textViewDidBeginEditing(_ notification: Notification) {
        guard let textView = notification.object as? UITextView else { return }
        installAccessoryIfNeeded(on: textView)
    }

    private func installAccessoryIfNeeded(on textField: UITextField) {
        guard !(textField.inputAccessoryView is OPSKeyboardDoneAccessoryView) else {
            return
        }

        textField.inputAccessoryView = OPSKeyboardDoneAccessoryView(
            editingResponder: textField
        )
        if textField.isFirstResponder {
            textField.reloadInputViews()
        }
    }

    private func installAccessoryIfNeeded(on textView: UITextView) {
        guard !(textView.inputAccessoryView is OPSKeyboardDoneAccessoryView) else {
            return
        }

        textView.inputAccessoryView = OPSKeyboardDoneAccessoryView(
            editingResponder: textView
        )
        if textView.isFirstResponder {
            textView.reloadInputViews()
        }
    }
}
