//
//  SiteVisitContactImportUITests.swift
//  OPSUITests
//
//  Regression proof for bug 5d5df5b0 — importing a device contact during a site
//  visit tore the whole visit down and left an empty intake form behind.
//
//  This drives the REAL CNContactPickerViewController against the DEBUG QA host
//  (SiteVisitCaptureQAHost), which presents the REAL capture console in the REAL
//  `.fullScreenCover` shape. The fault was UIKit's imperative
//  `picker.dismiss(animated:)` walking up the presentation chain past the
//  already-retiring picker sheet and landing on the cover, so nothing short of
//  the real picker in the real presentation reproduces it.
//
//  The assertion is simple and brutal: after a contact is picked, the capture
//  console must still be on screen and the intake fields must carry the contact.
//

import XCTest

final class SiteVisitContactImportUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-OPS_SITE_VISIT_CAPTURE_QA"]
        app.launch()
        XCTAssertTrue(
            startVisitButton.waitForExistence(timeout: 30),
            "QA host did not render"
        )
        try provisionSeededContact()
        XCTAssertTrue(
            app.staticTexts["OPERATOR · qa_site_visit_company"].waitForExistence(timeout: 30),
            "the QA operator never took hold — the console would sit on its spinner"
        )
    }

    /// The QA host seeds the picker's contact through `CNContactStore`, which
    /// needs the contacts privacy grant. Self-provision it: answer the system
    /// permission prompt when it appears. When the simulator's TCC store
    /// already remembers a denial — or the address-book write fails — skip
    /// cleanly with the reset recipe. Provisioning gaps are harness state,
    /// never a product red.
    ///
    /// The iOS 26 contacts prompt is a two-step card — "Continue" first, then
    /// "Allow Full Access" — and it can host either in-app or on SpringBoard,
    /// so both surfaces are polled. On the FIRST boot of a freshly-created
    /// simulator the card can take ~2 minutes to appear while the ContactsUI
    /// machinery warms up, hence the generous deadline (the loop exits the
    /// moment seeding lands, so a warm simulator pays none of it).
    private func provisionSeededContact() throws {
        let setupRecipe = """
        reset the simulator's contacts privacy state and rerun:
          xcrun simctl privacy booted reset contacts co.opsapp.ops.OPS
        (or pre-grant: xcrun simctl privacy booted grant contacts co.opsapp.ops.OPS)
        """
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let stateLabel = app.descendants(matching: .any)
            .matching(identifier: "qa_contacts_state").firstMatch

        // "Continue" advances the two-step card; "Share All N Contacts" (the
        // count varies) grants full access on the iOS 26 second step, and
        // "Allow…" covers older single-step alerts. Never "Don't Allow"
        // (starts with "Don"), never "Select Contacts" (the seeded person
        // must be fully visible to the picker).
        let advancePredicate = NSPredicate(
            format: "label BEGINSWITH[c] 'Allow' OR label ==[c] 'Continue' OR label BEGINSWITH[c] 'Share All'"
        )

        let deadline = Date(timeIntervalSinceNow: 150)
        while Date() < deadline {
            if contactsSeeded.exists { return }
            if stateLabel.exists {
                let state = stateLabel.label
                if state.contains("DENIED") {
                    throw XCTSkip("contacts access is denied for the bundle — \(setupRecipe)")
                }
                if state.contains("SEED FAILED") {
                    throw XCTSkip("the address-book write failed — erase the simulator or \(setupRecipe)")
                }
            }
            let surfaces: [XCUIApplication] = [springboard, app]
            for surface in surfaces {
                let advance = surface.buttons.matching(advancePredicate).firstMatch
                if advance.exists {
                    advance.tap()
                    break
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        }
        // Leave evidence for whoever reads the skip: what each surface was
        // actually showing when the deadline expired.
        print("SPRINGBOARD AT TIMEOUT:\n\(springboard.debugDescription)")
        print("APP AT TIMEOUT:\n\(app.debugDescription)")
        throw XCTSkip("the contacts permission prompt never resolved — \(setupRecipe)")
    }

    // MARK: - Elements

    private var startVisitButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "qa_start_visit").firstMatch
    }

    private var contactsSeeded: XCUIElement {
        app.staticTexts["CONTACTS · SEEDED"]
    }

    private var visitStateLabel: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "qa_visit_state").firstMatch
    }

    /// The identity panel's header — present only while the capture console is.
    private var captureConsoleMarker: XCUIElement {
        app.buttons["Lead and client details"]
    }

    private var importContactsButton: XCUIElement {
        app.buttons["Import from phone contacts"]
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openVisit() {
        XCTAssertEqual(visitStateLabel.label, "VISIT CLOSED")
        startVisitButton.tap()
        XCTAssertTrue(
            captureConsoleMarker.waitForExistence(timeout: 20),
            "the capture console never presented"
        )
        attach("01-visit-presented")
    }

    /// Taps the seeded person inside the real contact picker.
    private func pickSeededContact() {
        XCTAssertTrue(importContactsButton.waitForExistence(timeout: 10), "IMPORT FROM CONTACTS missing")
        importContactsButton.tap()

        let corinne = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Corinne")
        ).firstMatch
        XCTAssertTrue(corinne.waitForExistence(timeout: 20), "the contact picker never listed the seeded contact")
        attach("02-contact-picker")
        corinne.tap()
    }

    // MARK: - Tests

    /// THE BUG: picking a contact must fill the form and leave the visit standing.
    func testImportingAContactKeepsTheVisitPresentedAndFillsTheForm() {
        openVisit()
        pickSeededContact()

        XCTAssertTrue(
            captureConsoleMarker.waitForExistence(timeout: 10),
            "bug 5d5df5b0 — the contact import tore the site visit down"
        )
        attach("03-after-import")

        let filled = app.textFields.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "Corinne Robertson")
        ).firstMatch
        XCTAssertTrue(
            filled.waitForExistence(timeout: 10),
            "the intake form came back empty after the import"
        )

        let addressFilled = app.textFields.containing(
            NSPredicate(format: "value CONTAINS[c] %@", "Lyall")
        ).firstMatch
        XCTAssertTrue(addressFilled.exists, "the picked postal address did not reach the form")
    }

    /// Cancelling the picker must also leave the visit standing — the cancel path
    /// carried the same triple-dismissal.
    func testCancellingTheContactPickerKeepsTheVisitPresented() {
        openVisit()
        XCTAssertTrue(importContactsButton.waitForExistence(timeout: 10))
        importContactsButton.tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "the contact picker never presented")
        cancel.tap()

        XCTAssertTrue(
            captureConsoleMarker.waitForExistence(timeout: 10),
            "cancelling the picker tore the site visit down"
        )
        attach("04-after-cancel")
    }
}
