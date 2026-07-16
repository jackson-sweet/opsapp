//
//  PhoneContactPickerSnapshotTests.swift
//  OPSTests
//
//  Bug 388663d4 — visual proof that device contacts blend into the client
//  picker with the "IN CONTACTS" badge. Renders the real `PhoneContactRow`
//  (text-only create-form variant and avatar change-client variant) plus a
//  blended picker list — OPS client rows and badged phone rows in one column,
//  exactly as the create-project dropdown composes them. A rendering harness,
//  not an assertion.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/PhoneContactPickerSnapshotTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class PhoneContactPickerSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-phone-contact-picker-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        let host = UIHostingController(rootView: content())
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }

    private func sug(_ id: String, _ name: String, _ subtitle: String) -> PhoneContactSuggestion {
        let parts = name.split(separator: " ")
        return PhoneContactSuggestion(
            id: id,
            displayName: name,
            firstName: String(parts.first ?? ""),
            lastName: parts.count > 1 ? String(parts.last!) : "",
            subtitle: subtitle,
            phones: [subtitle]
        )
    }

    /// Create-form dropdown variant — text-only rows, badge on the right.
    func testRenderPhoneRowTextOnly() {
        snapshot("phone_row_text_only", size: CGSize(width: 360, height: 72)) {
            PhoneContactRow(suggestion: sug("1", "Maya Stone", "(555) 123-4567"), showsAvatar: false) {}
                .background(OPSStyle.Colors.cardBackground)
        }
    }

    /// Change-client sheet variant — avatar initials + badge.
    func testRenderPhoneRowWithAvatar() {
        snapshot("phone_row_with_avatar", size: CGSize(width: 360, height: 72)) {
            PhoneContactRow(suggestion: sug("1", "Jordan Blake", "jordan@blake.co"), showsAvatar: true) {}
                .background(OPSStyle.Colors.cardBackground)
        }
    }

    /// The blend: OPS client matches first (unbadged), then device contacts
    /// that aren't in OPS yet (badged) — the create-project dropdown layout.
    func testRenderBlendedPickerList() {
        snapshot("blended_picker_list", size: CGSize(width: 360, height: 300)) {
            VStack(spacing: 0) {
                opsRow("Canpro Decks")
                divider
                opsRow("Sarah Lee")
                divider
                PhoneContactRow(suggestion: sug("p1", "Maya Stone", "(555) 123-4567"), showsAvatar: false) {}
                divider
                PhoneContactRow(suggestion: sug("p2", "Bob Vance", "bob@vance.com"), showsAvatar: false) {}
            }
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    // OPS client row stand-in — matches the create-form dropdown's text rows.
    private func opsRow(_ name: String) -> some View {
        HStack {
            Text(name)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private var divider: some View {
        Divider().background(OPSStyle.Colors.cardBorder)
    }
}
#endif
