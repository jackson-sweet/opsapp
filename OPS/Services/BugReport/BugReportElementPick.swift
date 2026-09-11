//
//  BugReportElementPick.swift
//  OPS
//
//  POINT AT IT, rebuilt (bug 14e5a792, follow-up to 5aabcc3a).
//
//  The first version resolved a tap on a frozen screenshot against a
//  flattened UIView tree. On a real phone that tree is almost entirely
//  SwiftUI rendering containers, so Jackson's first real mark named
//  `PlatformGroupContainer` with no label — true, and useless. SwiftUI also
//  publishes no accessibility elements unless an assistive technology is
//  running, so the accessibility tree is no better a source.
//
//  The operator now picks on the LIVE app. What the finger lands on is named
//  from three sources, in this order:
//
//    1. COMPONENT — a probe the house components mount while a pick session
//       is running (`bugReportPickable`). It knows the role and, often, the
//       label, because the component itself said so.
//    2. TEXT — a line Vision read off the pick-time capture, when no probe
//       sits under the finger.
//    3. REGION — a 44×44pt square around the point, when neither applies.
//
//  Everything in this file is pure: rules in, answer out. The UIKit side
//  (which probes are really on screen, in the frontmost presentation) lives
//  in `BugReportPickProbe.swift`; Vision lives in
//  `BugReportTextRecognizer.swift`. That split is what lets the ordering
//  rules be pinned by unit tests with synthetic probes.
//

import CoreGraphics
import Foundation

// MARK: - Role

/// What kind of thing was picked. The raw value is what the report records
/// (`elementReferences[].role`) and what the pick layer's tag shows.
enum BugReportPickRole: String, CaseIterable, Equatable {
    case button
    case field
    case select
    case toggle
    case chip
    case row
    case card
    /// A line of text Vision read, with no component under it.
    case text
    /// Nothing nameable — a 44×44pt square around the point.
    case region

    /// Final tie-break when two probes cover exactly the same rect at the same
    /// depth — a list row and the glass card it is drawn on, typically. The
    /// more specific control is the more useful answer.
    var specificity: Int {
        switch self {
        case .button: return 6
        case .field, .select, .toggle: return 5
        case .chip: return 4
        case .row: return 3
        case .card: return 2
        case .text: return 1
        case .region: return 0
        }
    }
}

/// Which of the three sources produced the answer. Recorded as
/// `elementReferences[].source` so triage knows how much to trust the name.
enum BugReportPickSource: String, Equatable {
    case component
    case text
    case region
}

// MARK: - Inputs

/// One line Vision read off the pick-time capture, in app-window points.
struct BugReportTextLine: Equatable {
    let text: String
    let frame: CGRect
}

/// One mounted probe, as the UIKit collector measured it at the pick point.
///
/// The collector records the facts; `BugReportPickResolver` applies the
/// rules. Keeping the two apart is what makes "a probe under a covering
/// sheet never wins" a unit-testable statement rather than a hope.
struct BugReportProbeCandidate: Equatable {
    /// The element's frame in app-window points.
    let frame: CGRect
    /// The intersection of every clipping ancestor's bounds, in app-window
    /// points. A card scrolled half under a header still has its full frame,
    /// but only the unclipped part is on screen. Nil when nothing clips it.
    let clipRect: CGRect?
    /// Superview depth below the window. Deeper wins an area tie.
    let depth: Int
    /// Any ancestor (or the probe itself) is hidden.
    let isHiddenInHierarchy: Bool
    /// Product of every ancestor's layer opacity, the probe's own included.
    let cumulativeAlpha: CGFloat
    /// The probe is mounted in the app window — not a stray window.
    let isInAppWindow: Bool
    /// The probe sits inside the frontmost presentation at the pick point.
    /// False for content under a sheet or cover.
    let isInFrontmostPresentation: Bool
    let role: BugReportPickRole
    /// The label the component supplied, if any.
    let label: String?
    /// The source file that mounted the probe, e.g. `ButtonStyles`.
    let component: String?

    init(
        frame: CGRect,
        clipRect: CGRect? = nil,
        depth: Int = 0,
        isHiddenInHierarchy: Bool = false,
        cumulativeAlpha: CGFloat = 1,
        isInAppWindow: Bool = true,
        isInFrontmostPresentation: Bool = true,
        role: BugReportPickRole,
        label: String? = nil,
        component: String? = nil
    ) {
        self.frame = frame
        self.clipRect = clipRect
        self.depth = depth
        self.isHiddenInHierarchy = isHiddenInHierarchy
        self.cumulativeAlpha = cumulativeAlpha
        self.isInAppWindow = isInAppWindow
        self.isInFrontmostPresentation = isInFrontmostPresentation
        self.role = role
        self.label = label
        self.component = component
    }
}

// MARK: - Output

/// What the finger landed on — the answer the pick layer tags while the
/// finger is down, and the core of the mark once it lifts.
struct BugReportPickResolution: Equatable {
    let source: BugReportPickSource
    let role: BugReportPickRole
    /// App-window points.
    let rect: CGRect
    /// Never empty: the component's own label, else the text read inside the
    /// rect, else the role.
    let label: String
    /// Every line read inside the rect, reading order. Empty when none.
    let text: String
    let component: String?

    /// True when nothing better than the role was available — a pure icon, or
    /// a region with no text in it.
    var labelIsRole: Bool { label == role.rawValue }

    /// The pick layer's tag: the kind first, because that is what the finger
    /// is asking — "is this the button?" — e.g. `BUTTON · START`.
    var tagText: String {
        labelIsRole
            ? role.rawValue.uppercased()
            : "\(role.rawValue.uppercased()) · \(label.uppercased())"
    }

    /// The evidence card's second line: the name first, because that is what
    /// the operator recognises afterwards — e.g. `START · BUTTON`.
    var cardText: String {
        labelIsRole
            ? role.rawValue.uppercased()
            : "\(label.uppercased()) · \(role.rawValue.uppercased())"
    }
}

/// A finished pick: the resolution, plus where and when it happened.
struct BugReportElementPick: Equatable {
    /// Lowercase UUID — the same form every other OPS id takes.
    let id: String
    let resolution: BugReportPickResolution
    /// Where the finger lifted, app-window points.
    let point: CGPoint
    /// App-window size — the space `rect` and `point` are measured in, and
    /// the size of the pick-time screenshot.
    let viewport: CGSize
    /// `BugReportCaptureService.currentScreenName` at pick time.
    let screen: String
    let capturedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        resolution: BugReportPickResolution,
        point: CGPoint,
        viewport: CGSize,
        screen: String,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.resolution = resolution
        self.point = point
        self.viewport = viewport
        self.screen = screen
        self.capturedAt = capturedAt
    }
}

// MARK: - Resolution rules

enum BugReportPickResolver {

    /// A probe fainter than this is not something the operator can see.
    static let minimumVisibleAlpha: CGFloat = 0.01
    /// A text line counts as touched within this much of its box — Vision's
    /// boxes hug the glyphs, and a fingertip is wider than a cap height.
    static let textHitSlop: CGFloat = 8
    /// The fallback region's side: the field-minimum touch target.
    static let regionSide: CGFloat = 44
    /// Label cap — enough to name a control, short enough to read in a tag.
    static let labelLimit = 80
    /// Text cap — matches the web picker's snippet cap.
    static let textLimit = 120

    // MARK: Probes

    /// Could the operator have been touching this probe?
    static func isEligible(_ probe: BugReportProbeCandidate, at point: CGPoint) -> Bool {
        guard probe.frame.width >= 1, probe.frame.height >= 1 else { return false }
        guard probe.isInAppWindow, probe.isInFrontmostPresentation else { return false }
        guard !probe.isHiddenInHierarchy else { return false }
        guard probe.cumulativeAlpha > minimumVisibleAlpha else { return false }
        guard probe.frame.contains(point) else { return false }
        if let clip = probe.clipRect, !clip.contains(point) { return false }
        return true
    }

    /// The probe the operator meant: the smallest eligible one under the
    /// finger — a button inside a card, never the card around the button.
    /// Deeper wins an area tie; the more specific role wins after that.
    static func frontmostProbe(
        at point: CGPoint,
        among probes: [BugReportProbeCandidate]
    ) -> BugReportProbeCandidate? {
        probes
            .filter { isEligible($0, at: point) }
            .min { lhs, rhs in
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                if abs(lhsArea - rhsArea) > 1 { return lhsArea < rhsArea }
                if lhs.depth != rhs.depth { return lhs.depth > rhs.depth }
                return lhs.role.specificity > rhs.role.specificity
            }
    }

    // MARK: Text

    /// The line under the finger, if any: the closest line whose box, grown by
    /// `textHitSlop`, contains the point. A tighter box wins a distance tie.
    static func textLine(
        at point: CGPoint,
        in lines: [BugReportTextLine]
    ) -> BugReportTextLine? {
        lines
            .filter {
                !collapse($0.text).isEmpty
                    && $0.frame.insetBy(dx: -textHitSlop, dy: -textHitSlop).contains(point)
            }
            .min { lhs, rhs in
                let lhsDistance = distance(from: point, to: lhs.frame)
                let rhsDistance = distance(from: point, to: rhs.frame)
                if abs(lhsDistance - rhsDistance) > 0.5 { return lhsDistance < rhsDistance }
                return lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
            }
    }

    /// Every line whose centre falls inside `rect`, in reading order —
    /// top-to-bottom by row, left-to-right within a row — joined by spaces
    /// and capped at `limit`. Nil when nothing was read there.
    static func text(
        inside rect: CGRect,
        lines: [BugReportTextLine],
        limit: Int
    ) -> String? {
        let inside = lines.filter {
            !collapse($0.text).isEmpty
                && rect.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        guard !inside.isEmpty else { return nil }

        let joined = readingOrder(inside)
            .map { collapse($0.text) }
            .joined(separator: " ")
        return clamp(joined, to: limit)
    }

    /// Rows first, then columns. Two lines share a row when their vertical
    /// centres sit within half the shorter line's height — Vision reports a
    /// button's label and the chip beside it a pixel or two apart.
    static func readingOrder(_ lines: [BugReportTextLine]) -> [BugReportTextLine] {
        let byCentre = lines.sorted { $0.frame.midY < $1.frame.midY }
        var rows: [[BugReportTextLine]] = []
        for line in byCentre {
            if let anchor = rows.last?.first,
               abs(line.frame.midY - anchor.frame.midY)
                    <= min(line.frame.height, anchor.frame.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { row in row.sorted { $0.frame.minX < $1.frame.minX } }
    }

    // MARK: Region

    /// A 44×44pt square centred on the point, kept inside the viewport.
    static func regionRect(around point: CGPoint, viewport: CGSize) -> CGRect {
        let side = regionSide
        let maxX = max(0, viewport.width - side)
        let maxY = max(0, viewport.height - side)
        let x = min(max(0, point.x - side / 2), maxX)
        let y = min(max(0, point.y - side / 2), maxY)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    // MARK: The answer

    /// Component, else text, else region — and the label rule applied the
    /// same way to all three: the component's own label, else the text read
    /// inside the rect, else the role.
    static func resolve(
        point: CGPoint,
        probes: [BugReportProbeCandidate],
        lines: [BugReportTextLine],
        viewport: CGSize
    ) -> BugReportPickResolution {
        if let probe = frontmostProbe(at: point, among: probes) {
            let label = nonEmpty(probe.label).map { clamp($0, to: labelLimit) }
                ?? text(inside: probe.frame, lines: lines, limit: labelLimit)
                ?? probe.role.rawValue
            return BugReportPickResolution(
                source: .component,
                role: probe.role,
                rect: probe.frame,
                label: label,
                text: text(inside: probe.frame, lines: lines, limit: textLimit) ?? "",
                component: probe.component
            )
        }

        if let line = textLine(at: point, in: lines) {
            let spoken = collapse(line.text)
            return BugReportPickResolution(
                source: .text,
                role: .text,
                rect: line.frame,
                label: clamp(spoken, to: labelLimit),
                text: clamp(spoken, to: textLimit),
                component: nil
            )
        }

        let region = regionRect(around: point, viewport: viewport)
        return BugReportPickResolution(
            source: .region,
            role: .region,
            rect: region,
            label: text(inside: region, lines: lines, limit: labelLimit) ?? BugReportPickRole.region.rawValue,
            text: text(inside: region, lines: lines, limit: textLimit) ?? "",
            component: nil
        )
    }

    // MARK: Helpers

    static func collapse(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Cap at `limit` characters. A cut string ends in an ellipsis so the
    /// reader knows there was more; the ellipsis counts toward the cap.
    static func clamp(_ value: String, to limit: Int) -> String {
        let collapsed = collapse(value)
        guard collapsed.count > limit, limit > 1 else { return collapsed }
        let cut = collapsed.prefix(limit - 1).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = collapse(value)
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Drawing a mark on a shot

enum BugReportShotGeometry {

    /// Where an aspect-fit image actually sits inside its container. `.zero`
    /// for a degenerate container or image.
    static func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// A rect measured in `viewport` points, re-expressed inside the fitted
    /// image rect — how the evidence card draws the picked element on a
    /// thumbnail of any size.
    static func project(_ rect: CGRect, from viewport: CGSize, into fitted: CGRect) -> CGRect {
        guard viewport.width > 0, viewport.height > 0 else { return .zero }
        let sx = fitted.width / viewport.width
        let sy = fitted.height / viewport.height
        return CGRect(
            x: fitted.minX + rect.minX * sx,
            y: fitted.minY + rect.minY * sy,
            width: rect.width * sx,
            height: rect.height * sy
        )
    }
}

// MARK: - The report payload

extension BugReportElementPick {

    /// ISO-8601 with milliseconds and a `Z`, exactly what the web picker's
    /// `new Date().toISOString()` produces.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// One entry of `custom_metadata.elementReferences`, in the web picker's
    /// shape (`ElementReference`, ops-web `src/lib/types/bug-report-element.ts`)
    /// so the admin bug console reads an iOS pick the same way it reads a web
    /// one.
    ///
    /// Mapped honestly:
    /// - `selector`, `classes`, `tag` are DOM concepts with no iOS meaning.
    ///   The web contract types them as non-optional strings, and the admin
    ///   reader drops any reference whose `selector` is not a string — so they
    ///   are written as empty strings (absent), never as invented values and
    ///   never as null.
    /// - `testId` is nullable in the contract, so it is null.
    /// - `attachmentIndex` indexes the report's element-crop attachments
    ///   (`additional_attachments`). iOS uploads no crop — the picked rect is
    ///   measured against the report's own screenshot, which IS the pick-time
    ///   capture — so it is null, which the admin renders as "no crop" rather
    ///   than a crop that never loads.
    /// - `page` is the element's origin; an iOS window does not scroll, so it
    ///   equals the rect's origin. `componentChain` names the house component
    ///   that mounted the probe, when one did.
    /// - iOS adds `source`, `screen` and `point` (where the finger lifted).
    var elementReference: [String: JSONPrimitive] {
        let rect = resolution.rect
        return [
            "id": .string(id),
            "label": .string(resolution.label),
            "role": .string(resolution.role.rawValue),
            "tag": .string(""),
            "selector": .string(""),
            "classes": .string(""),
            "testId": .null,
            "text": .string(resolution.text),
            "rect": .nested([
                "x": .double(Double(rect.minX)),
                "y": .double(Double(rect.minY)),
                "width": .double(Double(rect.width)),
                "height": .double(Double(rect.height))
            ]),
            "page": .nested([
                "x": .double(Double(rect.minX)),
                "y": .double(Double(rect.minY))
            ]),
            "viewport": .nested([
                "width": .double(Double(viewport.width)),
                "height": .double(Double(viewport.height))
            ]),
            "componentChain": .nestedArray(resolution.component.map { [.string($0)] } ?? []),
            "capturedAt": .string(Self.timestampFormatter.string(from: capturedAt)),
            "attachmentIndex": .null,
            "source": .string(resolution.source.rawValue),
            "screen": .string(screen),
            "point": .nested([
                "x": .double(Double(point.x)),
                "y": .double(Double(point.y))
            ])
        ]
    }
}
