//
//  HeaderGeometryTests.swift
//  OPSTests
//
//  Geometry contract for every custom OPS header. The shared band stays 52pt
//  at nominal type, grows instead of clipping at accessibility sizes, keeps
//  controls glove-safe, respects the system safe area, and never exposes more
//  than two trailing actions.
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class HeaderGeometryTests: XCTestCase {
    private struct ProbeAction: Identifiable, Equatable {
        let id: String
    }

    private struct BoundsKey: PreferenceKey {
        static let defaultValue: [String: Anchor<CGRect>] = [:]

        static func reduce(
            value: inout [String: Anchor<CGRect>],
            nextValue: () -> [String: Anchor<CGRect>]
        ) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    private final class Measurements {
        var frames: [String: CGRect] = [:]
    }

    private struct Harness: View {
        let width: CGFloat
        let title: String
        let typeSize: DynamicTypeSize
        let safeAreaTop: CGFloat
        let requestedTrailingActions: [ProbeAction]
        let sink: Measurements

        var body: some View {
            VStack(spacing: 0) {
                OPSScreenHeader(
                    title,
                    leading: {
                        measuredButton(id: "leading", symbol: "chevron.left")
                    },
                    trailing: {
                        OPSHeaderActionStrip(requestedTrailingActions) { action in
                            measuredButton(id: action.id, symbol: "circle")
                        }
                    }
                )
                .anchorPreference(key: BoundsKey.self, value: .bounds) {
                    ["header": $0]
                }

                Spacer(minLength: 0)
            }
            // `safeAreaInset` models the system-owned status-bar/notch region.
            // A conforming header begins below it without adding the inset to
            // its own 52pt content-band height.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: safeAreaTop)
            }
            .frame(width: width, height: 260, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
            .overlayPreferenceValue(BoundsKey.self) { anchors in
                GeometryReader { proxy -> Color in
                    for (key, anchor) in anchors {
                        sink.frames[key] = proxy[anchor]
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
        }

        private func measuredButton(id: String, symbol: String) -> some View {
            Button(action: {}) {
                Image(systemName: symbol)
                    .frame(
                        width: OPSStyle.Layout.Indicator.dotMD,
                        height: OPSStyle.Layout.Indicator.dotMD
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(id)
            .anchorPreference(key: BoundsKey.self, value: .bounds) {
                [id: $0]
            }
        }
    }

    private struct TargetHarness: View {
        let sink: Measurements

        var body: some View {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                target(id: "leadingTarget", position: .leading, alignment: .leading)
                target(id: "trailingTarget", position: .trailing(0), alignment: .trailing)
            }
            .overlayPreferenceValue(BoundsKey.self) { anchors in
                GeometryReader { proxy -> Color in
                    for (key, anchor) in anchors {
                        sink.frames[key] = proxy[anchor]
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
        }

        private func target(
            id: String,
            position: OPSHeaderGeometry.AccessibilityPosition,
            alignment: Alignment
        ) -> some View {
            OPSHeaderControlSlot(position: position, alignment: alignment) {
                Button(action: {}) {
                    Image(systemName: "circle")
                        .frame(
                            width: OPSStyle.Layout.Indicator.dotMD,
                            height: OPSStyle.Layout.Indicator.dotMD
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(id)
            }
            .anchorPreference(key: BoundsKey.self, value: .bounds) {
                [id: $0]
            }
        }
    }

    private struct WrapperHarness<Content: View>: View {
        let width: CGFloat
        let typeSize: DynamicTypeSize
        let sink: Measurements
        let content: Content

        init(
            width: CGFloat,
            typeSize: DynamicTypeSize = .large,
            sink: Measurements,
            @ViewBuilder content: () -> Content
        ) {
            self.width = width
            self.typeSize = typeSize
            self.sink = sink
            self.content = content()
        }

        var body: some View {
            VStack(spacing: 0) {
                content
                    .anchorPreference(key: BoundsKey.self, value: .bounds) {
                        ["wrapper": $0]
                    }
                Spacer(minLength: 0)
            }
            .frame(width: width, height: 260, alignment: .top)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(typeSize)
            .overlayPreferenceValue(BoundsKey.self) { anchors in
                GeometryReader { proxy -> Color in
                    if let anchor = anchors["wrapper"] {
                        sink.frames["wrapper"] = proxy[anchor]
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func measure(
        width: CGFloat,
        title: String = "SETTINGS",
        typeSize: DynamicTypeSize = .large,
        safeAreaTop: CGFloat = 0,
        requestedTrailingActions: [ProbeAction] = [
            ProbeAction(id: "action.0"),
            ProbeAction(id: "action.1"),
        ]
    ) throws -> Measurements {
        let sink = Measurements()
        let view = Harness(
            width: width,
            title: title,
            typeSize: typeSize,
            safeAreaTop: safeAreaTop,
            requestedTrailingActions: requestedTrailingActions,
            sink: sink
        )
        _ = try FixedSizeSnapshot.render(view, size: CGSize(width: width, height: 260))
        return sink
    }

    func testNominalBandAtSupportedPhoneWidths() throws {
        for width in [CGFloat(320), CGFloat(390)] {
            let measured = try measure(width: width)
            let header = try XCTUnwrap(measured.frames["header"])

            XCTAssertEqual(header.width, width, accuracy: 0.5)
            XCTAssertEqual(
                header.height,
                OPSStyle.Layout.screenHeaderBandHeight,
                accuracy: 0.5,
                "\(Int(width))pt: nominal header must use the shared 52pt band"
            )
        }
    }

    func testControlSlotsExpandIntrinsicIconsToAccessibleTargets() throws {
        let sink = Measurements()
        let view = TargetHarness(sink: sink)
        _ = try FixedSizeSnapshot.render(
            view,
            size: CGSize(width: 320, height: 260)
        )

        for id in ["leadingTarget", "trailingTarget"] {
            let target = try XCTUnwrap(sink.frames[id])
            XCTAssertGreaterThanOrEqual(target.width, OPSStyle.Layout.touchTargetMin)
            XCTAssertGreaterThanOrEqual(target.height, OPSStyle.Layout.touchTargetMin)
        }
    }

    func testLongTitleGrowsAtAccessibilityTypeInsteadOfClipping() throws {
        let title = "CERTIFICATIONS & TRAINING"
        let nominal = try measure(width: 320, title: title)
        let accessibility = try measure(
            width: 320,
            title: title,
            typeSize: .accessibility5
        )
        let nominalHeader = try XCTUnwrap(nominal.frames["header"])
        let accessibilityHeader = try XCTUnwrap(accessibility.frames["header"])

        XCTAssertGreaterThanOrEqual(
            nominalHeader.height,
            OPSStyle.Layout.screenHeaderBandHeight
        )
        XCTAssertGreaterThan(
            accessibilityHeader.height,
            nominalHeader.height,
            "Dynamic Type must grow the header rather than shrink or clip its title"
        )
    }

    func testSafeAreaStaysOutsideTheHeaderBand() throws {
        let baseline = try measure(width: 390)
        let inset = try measure(width: 390, safeAreaTop: 31)
        let baselineHeader = try XCTUnwrap(baseline.frames["header"])
        let insetHeader = try XCTUnwrap(inset.frames["header"])

        XCTAssertEqual(insetHeader.minY - baselineHeader.minY, 31, accuracy: 0.5)
        XCTAssertEqual(insetHeader.height, baselineHeader.height, accuracy: 0.5)
    }

    func testTrailingPolicyCapsActionsAndDefinesAccessibleTraversalOrder() throws {
        let requested = [
            ProbeAction(id: "action.0"),
            ProbeAction(id: "action.1"),
            ProbeAction(id: "action.2"),
        ]
        let visible = OPSHeaderGeometry.visibleTrailingActions(from: requested)

        XCTAssertEqual(visible.map(\.id), ["action.0", "action.1"])
        XCTAssertEqual(visible.count, OPSHeaderGeometry.maximumTrailingActionCount)

        let order = OPSHeaderGeometry.accessibilityOrder(
            hasLeading: true,
            trailingActionCount: requested.count
        )
        XCTAssertEqual(
            order,
            [.leading, .title, .trailing(0), .trailing(1)]
        )
        let priorities = order.map {
            OPSHeaderGeometry.accessibilitySortPriority(for: $0)
        }
        for pair in zip(priorities, priorities.dropFirst()) {
            XCTAssertGreaterThan(
                pair.0,
                pair.1,
                "Accessibility priorities must preserve back, title, then source-order actions"
            )
        }

        let measured = try measure(width: 390, requestedTrailingActions: requested)
        let first = try XCTUnwrap(measured.frames["action.0"])
        let second = try XCTUnwrap(measured.frames["action.1"])
        XCTAssertLessThan(first.minX, second.minX, "Source order must match visual order")
        XCTAssertNil(measured.frames["action.2"], "A third trailing action must not render")
    }

    func testSettingsAndQuickActionCompatibilityHeadersUseSharedBand() throws {
        let settingsSink = Measurements()
        let settings = WrapperHarness(width: 320, sink: settingsSink) {
            SettingsHeader(
                title: "PROFILE SETTINGS",
                onBackTapped: {}
            )
        }
        _ = try FixedSizeSnapshot.render(
            settings,
            size: CGSize(width: 320, height: 260)
        )
        let settingsFrame = try XCTUnwrap(settingsSink.frames["wrapper"])
        XCTAssertEqual(
            settingsFrame.height,
            OPSStyle.Layout.screenHeaderBandHeight,
            accuracy: 0.5
        )

        let sheetSink = Measurements()
        let sheet = WrapperHarness(width: 320, sink: sheetSink) {
            QuickActionSheetHeader(
                title: "CHANGE STATUS",
                canSave: true,
                isSaving: false,
                onDismiss: {},
                onSave: {}
            )
        }
        _ = try FixedSizeSnapshot.render(
            sheet,
            size: CGSize(width: 320, height: 260)
        )
        let sheetFrame = try XCTUnwrap(sheetSink.frames["wrapper"])
        XCTAssertGreaterThanOrEqual(
            sheetFrame.height,
            OPSStyle.Layout.screenHeaderBandHeight
        )
        XCTAssertLessThanOrEqual(
            sheetFrame.height,
            OPSStyle.Layout.screenHeaderBandHeight + OPSStyle.Layout.Border.thick,
            "The sheet divider may add only its tokenized hairline to the shared band"
        )
    }

    func testCompactAndAccessibilitySnapshots() throws {
        try snapshot(
            "header-320-long-title",
            width: 320,
            title: "CERTIFICATIONS & TRAINING",
            typeSize: .large
        )
        try snapshot(
            "header-390-accessibility5",
            width: 390,
            title: "CERTIFICATIONS & TRAINING",
            typeSize: .accessibility5
        )
    }

    private func snapshot(
        _ name: String,
        width: CGFloat,
        title: String,
        typeSize: DynamicTypeSize
    ) throws {
        let sink = Measurements()
        let view = Harness(
            width: width,
            title: title,
            typeSize: typeSize,
            safeAreaTop: 0,
            requestedTrailingActions: [
                ProbeAction(id: "action.0"),
                ProbeAction(id: "action.1"),
            ],
            sink: sink
        )
        let image = try FixedSizeSnapshot.render(
            view,
            size: CGSize(width: width, height: 260)
        )
        let attachment = XCTAttachment(
            data: try XCTUnwrap(image.pngData()),
            uniformTypeIdentifier: "public.png"
        )
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
