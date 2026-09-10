//
//  BugReportPickSession.swift
//  OPS
//
//  One POINT AT IT round trip (bug 14e5a792), and the draft that survives it.
//
//  The report sheet steps aside, the live app sits under a transparent pick
//  layer, the operator puts a finger on the problem and lifts. This object
//  owns everything between those two moments: the capture Vision reads, the
//  element under the finger while it moves, and the finished pick.
//

import SwiftUI
import UIKit

// MARK: - Draft

/// Everything the operator has put into the report so far.
///
/// Owned by `BugReportPresenter`, not by the sheet: POINT AT IT dismisses the
/// sheet to show the live app, and what was typed, chosen and marked has to
/// be exactly where the operator left it when the sheet comes back.
@MainActor
final class BugReportDraft: ObservableObject {

    /// A pick, and the capture its rect was measured against.
    struct MarkedSpot {
        let element: BugReportElementPick
        /// The app window at the instant the finger lifted. Nil only when the
        /// window could not be rendered, in which case the trigger shot stands.
        let screenshot: UIImage?
    }

    /// The shot taken when the report was triggered.
    let triggerScreenshot: UIImage?

    @Published var description: String
    @Published var category: BugCategory
    @Published private(set) var spot: MarkedSpot?

    init(
        triggerScreenshot: UIImage?,
        description: String = "",
        category: BugCategory = .bug,
        spot: MarkedSpot? = nil
    ) {
        self.triggerScreenshot = triggerScreenshot
        self.description = description
        self.category = category
        self.spot = spot
    }

    /// The screenshot the report carries: the pick-time capture when there is
    /// a mark — so the recorded rect lines up with the attached image — and
    /// the trigger capture otherwise.
    var screenshot: UIImage? {
        spot?.screenshot ?? triggerScreenshot
    }

    var element: BugReportElementPick? {
        spot?.element
    }

    func mark(_ element: BugReportElementPick, screenshot: UIImage?) {
        spot = MarkedSpot(element: element, screenshot: screenshot)
    }

    /// Drops the mark and, with it, the pick-time capture — the report goes
    /// back to the shot it was triggered with.
    func clearMark() {
        spot = nil
    }
}

// MARK: - Session

@MainActor
final class BugReportPickSession: ObservableObject {

    /// What the finger is on right now (while tracking), or what it lifted on
    /// (once committed). App-window points.
    @Published private(set) var target: BugReportPickResolution?
    /// A finger is down.
    @Published private(set) var isTracking = false
    /// The finger lifted; the pick is being finished.
    @Published private(set) var isCommitted = false

    /// Longest the lift waits for Vision before finishing without text.
    /// Vision starts when the layer arms, so it has almost always finished by
    /// the time a finger reaches the problem; this bound only matters for an
    /// instant tap.
    static let textWaitLimit: TimeInterval = 1.0

    private weak var appWindow: UIWindow?
    private let screenName: String
    private let toAppWindow: (CGPoint) -> CGPoint
    private let toLayer: (CGRect) -> CGRect
    private let capture: (UIWindow) -> UIImage?
    private let recognize: (UIImage) async -> [BugReportTextLine]
    private let probeSource: () -> [BugReportProbeView]

    private(set) var lines: [BugReportTextLine] = []
    private(set) var linesReady = false
    private var recognition: Task<Void, Never>?
    private var lastPoint: CGPoint?

    /// - Parameters:
    ///   - appWindow: The `.normal`-level window the app draws in.
    ///   - toAppWindow: Pick-layer points → app-window points.
    ///   - toLayer: App-window rects → pick-layer rects.
    ///   - capture: Draws the app window. Defaults to the capture service.
    ///   - probeSource: The mounted probes. Defaults to the pick-mode registry.
    init(
        appWindow: UIWindow,
        screenName: String,
        toAppWindow: @escaping (CGPoint) -> CGPoint = { $0 },
        toLayer: @escaping (CGRect) -> CGRect = { $0 },
        capture: ((UIWindow) -> UIImage?)? = nil,
        recognize: @escaping (UIImage) async -> [BugReportTextLine] = BugReportTextRecognizer.recognize,
        probeSource: (() -> [BugReportProbeView])? = nil
    ) {
        self.appWindow = appWindow
        self.screenName = screenName
        self.toAppWindow = toAppWindow
        self.toLayer = toLayer
        self.capture = capture ?? { BugReportCaptureService.render($0) }
        self.recognize = recognize
        self.probeSource = probeSource ?? { BugReportPickMode.shared.registeredProbes }
    }

    // MARK: Arm

    /// Captures the app window and starts Vision on it — once per session.
    /// The app is frozen under the pick layer (the layer takes every touch),
    /// so this capture is the screen the operator is looking at.
    func arm() {
        guard recognition == nil, let appWindow, let shot = capture(appWindow) else {
            linesReady = true
            return
        }
        let recognize = recognize
        recognition = Task { [weak self] in
            let read = await recognize(shot)
            guard let self, !Task.isCancelled else { return }
            self.lines = read
            self.linesReady = true
            // A finger already down gets its label the moment it exists.
            if self.isTracking, let point = self.lastPoint {
                self.target = self.resolve(at: point)
            }
        }
    }

    /// Test seam: a session whose text is already known.
    func prime(lines: [BugReportTextLine]) {
        self.lines = lines
        linesReady = true
    }

    // MARK: Track

    /// The finger is down or moving at `layerPoint`.
    func track(at layerPoint: CGPoint) {
        guard !isCommitted else { return }
        let point = toAppWindow(layerPoint)
        if let lastPoint, isTracking,
           abs(lastPoint.x - point.x) < 0.5, abs(lastPoint.y - point.y) < 0.5 {
            return
        }
        lastPoint = point
        isTracking = true
        target = resolve(at: point)
    }

    // MARK: Commit

    /// The finger lifted at `layerPoint`. Measures the probes and captures
    /// the app window NOW — so the screenshot is the screen the rect was
    /// measured on — then waits (bounded) for Vision to name it.
    func commit(at layerPoint: CGPoint) async -> BugReportDraft.MarkedSpot? {
        guard !isCommitted, let appWindow else { return nil }
        isCommitted = true
        isTracking = false

        let point = toAppWindow(layerPoint)
        lastPoint = point
        let viewport = appWindow.bounds.size
        let probes = BugReportProbeCollector.candidates(
            at: point,
            in: appWindow,
            probes: probeSource()
        )
        let screenshot = capture(appWindow)

        target = BugReportPickResolver.resolve(
            point: point,
            probes: probes,
            lines: lines,
            viewport: viewport
        )

        await waitForText(limit: Self.textWaitLimit)

        let resolution = BugReportPickResolver.resolve(
            point: point,
            probes: probes,
            lines: lines,
            viewport: viewport
        )
        target = resolution

        return BugReportDraft.MarkedSpot(
            element: BugReportElementPick(
                resolution: resolution,
                point: point,
                viewport: viewport,
                screen: screenName
            ),
            screenshot: screenshot
        )
    }

    func cancel() {
        recognition?.cancel()
        isTracking = false
    }

    // MARK: Drawing

    /// A target rect in the pick layer's own coordinates.
    func layerRect(for rect: CGRect) -> CGRect {
        toLayer(rect)
    }

    // MARK: Internals

    private func resolve(at point: CGPoint) -> BugReportPickResolution? {
        guard let appWindow else { return nil }
        return BugReportPickResolver.resolve(
            point: point,
            probes: BugReportProbeCollector.candidates(
                at: point,
                in: appWindow,
                probes: probeSource()
            ),
            lines: lines,
            viewport: appWindow.bounds.size
        )
    }

    private func waitForText(limit: TimeInterval) async {
        let deadline = Date(timeIntervalSinceNow: limit)
        while !linesReady, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
