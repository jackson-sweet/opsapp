//
//  ColorOptionSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the TaskTypeSheet colour-picker swatch
//  (`ColorOption`). Renders the three swatch states and a realistic family
//  row to PNGs via SwiftUI's `ImageRenderer` so the restrained selection
//  treatment + collision-free grid can be eyeballed headlessly.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17' \
//          -only-testing:OPSTests/ColorOptionSnapshotTests \
//          -derivedDataPath /tmp/ops-tasktype-dd
//
//  Output: attachments in the .xcresult (export via `xcrun xcresulttool`),
//  mirrored to $TMPDIR/ops-colorpicker-shots/<name>@3x.png.
//  Rendering harness, not an assertion test — it never fails on pixels.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class ColorOptionSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-colorpicker-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, width: CGFloat? = nil, @ViewBuilder _ content: () -> V) {
        let w = width ?? deviceWidth
        let host = content()
            .frame(width: w)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: host)
        renderer.scale = 3
        renderer.isOpaque = true

        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    private func hex(_ h: String) -> Color { Color(hex: h) ?? .gray }

    private func labeled<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            content()
            Text(title)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    func testRenderColorPickerStates() {
        // The three swatch states, zoomed, so the restrained selection ring +
        // checkmark reads clearly against an unselected swatch and the in-use
        // (dimmed + slash) state.
        snapshot("states") {
            HStack(spacing: OPSStyle.Layout.spacing5) {
                labeled("UNSELECTED") {
                    ColorOption(color: hex("5D8CAE"), isSelected: false, action: {})
                }
                labeled("SELECTED") {
                    ColorOption(color: hex("5D8CAE"), isSelected: true, action: {})
                }
                labeled("IN USE") {
                    ColorOption(color: hex("5D8CAE"), isSelected: false, isInUse: true,
                                usedByName: "Framing", action: {})
                }
            }
            .padding(OPSStyle.Layout.spacing5)
        }

        // A realistic family row in the real FlowLayout — proves the grid is
        // uniform, the selected swatch doesn't balloon or collide with peers,
        // and there is no overflowing "SELECTED" label.
        let warmFamily = ["C79A95", "A0837F", "8B534E", "A47864", "B7788D", "7A6455", "716354"]
        snapshot("family_row") {
            FlowLayout(spacing: OPSStyle.Layout.spacing2) {
                ForEach(Array(warmFamily.enumerated()), id: \.offset) { idx, h in
                    ColorOption(
                        color: self.hex(h),
                        isSelected: idx == 3,
                        isInUse: idx == 1,
                        usedByName: idx == 1 ? "Inspection" : nil,
                        action: {}
                    )
                }
            }
            .padding(OPSStyle.Layout.spacing4)
        }
    }
}
#endif
