import XCTest
@testable import OPSDecks

final class CompanyOfOneProvisionerTests: XCTestCase {
    func testBrandNewUserCreatesDeckCompanyAndLinkedAdminUser() {
        let provisioner = CompanyOfOneProvisioner(
            companyIdGenerator: { "co-new" },
            userIdGenerator: { "u-new" }
        )

        let plan = provisioner.plan(
            for: AppleIdentity(
                sub: "fb-123",
                email: "deck@example.com",
                fullName: "Dana Lee"
            ),
            existingUser: nil
        )

        XCTAssertEqual(plan.createCompany?.id, "co-new")
        XCTAssertEqual(plan.createCompany?.name, "Dana Lee")
        XCTAssertEqual(plan.createCompany?.adminIds, ["u-new"])
        XCTAssertEqual(plan.createCompany?.subscriptionPlan, "decks")
        XCTAssertEqual(plan.createUser?.id, "u-new")
        XCTAssertEqual(plan.createUser?.firebaseUid, "fb-123")
        XCTAssertEqual(plan.createUser?.authId, "fb-123")
        XCTAssertEqual(plan.createUser?.companyId, "co-new")
        XCTAssertEqual(plan.createUser?.role, "admin")
        XCTAssertNil(plan.attachToCompanyId)
        XCTAssertEqual(plan.resolvedCompanyId, "co-new")
    }

    func testExistingLinkedUserIsNoOp() {
        let provisioner = CompanyOfOneProvisioner(
            companyIdGenerator: { "co-unused" },
            userIdGenerator: { "u-unused" }
        )
        let existingUser = UsersRow(
            id: "u-existing",
            firebaseUid: "fb-123",
            companyId: "co-existing"
        )

        let plan = provisioner.plan(
            for: AppleIdentity(sub: "fb-123"),
            existingUser: existingUser
        )

        XCTAssertNil(plan.createCompany)
        XCTAssertNil(plan.createUser)
        XCTAssertNil(plan.attachToCompanyId)
        XCTAssertEqual(plan.resolvedCompanyId, "co-existing")
    }

    func testExistingUserWithoutCompanyIsAttachedToNewDeckCompany() {
        let provisioner = CompanyOfOneProvisioner(
            companyIdGenerator: { "co-new" },
            userIdGenerator: { "u-unused" }
        )
        let existingUser = UsersRow(
            id: "u-existing",
            firebaseUid: "fb-123",
            companyId: nil
        )

        let plan = provisioner.plan(
            for: AppleIdentity(
                sub: "fb-123",
                email: nil,
                fullName: "Dana Lee"
            ),
            existingUser: existingUser
        )

        XCTAssertEqual(plan.createCompany?.id, "co-new")
        XCTAssertEqual(plan.createCompany?.adminIds, ["u-existing"])
        XCTAssertEqual(plan.createCompany?.subscriptionPlan, "decks")
        XCTAssertNil(plan.createUser)
        XCTAssertEqual(plan.attachToCompanyId, "co-new")
        XCTAssertEqual(plan.resolvedCompanyId, "co-new")
    }

    func testCompanyNameDefaultsToNameThenMyDecks() {
        let provisioner = CompanyOfOneProvisioner(
            companyIdGenerator: { "co-new" },
            userIdGenerator: { "u-new" }
        )

        let namedPlan = provisioner.plan(
            for: AppleIdentity(sub: "fb-123", fullName: "  Dana Lee  "),
            existingUser: nil
        )
        let fallbackPlan = provisioner.plan(
            for: AppleIdentity(sub: "fb-456", fullName: "   "),
            existingUser: nil
        )

        XCTAssertEqual(namedPlan.createCompany?.name, "Dana Lee")
        XCTAssertEqual(fallbackPlan.createCompany?.name, "My Decks")
    }
}
