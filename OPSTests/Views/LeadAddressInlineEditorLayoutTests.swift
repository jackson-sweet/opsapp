//
//  LeadAddressInlineEditorLayoutTests.swift
//  OPSTests
//
//  Regression coverage for bug 5f49e0b9: the lead dossier's ADDRESS editor
//  must leave a usable text-entry lane at phone width. The failure shipped
//  when the document label, autocomplete accessories, and inline SAVE/CANCEL
//  controls all competed in one horizontal row.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class LeadAddressInlineEditorLayoutTests: XCTestCase {

    private let phoneSize = CGSize(width: 393, height: 760)

    /// A common street address must fit in the typing lane without collapsing
    /// to a few visible characters. At 180pt, "903 Collinson St" clears the
    /// OPS body font with working room for the insertion point; the shipped
    /// side-by-side control stack does not.
    func testAddressEditorKeepsReadableTypingLaneAtPhoneWidth() throws {
        let lead = Opportunity(
            id: "lead-address-layout",
            companyId: "company-address-layout",
            contactName: "Kim Berellie",
            stage: .quoted
        )
        lead.address = "903 Collinson St"
        lead.latitude = 48.422
        lead.longitude = -123.365

        let controller = LeadFieldEditController(opportunity: lead) { _ in lead }
        controller.begin(.address)

        let permissions = PermissionStore()
        permissions.disabledFlags = ["deck_builder"]

        let view = ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            LeadDetailsDocument(
                lead: lead,
                client: nil,
                rosterState: .noClient,
                canEdit: true,
                projectName: nil,
                attachments: [],
                estimates: [],
                fieldEdit: controller
            )
            .padding(.top, OPSStyle.Layout.spacing3)
        }
        .frame(width: phoneSize.width)
        .environmentObject(permissions)

        let hosted = try host(view)
        defer { hosted.restore() }

        settleGeometry(of: hosted.host.view.layer, in: hosted.window)
        let textField = try XCTUnwrap(
            findTextField(in: hosted.host.view),
            "The real address editor must expose a settled editable text field"
        )
        let fieldFrame = textField.convert(textField.bounds, to: hosted.host.view)
        print("Lead address text-entry frame: \(fieldFrame.integral)")

        capture(hosted.host.view, name: "lead_address_editor_layout")

        XCTAssertGreaterThanOrEqual(
            fieldFrame.width,
            180,
            "ADDRESS leaves only \(fieldFrame.width)pt for typing at 393pt — autocomplete and edit controls are squeezing the field"
        )
    }

    /// The sticky EDIT / MARK WON bar belongs to the dossier's reading state.
    /// Once an inline editor owns focus, leaving that global bar mounted covers
    /// the editor and its autocomplete results with unrelated actions.
    func testGlobalActionBarWithdrawsWhileInlineEditorOwnsFocus() {
        XCTAssertTrue(
            LeadDetailActionBarVisibility.shouldShow(
                canEdit: true,
                canConvert: false,
                isTerminal: false,
                activeEditor: nil
            )
        )
        XCTAssertTrue(
            LeadDetailActionBarVisibility.shouldShow(
                canEdit: false,
                canConvert: true,
                isTerminal: false,
                activeEditor: nil
            )
        )
        for field in LeadEditableField.allCases {
            XCTAssertFalse(
                LeadDetailActionBarVisibility.shouldShow(
                    canEdit: true,
                    canConvert: true,
                    isTerminal: false,
                    activeEditor: field
                ),
                "The global action bar must withdraw while \(field.rawValue) is being edited"
            )
        }
        XCTAssertFalse(
            LeadDetailActionBarVisibility.shouldShow(
                canEdit: true,
                canConvert: true,
                isTerminal: true,
                activeEditor: nil
            )
        )
        XCTAssertFalse(
            LeadDetailActionBarVisibility.shouldShow(
                canEdit: false,
                canConvert: false,
                isTerminal: false,
                activeEditor: nil
            )
        )
    }

    private struct HostedView {
        let window: UIWindow
        let originalRoot: UIViewController?
        let host: UIHostingController<AnyView>

        @MainActor
        func restore() {
            window.rootViewController = originalRoot
            window.layoutIfNeeded()
        }
    }

    private func host<V: View>(_ view: V) throws -> HostedView {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let host = UIHostingController(rootView: AnyView(view))
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = .black
        host.safeAreaRegions = []

        let container = UIViewController()
        container.overrideUserInterfaceStyle = .dark
        container.view.backgroundColor = .black
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.widthAnchor.constraint(equalToConstant: phoneSize.width),
            host.view.heightAnchor.constraint(equalToConstant: phoneSize.height),
        ])
        host.didMove(toParent: container)

        window.rootViewController = container
        window.layoutIfNeeded()

        return HostedView(window: window, originalRoot: originalRoot, host: host)
    }

    /// Wait on the hosted layer tree, never a fixed sleep. Three consecutive
    /// matching fingerprints prove SwiftUI has stopped rebuilding geometry;
    /// the deadline matches the shared snapshot harness and prevents a cursor
    /// or system animation from hanging CI indefinitely.
    private func settleGeometry(
        of layer: CALayer,
        in window: UIWindow,
        timeout: TimeInterval = 2
    ) {
        var lastFingerprint = ""
        var stablePasses = 0
        let deadline = Date(timeIntervalSinceNow: timeout)

        while stablePasses < 3, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            window.layoutIfNeeded()

            let fingerprint = geometryFingerprint(of: layer)
            if fingerprint == lastFingerprint {
                stablePasses += 1
            } else {
                lastFingerprint = fingerprint
                stablePasses = 0
            }
        }
    }

    private func geometryFingerprint(of layer: CALayer, depth: Int = 0) -> String {
        var parts = ["\(layer.frame.integral)"]
        if depth < 12, let sublayers = layer.sublayers {
            parts.append("\(sublayers.count)")
            for sublayer in sublayers {
                parts.append(geometryFingerprint(of: sublayer, depth: depth + 1))
            }
        }
        return parts.joined(separator: "|")
    }

    private func findTextField(in view: UIView) -> UITextField? {
        if let textField = view as? UITextField { return textField }
        for subview in view.subviews {
            if let match = findTextField(in: subview) { return match }
        }
        return nil
    }

    private func capture(_ view: UIView, name: String) {
        let renderer = UIGraphicsImageRenderer(size: phoneSize)
        let image = renderer.image { _ in
            view.drawHierarchy(
                in: CGRect(origin: .zero, size: phoneSize),
                afterScreenUpdates: true
            )
        }
        guard let data = image.pngData() else { return }

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)

        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name).png")
        try? data.write(to: output)
        print("Lead address layout proof: \(output.path)")
    }
}
#endif
