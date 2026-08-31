//
//  ContactLeadFillTests.swift
//  OPSTests
//
//  Bugs f8951223 / 55f40233 — one mapping from a picked CNContact to lead-form
//  fields, shared by the booking picker's inline form and AddLeadSheet.
//
//  The contract under test is FILL, never create: a pick writes only the
//  fields the contact actually carries, so a partly typed form is never wiped,
//  and no Client / Opportunity row is minted until the operator commits.
//

import Contacts
import XCTest
@testable import OPS

@MainActor
final class ContactLeadFillTests: XCTestCase {

    // MARK: - Fixtures

    private func makeContact(
        given: String = "Dana",
        family: String = "Rowe",
        organization: String = "",
        phone: String? = "250-555-0199",
        email: String? = "dana@example.com",
        street: String? = "18 Alder Way",
        city: String = "Squamish",
        state: String = "BC",
        postalCode: String = "V8B 0A1"
    ) -> CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = given
        contact.familyName = family
        contact.organizationName = organization
        if let phone {
            contact.phoneNumbers = [
                CNLabeledValue(
                    label: CNLabelPhoneNumberMain,
                    value: CNPhoneNumber(stringValue: phone)
                )
            ]
        }
        if let email {
            contact.emailAddresses = [
                CNLabeledValue(label: CNLabelHome, value: email as NSString)
            ]
        }
        if let street {
            let postal = CNMutablePostalAddress()
            postal.street = street
            postal.city = city
            postal.state = state
            postal.postalCode = postalCode
            // The cast is required: CNLabeledValue is invariant in its Value,
            // so a CNMutablePostalAddress element will not convert implicitly.
            contact.postalAddresses = [
                CNLabeledValue(label: CNLabelHome, value: postal as CNPostalAddress)
            ]
        }
        return contact
    }

    // MARK: - Mapping

    /// A full contact maps every field, and the address arrives as the same
    /// comma-canonical single line AddressAutocompleteField emits — so an
    /// imported address and a picked one are indistinguishable downstream.
    func testFillMapsNamePhoneEmailAddress() {
        let fill = ContactLeadFill.from(makeContact())

        XCTAssertEqual(fill.name, "Dana Rowe")
        XCTAssertEqual(fill.phone, "250-555-0199")
        XCTAssertEqual(fill.email, "dana@example.com")
        XCTAssertEqual(fill.address, "18 Alder Way, Squamish, BC, V8B 0A1")
    }

    /// A business card with no personal name still yields a usable lead name.
    func testFillFallsBackToOrganizationName() {
        let fill = ContactLeadFill.from(
            makeContact(given: "", family: "", organization: "West Shore Decks")
        )

        XCTAssertEqual(fill.name, "West Shore Decks")
    }

    /// An empty contact carries nothing, so applying it is a no-op — the
    /// operator's typed values survive a mis-tap in the picker.
    func testEmptyContactProducesAllNils() {
        let fill = ContactLeadFill.from(
            makeContact(
                given: "", family: "", organization: "",
                phone: nil, email: nil, street: nil
            )
        )

        XCTAssertNil(fill.name)
        XCTAssertNil(fill.phone)
        XCTAssertNil(fill.email)
        XCTAssertNil(fill.address)

        var name = "Typed Name"
        var phone = "555-0100"
        var email = "typed@example.com"
        fill.apply(name: &name, phone: &phone, email: &email)

        XCTAssertEqual(name, "Typed Name")
        XCTAssertEqual(phone, "555-0100")
        XCTAssertEqual(email, "typed@example.com")
    }

    // MARK: - apply(into three independent strings)

    /// Only the carried fields overwrite. This is the whole point: importing a
    /// contact that has just a phone number must not blank a name the operator
    /// already typed.
    func testApplyOverwritesOnlyCarriedFields() {
        let fill = ContactLeadFill.from(
            makeContact(given: "", family: "", organization: "", email: nil, street: nil)
        )

        var name = "Typed Name"
        var phone = "555-0100"
        var email = "typed@example.com"
        fill.apply(name: &name, phone: &phone, email: &email)

        XCTAssertEqual(name, "Typed Name", "no name on the contact ⇒ typed name survives")
        XCTAssertEqual(phone, "250-555-0199", "the carried phone wins")
        XCTAssertEqual(email, "typed@example.com", "no email on the contact ⇒ typed email survives")
    }

    // MARK: - applied(to: LeadForm)

    /// Identity fields adopt the contact; JOB fields stay the operator's. The
    /// address overwrite must also drop stale coordinates — imported text owns
    /// no coordinates, and writing a lead whose lat/lng points somewhere else
    /// would send a crew to the wrong site.
    func testAppliedToFormOverwritesCarriedFieldsAndDropsCoords() {
        var form = LeadForm()
        form.title = "Cedar deck rebuild"
        form.estimatedValue = "12,500"
        form.notes = "Called Tuesday"
        form.address = "99 Old Street, Vancouver, BC"
        form.addressResolved("99 Old Street, Vancouver, BC", latitude: 49.28, longitude: -123.12)
        XCTAssertNotNil(form.latitude, "precondition: the form starts with resolved coords")

        let updated = ContactLeadFill.from(makeContact()).applied(to: form)

        // Identity adopted
        XCTAssertEqual(updated.contactName, "Dana Rowe")
        XCTAssertEqual(updated.phone, "250-555-0199")
        XCTAssertEqual(updated.email, "dana@example.com")
        XCTAssertEqual(updated.address, "18 Alder Way, Squamish, BC, V8B 0A1")

        // Job fields untouched
        XCTAssertEqual(updated.title, "Cedar deck rebuild")
        XCTAssertEqual(updated.estimatedValue, "12,500")
        XCTAssertEqual(updated.notes, "Called Tuesday")

        // Stale coords dropped by the form's own divergence rule
        XCTAssertNil(updated.latitude, "imported address text owns no coordinates")
        XCTAssertNil(updated.longitude)
    }

    /// A contact with no postal address leaves the form's address — and the
    /// coordinates that belong to it — completely alone.
    func testAppliedToFormLeavesAddressAndCoordsWhenContactHasNoAddress() {
        var form = LeadForm()
        form.address = "99 Old Street, Vancouver, BC"
        form.addressResolved("99 Old Street, Vancouver, BC", latitude: 49.28, longitude: -123.12)

        let updated = ContactLeadFill.from(makeContact(street: nil)).applied(to: form)

        XCTAssertEqual(updated.address, "99 Old Street, Vancouver, BC")
        XCTAssertEqual(updated.latitude, 49.28)
        XCTAssertEqual(updated.longitude, -123.12)
        XCTAssertEqual(updated.contactName, "Dana Rowe", "identity still fills")
    }

    /// An empty contact applied to a form changes nothing at all.
    func testAppliedToFormWithEmptyContactIsANoOp() {
        var form = LeadForm()
        form.contactName = "Typed Name"
        form.phone = "555-0100"
        form.title = "Cedar deck rebuild"

        let fill = ContactLeadFill.from(
            makeContact(
                given: "", family: "", organization: "",
                phone: nil, email: nil, street: nil
            )
        )
        let updated = fill.applied(to: form)

        XCTAssertEqual(updated.contactName, "Typed Name")
        XCTAssertEqual(updated.phone, "555-0100")
        XCTAssertEqual(updated.title, "Cedar deck rebuild")
        XCTAssertEqual(updated.email, "")
    }

    /// The mapper creates nothing — it is a value, not a write path. Two fills
    /// from the same contact are equal, which is what lets a caller apply one
    /// twice without side effects.
    func testFillIsAPureValue() {
        let contact = makeContact()
        XCTAssertEqual(ContactLeadFill.from(contact), ContactLeadFill.from(contact))
    }
}
