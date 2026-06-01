//
//  BooksSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the Books tab UX overhaul (P6).
//  Renders the hero-carousel cards (and, post-refactor, their condensed
//  faces + expanded sheets + the below-picker section) to PNGs via
//  SwiftUI's `ImageRenderer`, driven by the DEBUG `previewStub` data so
//  the output matches Xcode's live preview canvas.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/BooksSnapshotTests \
//          -derivedDataPath /tmp/ops-ux-dd
//
//  Output: $TMPDIR/ops-books-shots/<name>@3x.png  (path is logged).
//  This is a rendering harness, not an assertion test — it never fails on
//  pixels; it writes images for a human/agent to inspect.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class BooksSnapshotTests: XCTestCase {

    /// iPhone 17 logical width (pt). Cards apply their own horizontal padding.
    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-books-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Renders a SwiftUI view to a PNG at @3x on the canvas background in dark mode.
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
        // XCTest runs in the simulator sandbox, so a plain file write lands
        // inside the sim — unreachable from the host. Attach to the .xcresult
        // (extractable via `xcrun xcresulttool export attachments`) AND mirror
        // to the sim tmp dir for local debugging.
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    // MARK: - Cards

    func testRenderBooksSurfaces() {
        let vm = MoneyDashboardViewModel.previewStub()
        let empty = MoneyDashboardViewModel.previewEmpty()

        // Condensed faces — the new uniform glance tiles (one fixed height).
        snapshot("condensed_pl") {
            PLCard(viewModel: vm, style: .condensed, onTapOutstanding: {}, onTapForecast: {})
                .padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("condensed_cashflow") {
            CashFlowCard(viewModel: vm, style: .condensed).padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("condensed_ar") {
            ARCard(viewModel: vm, style: .condensed, onTapTopChase: {}).padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("condensed_forecast") {
            ForecastCard(viewModel: vm, style: .condensed).padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("condensed_jobs") {
            JobsCard(viewModel: vm, style: .condensed).padding(.vertical, OPSStyle.Layout.spacing3)
        }

        // All five stacked — proves uniform height + consistent design language.
        snapshot("condensed_strip") {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                PLCard(viewModel: vm, style: .condensed, onTapOutstanding: {}, onTapForecast: {})
                CashFlowCard(viewModel: vm, style: .condensed)
                ARCard(viewModel: vm, style: .condensed, onTapTopChase: {})
                ForecastCard(viewModel: vm, style: .condensed)
                JobsCard(viewModel: vm, style: .condensed)
            }
            .padding(.vertical, OPSStyle.Layout.spacing4)
        }

        // Empty condensed states (em-dash / zero, flat viz).
        snapshot("condensed_empty") {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                PLCard(viewModel: empty, style: .condensed, onTapOutstanding: {}, onTapForecast: {})
                ARCard(viewModel: empty, style: .condensed, onTapTopChase: {})
                JobsCard(viewModel: empty, style: .condensed)
            }
            .padding(.vertical, OPSStyle.Layout.spacing4)
        }

        // Expanded sheet content (the full card body now lives in the sheet).
        snapshot("expanded_pl") {
            PLCard(viewModel: vm, style: .full, onTapOutstanding: {}, onTapForecast: {})
                .padding(.vertical, OPSStyle.Layout.spacing3)
        }
        snapshot("expanded_forecast") {
            ForecastCard(viewModel: vm, style: .full).padding(.vertical, OPSStyle.Layout.spacing3)
        }
    }
}
#endif
