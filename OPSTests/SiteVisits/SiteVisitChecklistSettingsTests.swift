//
//  SiteVisitChecklistSettingsTests.swift
//  OPSTests
//
//  Reusable checklist-template behavior and the one-time settings guide.
//

import XCTest
@testable import OPS

final class SiteVisitChecklistSettingsTests: XCTestCase {

    func test_legacyFieldJSONDecodesAsVisible() throws {
        let data = Data(
            #"[{"id":"scope","label":"Scope","kind":"long_text","required":true,"sortOrder":10}]"#.utf8
        )

        let fields = try JSONDecoder().decode(
            [SiteVisitTypeFieldDefinition].self,
            from: data
        )

        XCTAssertEqual(fields.count, 1)
        XCTAssertTrue(fields[0].isShown)
    }

    func test_answerSnapshotsExcludeHiddenTemplateFields() {
        let type = SiteVisitType(
            companyId: "company-1",
            slug: "inspection",
            name: "Inspection",
            fields: [
                .init(
                    id: "visible",
                    label: "Visible field",
                    kind: .shortText,
                    isVisible: true,
                    sortOrder: 10
                ),
                .init(
                    id: "hidden",
                    label: "Hidden field",
                    kind: .longText,
                    required: true,
                    isVisible: false,
                    sortOrder: 20
                )
            ]
        )

        let answers = SiteVisitChecklistAnswer.makeAnswers(
            for: type,
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: nil,
            createdBy: "user-1"
        )

        XCTAssertEqual(answers.map(\.fieldId), ["visible"])
    }

    func test_builtinReconciliationPreservesCompanyChoicesAndAddsNewFields() {
        let existing: [SiteVisitTypeFieldDefinition] = [
            .init(
                id: "scope",
                label: "Old app label",
                kind: .shortText,
                required: false,
                isVisible: false,
                sortOrder: 90
            ),
            .init(
                id: "company-field",
                label: "Permit number",
                kind: .shortText,
                required: true,
                isVisible: true,
                sortOrder: 20
            )
        ]
        let canonical: [SiteVisitTypeFieldDefinition] = [
            .init(
                id: "scope",
                label: "Scope of work",
                kind: .longText,
                required: true,
                sortOrder: 10
            ),
            .init(
                id: "photos",
                label: "Site photos",
                kind: .photo,
                sortOrder: 20
            )
        ]

        let reconciled = SiteVisitTypeTemplateReconciler.reconciledFields(
            existing: existing,
            canonical: canonical
        )

        let scope = reconciled.first { $0.id == "scope" }
        XCTAssertEqual(scope?.label, "Scope of work")
        XCTAssertEqual(scope?.kind, .longText)
        XCTAssertEqual(scope?.required, false)
        XCTAssertEqual(scope?.isShown, false)
        XCTAssertEqual(scope?.sortOrder, 90)
        XCTAssertNotNil(reconciled.first { $0.id == "company-field" })
        XCTAssertNotNil(reconciled.first { $0.id == "photos" })
    }

    func test_guideSuppressionIsScopedToTheCurrentUser() {
        let suiteName = "ops.tests.site-visit-checklist-guide.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SiteVisitChecklistGuideStore(defaults: defaults)

        XCTAssertTrue(store.shouldPresent(userId: "user-a"))
        store.suppress(userId: "user-a")

        XCTAssertFalse(store.shouldPresent(userId: "user-a"))
        XCTAssertTrue(store.shouldPresent(userId: "user-b"))
    }

    func test_fieldNormalizationClearsRequiredWhenHiddenAndReorders() throws {
        let fields: [SiteVisitTypeFieldDefinition] = [
            .init(
                id: "hidden",
                label: "  Gate access  ",
                kind: .shortText,
                required: true,
                helpText: "  Code or lockbox  ",
                isVisible: false,
                sortOrder: 90
            ),
            .init(
                id: "shown",
                label: "Site photos",
                kind: .photo,
                sortOrder: 5
            )
        ]

        let normalized = try SiteVisitTypeSettingsLogic.normalizedFields(fields)

        XCTAssertEqual(normalized.map(\.sortOrder), [10, 20])
        XCTAssertEqual(normalized[0].label, "Gate access")
        XCTAssertEqual(normalized[0].helpText, "Code or lockbox")
        XCTAssertFalse(normalized[0].required)
        XCTAssertFalse(normalized[0].isShown)
        XCTAssertTrue(normalized[1].isShown)
    }

    func test_fieldNormalizationRejectsAChecklistWithEverythingHidden() {
        let fields: [SiteVisitTypeFieldDefinition] = [
            .init(
                id: "hidden",
                label: "Hidden field",
                kind: .shortText,
                isVisible: false,
                sortOrder: 10
            )
        ]

        XCTAssertThrowsError(
            try SiteVisitTypeSettingsLogic.normalizedFields(fields)
        ) { error in
            XCTAssertEqual(
                error as? SiteVisitTypeSettingsError,
                .visibleFieldRequired
            )
        }
    }

    func test_fieldNormalizationRejectsMoreThanTheServerLimit() {
        let fields = (0...SiteVisitTypeSettingsLogic.maximumFieldCount).map {
            SiteVisitTypeFieldDefinition(
                id: "field-\($0)",
                label: "Field \($0)",
                kind: .shortText,
                sortOrder: $0 * 10
            )
        }

        XCTAssertThrowsError(
            try SiteVisitTypeSettingsLogic.normalizedFields(fields)
        ) { error in
            XCTAssertEqual(
                error as? SiteVisitTypeSettingsError,
                .fieldLimitReached
            )
        }
    }

    func test_textLimitsMatchTheDatabaseContract() throws {
        XCTAssertEqual(
            try SiteVisitTypeSettingsLogic.normalizedName("  Inspection  "),
            "Inspection"
        )
        XCTAssertNil(
            try SiteVisitTypeSettingsLogic.normalizedDescription("   ")
        )
        XCTAssertThrowsError(
            try SiteVisitTypeSettingsLogic.normalizedName(
                String(repeating: "n", count: 121)
            )
        ) { error in
            XCTAssertEqual(error as? SiteVisitTypeSettingsError, .nameTooLong)
        }
        XCTAssertThrowsError(
            try SiteVisitTypeSettingsLogic.normalizedDescription(
                String(repeating: "d", count: 501)
            )
        ) { error in
            XCTAssertEqual(
                error as? SiteVisitTypeSettingsError,
                .descriptionTooLong
            )
        }
    }
}
