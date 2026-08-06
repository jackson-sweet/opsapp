//
//  PassthroughToastWindowTests.swift
//  OPSTests
//
//  Regression coverage for the dedicated toast window's hit-testing contract.
//  The window may capture the visible toast, but its transparent full-screen
//  background must never block the app underneath.
//

import UIKit
import XCTest
@testable import OPS

@MainActor
final class PassthroughToastWindowTests: XCTestCase {
    private var center: ToastCenter { ToastCenter.shared }

    override func setUp() {
        super.setUp()
        center.reset()
    }

    override func tearDown() {
        center.reset()
        super.tearDown()
    }

    func testBackgroundPassesThroughWhileToastIsVisible() {
        let (window, _, button) = makeWindow()
        window.interactionRegionView = button
        center.present(Toast(label: "// SAVED", tone: .success, autoDismissAfter: 0))

        let hitView = window.hitTest(CGPoint(x: 160, y: 500), with: nil)

        XCTAssertNil(hitView, "The transparent toast window background must not block the app below it")
    }

    func testInteractiveToastContentStillReceivesTouches() {
        let (window, _, button) = makeWindow()
        window.interactionRegionView = button
        center.present(Toast(label: "// SAVED", tone: .success, autoDismissAfter: 0))

        let hitView = window.hitTest(CGPoint(x: 160, y: 70), with: nil)

        XCTAssertTrue(hitView === button, "The visible toast control must remain tappable")
    }

    private func makeWindow() -> (PassthroughToastWindow, UIView, UIButton) {
        let window = PassthroughToastWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let rootViewController = UIViewController()
        rootViewController.view.frame = window.bounds
        rootViewController.view.backgroundColor = .clear
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 80, y: 40, width: 160, height: 60)
        rootViewController.view.addSubview(button)
        window.rootViewController = rootViewController
        window.isHidden = false
        window.layoutIfNeeded()
        return (window, rootViewController.view, button)
    }
}
