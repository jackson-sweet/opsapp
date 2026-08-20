//
//  KeyboardDoneAccessorySnapshotTests.swift
//  OPSTests
//
//  Visual proof for the global keyboard DONE accessory (bug 026891c5).
//
//  WHY THIS FILE EXISTS: the prior regression test measured the DONE *label's*
//  distance to the keyboard edge. An inner top padding satisfies that number
//  while the *button* still spans the whole band and sits flush on the
//  keyboard — so the suite went green while the founder could see the button's
//  border touching the keyboard. Numbers alone cannot catch that class of bug.
//  This renders the band exactly as it sits on the keyboard and writes a PNG
//  for a human to look at, alongside a pixel scan that reads the rendered
//  image rather than the constraint math.
//
//  The accessory's own bottom edge IS the keyboard's top edge (a UIToolbar
//  inputAccessoryView is mounted directly above the keyboard), so the canvas
//  draws a keyboard-toned strip immediately below the band to make the seam
//  unmistakable in the capture.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/KeyboardDoneAccessorySnapshotTests
//

#if DEBUG
import XCTest
import UIKit
@testable import OPS

@MainActor
final class KeyboardDoneAccessorySnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-keyboard-done-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Device width of the reference phone (iPhone 17 logical points).
    private let canvasWidth: CGFloat = 393
    /// Height of the fake keyboard strip drawn under the band.
    private let keyboardStripHeight: CGFloat = 96

    // MARK: - Harness

    private struct Rendered {
        let image: UIImage
        let accessory: OPSKeyboardDoneAccessoryView
        /// DONE button frame in canvas coordinates.
        let buttonFrame: CGRect
        /// DONE label frame in canvas coordinates.
        let labelFrame: CGRect
        /// y of the seam between the accessory band and the keyboard.
        let keyboardTopY: CGFloat
        let scale: CGFloat
    }

    private func renderBandOverKeyboard() throws -> Rendered {
        let bandHeight = OPSStyle.Layout.keyboardAccessoryHeight
        let canvasSize = CGSize(
            width: canvasWidth,
            height: bandHeight + keyboardStripHeight
        )

        let canvas = UIView(frame: CGRect(origin: .zero, size: canvasSize))
        canvas.backgroundColor = .black
        canvas.overrideUserInterfaceStyle = .dark

        // Keyboard-toned strip directly beneath the band. Its top edge is the
        // line the founder said the button border was touching.
        let keyboard = UIView(frame: CGRect(
            x: 0,
            y: bandHeight,
            width: canvasWidth,
            height: keyboardStripHeight
        ))
        keyboard.backgroundColor = UIColor(white: 0.16, alpha: 1.0)
        canvas.addSubview(keyboard)

        let textField = UITextField()
        let accessory = OPSKeyboardDoneAccessoryView(editingResponder: textField)
        accessory.frame = CGRect(x: 0, y: 0, width: canvasWidth, height: bandHeight)
        accessory.overrideUserInterfaceStyle = .dark
        canvas.addSubview(accessory)

        // iOS 26.5: UIToolbar only mounts bar-item custom views once it joins a
        // window, and window-level capture of a test-created window renders
        // blank — host inside the app's own window (CLAUDE.md iOS gotchas).
        let window = try AppHostWindow.acquire()
        window.addSubview(canvas)
        defer { canvas.removeFromSuperview() }

        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        accessory.setNeedsLayout()
        accessory.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        canvas.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { _ in
            canvas.drawHierarchy(in: canvas.bounds, afterScreenUpdates: true)
        }

        return Rendered(
            image: image,
            accessory: accessory,
            buttonFrame: accessory.doneButton.convert(
                accessory.doneButton.bounds,
                to: canvas
            ),
            labelFrame: accessory.doneLabel.convert(
                accessory.doneLabel.bounds,
                to: canvas
            ),
            keyboardTopY: bandHeight,
            scale: image.scale
        )
    }

    private func write(_ image: UIImage, named name: String) {
        guard let data = image.pngData() else {
            XCTFail("failed to encode \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = outDir.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("📸 SNAPSHOT \(name) -> \(url.path)")
    }

    // MARK: - Proof

    func testDoneButtonBorderClearsKeyboardEdgeAndLabelIsCentred() throws {
        let r = try renderBandOverKeyboard()
        write(r.image, named: "keyboard-done-accessory")

        let gapBelow = r.keyboardTopY - r.buttonFrame.maxY
        let gapAbove = r.buttonFrame.minY

        print("""
        📐 KEYBOARD DONE ACCESSORY GEOMETRY
           band height ............ \(OPSStyle.Layout.keyboardAccessoryHeight)
           button frame ........... \(r.buttonFrame)
           label frame ............ \(r.labelFrame)
           keyboard top edge y .... \(r.keyboardTopY)
           GAP below button border  \(gapBelow)
           GAP above button border  \(gapAbove)
           label midY - button midY \(r.labelFrame.midY - r.buttonFrame.midY)
        """)

        // The founder's defect, stated as an assertion on the BUTTON.
        XCTAssertGreaterThanOrEqual(
            gapBelow,
            OPSStyle.Layout.spacing1,
            "DONE button border must not touch the keyboard's top edge"
        )
        XCTAssertGreaterThanOrEqual(
            gapAbove,
            OPSStyle.Layout.spacing1,
            "DONE button border must not touch the top of the band"
        )
        XCTAssertGreaterThanOrEqual(
            r.buttonFrame.height,
            OPSStyle.Layout.touchTargetMin,
            "gap must not be bought out of the touch target"
        )
        // Sanity only — exact optical centring is proven against glyph ink in
        // testRenderedBorderMatchesMeasuredButtonAndClearsKeyboard.
        XCTAssertEqual(
            r.labelFrame.midY,
            r.buttonFrame.midY,
            accuracy: 4.0,
            "DONE must be vertically centred in the button"
        )
    }

    /// Reads the RENDERED PIXELS, not the constraint math. This is the guard
    /// the original regression test lacked: it proves the border a human sees
    /// is the same rectangle the geometry assertions measured, and that it
    /// stops short of the keyboard. A decorative platter drawn by UIKit around
    /// the button — the iOS 26 bar-item glass that caused this bug — would
    /// extend past the button's frame and fail this immediately.
    func testRenderedBorderMatchesMeasuredButtonAndClearsKeyboard() throws {
        let r = try renderBandOverKeyboard()
        write(r.image, named: "keyboard-done-accessory-pixelscan")

        guard let cg = r.image.cgImage else {
            XCTFail("no bitmap")
            return
        }

        let w = cg.width, h = cg.height
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(
            data: &raw, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Differential scan: the button's centre column against an empty
        // column of the same band. The band's own background cancels out, so
        // whatever remains is the button's rendered pixels.
        let s = r.scale
        let cx = Int(r.buttonFrame.midX * s)
        let refX = Int(8 * s)
        var top = -1, bottom = -1
        for y in 0..<Int(r.keyboardTopY * s) {
            let a = (y * w + cx) * 4
            let b = (y * w + refX) * 4
            let d = abs(Int(raw[a]) - Int(raw[b]))
                + abs(Int(raw[a + 1]) - Int(raw[b + 1]))
                + abs(Int(raw[a + 2]) - Int(raw[b + 2]))
            if d > 6 {
                if top < 0 { top = y }
                bottom = y
            }
        }
        XCTAssertGreaterThanOrEqual(top, 0, "nothing of the button rendered")

        let renderedTop = CGFloat(top) / s
        let renderedBottom = CGFloat(bottom + 1) / s
        let gapBelow = r.keyboardTopY - renderedBottom

        print("""
        \u{1F3A8} RENDERED BORDER (scale \(s))
           measured button ... [\(r.buttonFrame.minY) ... \(r.buttonFrame.maxY)]
           rendered border ... [\(renderedTop) ... \(renderedBottom)]
           keyboard edge ..... \(r.keyboardTopY)
           GAP below rendered  \(gapBelow)
           GAP above rendered  \(renderedTop)
        """)

        // What is drawn is what was measured — no hidden platter.
        XCTAssertEqual(
            renderedTop, r.buttonFrame.minY, accuracy: 1.5,
            "rendered border starts somewhere other than the button's frame"
        )
        XCTAssertEqual(
            renderedBottom, r.buttonFrame.maxY, accuracy: 1.5,
            "rendered border extends past the button's frame — a platter is being drawn"
        )
        // And it clears the keyboard.
        XCTAssertGreaterThanOrEqual(
            gapBelow, OPSStyle.Layout.spacing1,
            "rendered border must clear the keyboard's top edge"
        )
        XCTAssertGreaterThanOrEqual(
            renderedTop, OPSStyle.Layout.spacing1,
            "rendered border must clear the top of the band"
        )

        // Optical centring, measured on the glyph ink itself. Scan the button's
        // width for near-white text pixels; their vertical midpoint is where
        // the eye reads "DONE" as sitting.
        var inkRows: [Int] = []
        let bx0 = Int(r.buttonFrame.minX * s), bx1 = Int(r.buttonFrame.maxX * s)
        for y in 0..<Int(r.keyboardTopY * s) {
            var hit = false
            for x in bx0..<min(bx1, w) where raw[(y * w + x) * 4] > 120 {
                hit = true
                break
            }
            if hit { inkRows.append(y) }
        }
        let inkTop = CGFloat(inkRows.first ?? 0) / s
        let inkBottom = CGFloat((inkRows.last ?? 0) + 1) / s
        let inkCentre = (inkTop + inkBottom) / 2

        print("""
        \u{270D} GLYPH INK
           ink rows ........ \(inkTop) ... \(inkBottom)
           ink centre ...... \(inkCentre)
           button centre ... \(r.buttonFrame.midY)
           offset .......... \(inkCentre - r.buttonFrame.midY)
        """)

        XCTAssertFalse(inkRows.isEmpty, "no DONE glyphs rendered")
        XCTAssertEqual(
            inkCentre,
            r.buttonFrame.midY,
            accuracy: 0.5,
            "DONE's glyphs must be optically centred in the button"
        )
    }
}
#endif
