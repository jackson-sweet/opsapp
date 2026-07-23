//
//  ComebackChooserSheetSnapshotTests.swift
//  OPSTests
//
//  Visual proof that the collapsed medium-height ownership/comeback sheet
//  keeps every action, including PICK DATE, visible after the ownership row
//  was added.
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class ComebackChooserSheetSnapshotTests: XCTestCase {
    func testCollapsedOwnershipAndComebackRowsFitMediumSheet() throws {
        let size = CGSize(width: 390, height: 844)
        var layout: ComebackChooserLayoutSnapshot?
        let lead = Opportunity(
            id: "lead-snapshot",
            companyId: "company-snapshot",
            contactName: "Helen Calloway",
            stage: .quoted
        )
        let host = UIHostingController(
            rootView: Color.black
                .ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    ComebackChooserSheet(
                        lead: lead,
                        viewModel: PipelineViewModel(),
                        layoutObserver: { layout = $0 }
                    )
                }
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.75))

        let measured = try XCTUnwrap(layout)
        for frame in [measured.ownership, measured.pickDate] {
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertGreaterThanOrEqual(
                frame.minY,
                measured.container.minY
            )
            XCTAssertLessThanOrEqual(
                frame.maxY,
                measured.container.maxY
            )
        }
        XCTAssertGreaterThan(
            measured.pickDate.minY,
            measured.ownership.maxY
        )

        let sheet = try XCTUnwrap(host.presentedViewController?.view)
        sheet.setNeedsLayout()
        sheet.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(bounds: sheet.bounds)
        let image = renderer.image { _ in
            sheet.drawHierarchy(in: sheet.bounds, afterScreenUpdates: true)
        }
        let data = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(
            data: data,
            uniformTypeIdentifier: "public.png"
        )
        attachment.name = "comeback-chooser-collapsed.png"
        attachment.lifetime = .keepAlways
        add(attachment)

        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("comeback-chooser-collapsed.png")
        try data.write(to: output)
        XCTAssertEqual(image.size, sheet.bounds.size)
        XCTAssertEqual(image.size.width, size.width)
        XCTAssertGreaterThan(image.size.height, 0)
    }

}
#endif
