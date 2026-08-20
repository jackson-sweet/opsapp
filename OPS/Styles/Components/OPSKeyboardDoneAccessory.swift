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
    let doneLabel = UILabel()
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

        doneLabel.translatesAutoresizingMaskIntoConstraints = false
        doneLabel.text = "DONE"
        doneLabel.font = OPSStyle.Typography.uiButtonLabel
        doneLabel.textColor = UIColor(OPSStyle.Colors.primaryText)
        doneLabel.textAlignment = .center
        doneLabel.isUserInteractionEnabled = false

        // DONE is a direct subview, deliberately NOT a UIBarButtonItem. On
        // iOS 26 a bar item is wrapped in a Liquid Glass platter that the
        // toolbar pins to its own fixed ~48pt content band and clips to it.
        // Measured across custom-view heights 36/40/44/48, that platter always
        // began at the band's top edge and overhung the item's bottom by ~5pt
        // — so the visible border sat on the keyboard, was sheared flat on
        // top, and no band height could buy a gutter above it. Owning the
        // layout puts both visible edges under `OPSStyle` control.
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.accessibilityLabel = "Done"
        doneButton.accessibilityIdentifier = "ops.keyboard.done"
        doneButton.backgroundColor = UIColor(OPSStyle.Colors.surfaceHover)
        doneButton.layer.cornerRadius = OPSStyle.Layout.buttonRadius
        doneButton.layer.cornerCurve = .continuous
        doneButton.layer.borderWidth = OPSStyle.Layout.hairlineWidth
        doneButton.layer.borderColor = UIColor(OPSStyle.Colors.line).cgColor
        doneButton.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)

        addSubview(doneButton)
        doneButton.addSubview(doneLabel)
        NSLayoutConstraint.activate([
            // Full-size target, centred in the band so the visible border
            // keeps an equal `spacing1` gutter above and below — the one below
            // being the clearance from the keyboard's top edge.
            doneButton.heightAnchor.constraint(
                equalToConstant: OPSStyle.Layout.touchTargetMin
            ),
            doneButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: OPSStyle.Layout.touchTargetMin
            ),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            doneButton.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -OPSStyle.Layout.spacing3
            ),
            // Optical, not geometric, centring. Centring the label's box would
            // centre a line box that reserves descender space "DONE" never
            // uses, leaving the caps visibly low. Pin the BASELINE instead so
            // the cap-height ink straddles the button's centre exactly; this
            // needs only `capHeight`, so it retunes itself if the type token
            // changes.
            doneLabel.firstBaselineAnchor.constraint(
                equalTo: doneButton.centerYAnchor,
                constant: OPSStyle.Typography.uiButtonLabel.capHeight / 2
            ),
            doneLabel.leadingAnchor.constraint(
                equalTo: doneButton.leadingAnchor,
                constant: OPSStyle.Layout.spacing3
            ),
            doneLabel.trailingAnchor.constraint(
                equalTo: doneButton.trailingAnchor,
                constant: -OPSStyle.Layout.spacing3
            )
        ])

        items = []
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
