//
//  StatusTagContrastSnapshotTests.swift
//  OPSTests
//
//  Visual proof for the MOBILE.md §1 status-tag correction — the picture that
//  goes with the numbers in OPSTests/Styles/StatusTagContrastTests.swift.
//
//  The change is app-wide: ~190 references across 39 files render from the
//  `*FillM` / `*LineM` / `*TextM` family, `ToneTag` and `Toast` most of all. So
//  the question is not "is it more legible" — the measurements settle that —
//  it is "does it still look like OPS". That is a taste call, and a taste call
//  needs images.
//
//  The BEFORE values are literals here because they no longer exist as tokens.
//  That is deliberate: this file is the only place the old numbers survive, so
//  the comparison stays reproducible after the tokens have moved on.
//
//  A rendering harness, not an assertion — every test here writes PNGs and
//  passes. The assertions live in the contrast test alongside it.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/StatusTagContrastSnapshotTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class StatusTagContrastSnapshotTests: XCTestCase {

    // MARK: - The values as they stood before the correction

    /// What `*FillM` / `*LineM` / `*TextM` held while their own comment cited
    /// MOBILE.md §1 — 0.20 / 0.55 against a spec that says 0.32 / 0.88, and
    /// inks that were never the ~25% lift they claimed (tan was +9% / +12% /
    /// +25% — a blue-only shift wearing a uniform label).
    private enum Before {
        static let fill: Double = 0.20
        static let line: Double = 0.55
        static let oliveInk = Color(red: 0.710, green: 0.788, blue: 0.627)   // #B5C9A0
        static let tanInk   = Color(red: 0.839, green: 0.737, blue: 0.510)   // #D6BC82
        static let roseInk  = Color(red: 0.788, green: 0.612, blue: 0.639)   // #C99CA3
    }

    private struct ToneRow {
        let name: String
        let base: Color
        let beforeInk: Color
        let afterFill: Color
        let afterLine: Color
        let afterInk: Color
        let sample: String
    }

    private var rows: [ToneRow] {
        [
            ToneRow(name: "OLIVE / success",
                    base: OPSStyle.Colors.olive,
                    beforeInk: Before.oliveInk,
                    afterFill: OPSStyle.Colors.oliveFillM,
                    afterLine: OPSStyle.Colors.oliveLineM,
                    afterInk: OPSStyle.Colors.oliveTextM,
                    sample: "WON"),
            ToneRow(name: "TAN / attention",
                    base: OPSStyle.Colors.tan,
                    beforeInk: Before.tanInk,
                    afterFill: OPSStyle.Colors.tanFillM,
                    afterLine: OPSStyle.Colors.tanLineM,
                    afterInk: OPSStyle.Colors.tanTextM,
                    sample: "TODAY"),
            ToneRow(name: "ROSE / overdue",
                    base: OPSStyle.Colors.rose,
                    beforeInk: Before.roseInk,
                    afterFill: OPSStyle.Colors.roseFillM,
                    afterLine: OPSStyle.Colors.roseLineM,
                    afterInk: OPSStyle.Colors.roseTextM,
                    sample: "3D LATE"),
        ]
    }

    // MARK: - Tests

    /// The money shot: the same three tags, old tokens beside new, on the
    /// canvas they actually sit on.
    func testStatusTagsBeforeAndAfter() {
        snapshot("status-tags-before-after", size: CGSize(width: 390, height: 300)) {
            comparisonSheet(glare: 0)
        }
    }

    /// The same sheet under a white veil approximating direct sun on the
    /// screen — the condition §1's uplift exists for. If the correction earns
    /// its keep anywhere, it is here: the old outlines wash out first.
    func testStatusTagsUnderGlare() {
        snapshot("status-tags-glare", size: CGSize(width: 390, height: 300)) {
            comparisonSheet(glare: 0.28)
        }
    }

    /// The real shared component, post-change, in the row it ships in — proof
    /// the tokens land in `ToneTag` and not just in a specimen.
    func testToneTagLive() {
        snapshot("tone-tag-live", size: CGSize(width: 390, height: 120)) {
            ZStack {
                OPSStyle.Colors.background
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ToneTag("3D LATE", tone: .rose)
                    ToneTag("TODAY", tone: .tan)
                    ToneTag("YOUR MOVE", tone: .neutral)
                }
            }
        }
    }

    /// `Toast` is the other heavy consumer, and it uses the family differently:
    /// `*LineM` tints a hairline over glass rather than outlining a tag, and
    /// the label sits on that glass rather than on a tone fill. Raising the
    /// border to 0.88 makes the toast edge markedly louder — a real
    /// consequence of the change, and the one most worth a look.
    func testToastTonesLive() {
        for (tone, label) in [(ToastTone.success, "// LEAD CREATED"),
                              (ToastTone.warning, "// LEAD LOST"),
                              (ToastTone.error, "// LEAD DELETED")] {
            ToastCenter.shared.present(Toast(label: label, tone: tone, autoDismissAfter: 600))
            snapshot("toast-\(tone)", size: CGSize(width: 390, height: 160)) {
                ZStack {
                    OPSStyle.Colors.background
                    ToastHostView()
                }
            }
            ToastCenter.shared.dismiss()
        }
    }

    // MARK: - Sheet

    @ViewBuilder
    private func comparisonSheet(glare: Double) -> some View {
        ZStack {
            OPSStyle.Colors.background

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header

                ForEach(rows, id: \.name) { row in
                    HStack(spacing: 0) {
                        Text(row.name)
                            .font(OPSStyle.Typography.nanoLabel)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .kerning(1.2)
                            .textCase(.uppercase)
                            .frame(width: 118, alignment: .leading)

                        self.specimen(tone: row.base,
                                      fill: row.base.opacity(Before.fill),
                                      line: row.base.opacity(Before.line),
                                      ink: row.beforeInk,
                                      label: row.sample)
                            .frame(width: 110, alignment: .leading)

                        self.specimen(tone: row.base,
                                      fill: row.afterFill,
                                      line: row.afterLine,
                                      ink: row.afterInk,
                                      label: row.sample)
                            .frame(width: 110, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 20)

            // Sun on the screen: a flat white veil is a crude model of glare,
            // but it is the right crude model — it collapses the low end of the
            // range, which is exactly where the old 0.55 outline lived.
            if glare > 0 {
                Color.white.opacity(glare).allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("// MOBILE.md §1")
                .frame(width: 118, alignment: .leading)
            Text("BEFORE")
                .frame(width: 110, alignment: .leading)
            Text("AFTER")
                .frame(width: 110, alignment: .leading)
        }
        .font(OPSStyle.Typography.nanoLabel)
        .foregroundColor(OPSStyle.Colors.textMute)
        .kerning(1.2)
    }

    /// `ToneTag`'s metrics verbatim — same padding, radius, weight, kerning and
    /// font — with the three colours injected, so BEFORE and AFTER differ in
    /// colour and in nothing else.
    private func specimen(tone: Color, fill: Color, line: Color, ink: Color, label: String) -> some View {
        Text(label)
            .monospacedDigit()
            .font(OPSStyle.Typography.nanoLabel)
            .fontWeight(.semibold)
            .kerning(1.4)
            .foregroundColor(ink)
            .textCase(.uppercase)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(line, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    // MARK: - Capture

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-status-tag-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        do {
            let image = try FixedSizeSnapshot.render(content(), size: size)
            guard let data = image.pngData() else { return XCTFail("render \(name)") }
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "\(name).png"
            attachment.lifetime = .keepAlways
            add(attachment)
            try data.write(to: outDir.appendingPathComponent("\(name).png"))
            print("📸 SNAPSHOT \(name) → \(outDir.path)/\(name).png")
        } catch {
            XCTFail("snapshot \(name) failed: \(error)")
        }
    }
}
#endif
