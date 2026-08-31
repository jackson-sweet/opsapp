//
//  LeadInputPlaceholderSnapshotTests.swift
//  OPSTests
//
//  Bug 93b0dbe0 — "address input in convert to project is not a tokenized
//  address input."
//
//  CONVERT → PROJECT has used the shared tokenized AddressAutocompleteField
//  since 7347b075, with known-place suggestions since 3c67e894; the reporting
//  build (3.0.5) predated both. What was genuinely still wrong is what this
//  file proves: the lead-form primitives beside the address field carried two
//  off-token values (placeholder on `textMute` instead of `--text-3`, focus
//  border as a raw white literal), so the address field READ as a different
//  family from the VALUE and NOTES fields stacked next to it.
//
//  The frame renders a LeadField-wrapped LeadTextInput directly above the
//  shared AddressAutocompleteField. The two placeholders must now be the same
//  brightness — that is the whole proof, and it is visual, so this is a
//  rendering harness with an attachment, not a pixel assertion.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/LeadInputPlaceholderSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-lead-input-placeholder-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
import UIKit
@testable import OPS

@MainActor
final class LeadInputPlaceholderSnapshotTests: XCTestCase {

    /// A ModelContext does NOT keep its container alive — an unretained
    /// container deallocates and the next SwiftData touch traps.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Token contract

    /// The focus border traces to a token rather than a raw literal. Same
    /// value, so there is zero visual change — the trace is the point, and it
    /// is what keeps the next edit from drifting.
    func testFocusBorderTokenExists() {
        XCTAssertEqual(
            OPSStyle.Colors.inputFieldBorderFocus,
            Color.white.opacity(0.20),
            "inputFieldBorderFocus must keep the value the lead inputs used to hardcode"
        )
    }

    /// Placeholders across the lead form and the shared address field resolve
    /// to the SAME token. `text3` and `tertiaryText` are two names for one
    /// asset; the address field uses the latter, the lead inputs now use the
    /// former, and they must not diverge.
    func testPlaceholderTokensAreOneColor() {
        XCTAssertEqual(
            OPSStyle.Colors.text3,
            OPSStyle.Colors.tertiaryText,
            "the lead inputs' placeholder token and the address field's must be one color"
        )
        XCTAssertNotEqual(
            OPSStyle.Colors.text3,
            OPSStyle.Colors.textMute,
            "textMute is decorative-only (DESIGN.md §3) and is not a placeholder color"
        )
    }

    // MARK: - Rendered proof

    /// One frame, both fields, both empty — the placeholder family match.
    func testRendersLeadInputAndAddressFieldPlaceholderFamily() throws {
        let container = try makeContainer()
        let size = CGSize(width: 393, height: 300)

        let image = try FixedSizeSnapshot.render(
            VStack(alignment: .leading, spacing: 14) {
                LeadField(label: "ESTIMATED VALUE") {
                    LeadTextInput(
                        placeholder: "0.00",
                        text: .constant(""),
                        leading: "$"
                    )
                }
                LeadField(label: "SITE ADDRESS") {
                    AddressAutocompleteField(
                        address: .constant(""),
                        placeholder: "Enter Address"
                    )
                }
                LeadField(label: "NOTES") {
                    LeadTextArea(placeholder: "Anything the crew should know", text: .constant(""), rows: 2)
                }
            }
            .padding(OPSStyle.Layout.spacing3_5)
            .frame(width: size.width, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(OPSStyle.Colors.background)
            .modelContainer(container),
            size: size,
            minimumSettle: 0.4
        )

        attach(image, named: "lead-input-placeholder-family")
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // MARK: - Harness

    private func makeContainer() throws -> ModelContainer {
        // AddressAutocompleteField reads modelContext for known places; the
        // relationship closure must be complete even though nothing is seeded.
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            ProjectVinylOrderMarker.self,
            DeckDesign.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return container
    }

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-lead-input-placeholder-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func attach(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }
}
#endif
