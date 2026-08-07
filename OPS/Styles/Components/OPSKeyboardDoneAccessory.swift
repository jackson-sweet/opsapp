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
    private let doneContainer = UIView()
    let doneButton = UIButton(type: .system)

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: OPSStyle.Layout.keyboardAccessoryHeight
        )
    }

    init(editingResponder: UIResponder) {
        self.editingResponder = editingResponder

        super.init(frame: CGRect(
            x: .zero,
            y: .zero,
            width: .zero,
            height: OPSStyle.Layout.keyboardAccessoryHeight
        ))

        barStyle = .black
        isTranslucent = true
        autoresizingMask = [.flexibleWidth]
        tintColor = UIColor(OPSStyle.Colors.primaryText)

        doneContainer.translatesAutoresizingMaskIntoConstraints = false
        doneContainer.isAccessibilityElement = false

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("DONE", for: .normal)
        doneButton.titleLabel?.font = OPSStyle.Typography.uiButtonLabel
        doneButton.setTitleColor(UIColor(OPSStyle.Colors.primaryText), for: .normal)
        doneButton.accessibilityLabel = "Done"
        doneButton.accessibilityIdentifier = "ops.keyboard.done"
        doneButton.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)

        doneContainer.addSubview(doneButton)
        NSLayoutConstraint.activate([
            doneContainer.widthAnchor.constraint(
                greaterThanOrEqualToConstant: OPSStyle.Layout.touchTargetMin
            ),
            doneContainer.heightAnchor.constraint(
                equalToConstant: OPSStyle.Layout.keyboardAccessoryHeight
            ),
            doneButton.leadingAnchor.constraint(equalTo: doneContainer.leadingAnchor),
            doneButton.trailingAnchor.constraint(equalTo: doneContainer.trailingAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: OPSStyle.Layout.touchTargetMin),
            doneButton.bottomAnchor.constraint(
                equalTo: doneContainer.bottomAnchor,
                constant: -OPSStyle.Layout.spacing2
            )
        ])

        let doneItem = UIBarButtonItem(customView: doneContainer)
        // Retain item identity and target/action for UIKit command routing and
        // the existing exactly-once dismissal regression.
        doneItem.title = "DONE"
        doneItem.target = self
        doneItem.action = #selector(dismissKeyboard)
        doneItem.accessibilityLabel = "Done"
        doneItem.accessibilityIdentifier = "ops.keyboard.done"

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

    /// Installs the canonical accessory before a UIKit-backed custom editor
    /// becomes first responder, so its keyboard never needs a mid-focus reload.
    func prepare(_ textField: UITextField) {
        installAccessoryIfNeeded(on: textField, reloadIfActive: false)
    }

    /// Installs the canonical accessory before a UIKit-backed custom editor
    /// becomes first responder, so its keyboard never needs a mid-focus reload.
    func prepare(_ textView: UITextView) {
        installAccessoryIfNeeded(on: textView, reloadIfActive: false)
    }

    @objc private func textFieldDidBeginEditing(_ notification: Notification) {
        guard let textField = notification.object as? UITextField else { return }
        installAccessoryIfNeeded(on: textField, reloadIfActive: true)
    }

    @objc private func textViewDidBeginEditing(_ notification: Notification) {
        guard let textView = notification.object as? UITextView else { return }
        installAccessoryIfNeeded(on: textView, reloadIfActive: true)
    }

    private func installAccessoryIfNeeded(
        on textField: UITextField,
        reloadIfActive: Bool
    ) {
        guard !(textField.inputAccessoryView is OPSKeyboardDoneAccessoryView) else {
            return
        }

        textField.inputAccessoryView = OPSKeyboardDoneAccessoryView(
            editingResponder: textField
        )
        if reloadIfActive, textField.isFirstResponder {
            textField.reloadInputViews()
        }
    }

    private func installAccessoryIfNeeded(
        on textView: UITextView,
        reloadIfActive: Bool
    ) {
        guard !(textView.inputAccessoryView is OPSKeyboardDoneAccessoryView) else {
            return
        }

        textView.inputAccessoryView = OPSKeyboardDoneAccessoryView(
            editingResponder: textView
        )
        if reloadIfActive, textView.isFirstResponder {
            textView.reloadInputViews()
        }
    }
}
