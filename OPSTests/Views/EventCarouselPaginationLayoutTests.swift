//
//  EventCarouselPaginationLayoutTests.swift
//  OPSTests
//
//  Regression coverage for bug 80e7d23a-9a16-4895-b458-f821dc1bb73e:
//  Home carousel pagination must occupy its own lane below the card instead
//  of covering long project/task titles.
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class EventCarouselPaginationLayoutTests: XCTestCase {

    func test_paginationLaneDoesNotIntersectCardContent() throws {
        let recorder = FrameRecorder()
        let window = mount(
            EventCarouselPaginationLayout(
                cardContent: {
                    Color.red
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        recorder.cardFrame = proxy.frame(in: .global)
                                    }
                            }
                        )
                },
                indicator: {
                    Color.blue
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        recorder.indicatorFrame = proxy.frame(in: .global)
                                    }
                            }
                        )
                }
            )
            .frame(
                width: EventCarouselMetrics.cardWidth,
                height: EventCarouselMetrics.viewportHeight
            )
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        let cardBounds = try XCTUnwrap(recorder.cardFrame)
        let indicatorBounds = try XCTUnwrap(recorder.indicatorFrame)
        window.isHidden = true

        XCTAssertFalse(
            cardBounds.intersects(indicatorBounds),
            "Pagination must render below the card, never over readable card content."
        )
    }

    private func mount<V: View>(_ view: V) -> UIWindow {
        let size = CGSize(
            width: EventCarouselMetrics.cardWidth,
            height: EventCarouselMetrics.viewportHeight
        )
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window.windowScene = scene
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return window
    }

    @MainActor
    private final class FrameRecorder {
        var cardFrame: CGRect?
        var indicatorFrame: CGRect?
    }
}
#endif
