//
//  ProjectDetailsTitleUpdateTests.swift
//  OPSTests
//
//  Regression coverage for project-detail title saves on auto-named projects.
//

import XCTest
import Supabase
@testable import OPS

final class ProjectDetailsTitleUpdateTests: XCTestCase {
    func testCustomTitleSaveDisablesAutoTitleOnServer() {
        let fields = ProjectDetailsViewModel.titleUpdateFields(forCustomTitle: "Faye Keys deck rebuild")

        XCTAssertEqual(fields["title"]?.stringValue, "Faye Keys deck rebuild")
        XCTAssertEqual(fields["title_is_auto"]?.boolValue, false)
    }
}

private extension AnyJSON {
    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}
