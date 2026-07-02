//
//  ProjectLocationSnapshotView.swift
//  OPS
//
//  Static, non-interactive 2D map snapshot for the project details header.
//
//  Replaces the live `MapView`-backed header (`ProjectLocationMapView`), which
//  streamed vector tiles, ran a live location puck, and kept a Metal renderer
//  hot behind the ENTIRE project-details scroll — the primary source of the
//  scroll / tab-switch lag that vanished in airplane mode. A Mapbox
//  `Snapshotter` renders the map to a single `UIImage` once, then releases all
//  GPU + tile resources. Nothing keeps rendering while the operator scrolls.
//
//  The header is display-only: no pan, zoom, rotate, or 3D. Just a flat
//  top-down frame of where the project is, the OPS project pin, and — only
//  when the operator is standing inside the framed area — a "you are here" dot.
//

import SwiftUI
import MapboxMaps
import CoreLocation

struct ProjectLocationSnapshotView: View {

    let coordinate: CLLocationCoordinate2D
    let projectName: String
    let status: Status
    let taskColorHexes: [String]

    /// Operator's current location. A dot is drawn ONLY when this falls within
    /// the snapshot's framed bounds (i.e. they're near the project). Nil or
    /// out-of-frame → no dot, and never a permission prompt.
    var userCoordinate: CLLocationCoordinate2D?

    /// Wider-area framing so the pin reads with a little surrounding context.
    var zoomLevel: Double = 13.0

    @AppStorage("mapStyle") private var mapStyleRaw = "dark"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var loader = ProjectLocationSnapshotLoader()

    /// Bumped when connectivity returns while we still have no image — an
    /// offline-open otherwise left the header a flat color block for the
    /// whole session (the render key never changes on reconnect).
    @State private var retryToken = 0

    private var style: OPSMapStyle { OPSMapStyle(rawValue: mapStyleRaw) ?? .dark }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Land-color base — identical to the map's land fill, so the
                // header reads as "map" instantly and the snapshot fades in
                // with no black flash while it renders.
                Color(uiColor: style.backgroundColor)

                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(reduceMotion ? nil : OPSStyle.Animation.standard, value: loader.image)
            .task(id: taskID(size: geo.size)) {
                loader.render(
                    coordinate: coordinate,
                    projectName: projectName,
                    status: status,
                    taskColorHexes: taskColorHexes,
                    userCoordinate: userCoordinate,
                    zoom: zoomLevel,
                    style: style,
                    size: geo.size
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: ConnectivityManager.connectivityChangedNotification
            )) { _ in
                if loader.image == nil { retryToken &+= 1 }
            }
        }
    }

    /// Stable identity for the snapshot. Internal + nonisolated static so the
    /// gating rules are unit-testable (pattern: RealtimeProcessor.subscribeRetryDelay).
    ///
    /// The operator's position folds into the identity ONLY when they are
    /// close enough to plausibly land inside the framed area (the zoom-13
    /// header frame is ~3 km across; 2.5 km is the conservative gate — the
    /// dot draw itself still exact-checks pixel bounds). Without the gate, a
    /// driving operator forced a full Snapshotter spin-up every ~100 m of
    /// travel anywhere on earth. Near the project, ~100 m buckets still
    /// refresh the dot on meaningful moves while absorbing GPS jitter.
    nonisolated static func renderKey(
        projectCoordinate: CLLocationCoordinate2D,
        userCoordinate: CLLocationCoordinate2D?,
        size: CGSize,
        styleRaw: String,
        taskColorHexes: [String],
        statusDescription: String
    ) -> String {
        let lat = (projectCoordinate.latitude * 10_000).rounded() / 10_000
        let lng = (projectCoordinate.longitude * 10_000).rounded() / 10_000
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())

        var user = "none"
        if let u = userCoordinate {
            let userLocation = CLLocation(latitude: u.latitude, longitude: u.longitude)
            let projectLocation = CLLocation(
                latitude: projectCoordinate.latitude,
                longitude: projectCoordinate.longitude
            )
            if userLocation.distance(from: projectLocation) <= 2_500 {
                let ulat = (u.latitude * 1_000).rounded() / 1_000
                let ulng = (u.longitude * 1_000).rounded() / 1_000
                user = "\(ulat),\(ulng)"
            }
        }

        let ring = taskColorHexes.joined(separator: "-")
        return "\(lat),\(lng)|\(w)x\(h)|\(styleRaw)|\(ring)|\(statusDescription)|\(user)"
    }

    private func taskID(size: CGSize) -> String {
        Self.renderKey(
            projectCoordinate: coordinate,
            userCoordinate: userCoordinate,
            size: size,
            styleRaw: style.rawValue,
            taskColorHexes: taskColorHexes,
            statusDescription: String(describing: status)
        ) + "|r\(retryToken)"
    }
}

// MARK: - Snapshot Loader

/// Owns the async `Snapshotter` lifecycle and publishes the rendered image.
/// A dedicated `ObservableObject` (rather than raw `@State`) so the snapshotter
/// and its style-load subscription stay retained until the render completes,
/// and so an in-flight render is cancelled cleanly when inputs change.
@MainActor
final class ProjectLocationSnapshotLoader: ObservableObject {

    @Published private(set) var image: UIImage?

    private var snapshotter: Snapshotter?
    private var cancelables = Set<AnyCancelable>()

    func render(
        coordinate: CLLocationCoordinate2D,
        projectName: String,
        status: Status,
        taskColorHexes: [String],
        userCoordinate: CLLocationCoordinate2D?,
        zoom: Double,
        style: OPSMapStyle,
        size: CGSize
    ) {
        guard size.width > 1, size.height > 1 else { return }

        // Supersede any in-flight render.
        snapshotter?.cancel()
        cancelables.removeAll()

        let options = MapSnapshotOptions(
            size: size,
            pixelRatio: UIScreen.main.scale
        )
        let snapshotter = Snapshotter(options: options)
        self.snapshotter = snapshotter

        snapshotter.styleURI = style.baseStyleURI
        // pitch 0 → flat top-down. No bearing, no tilt, no 3D.
        snapshotter.setCamera(to: CameraOptions(center: coordinate, zoom: zoom, pitch: 0))

        // Render the pin off the render loop, up front — reuses the exact pin
        // the live map draws so the header stays visually identical.
        let pin = ProjectAnnotationRenderer.renderProject(
            name: projectName,
            status: status,
            taskColorHexes: taskColorHexes,
            isSelected: true
        )
        let dotColor = UIColor(OPSStyle.Colors.primaryAccent)

        snapshotter.onStyleLoaded.observeNext { [weak self, weak snapshotter] _ in
            guard let snapshotter else { return }

            // Recolor the base Mapbox style to the OPS profile — same override
            // pass the live map runs — and force 2D (hide building extrusions).
            MapStyleApplicator.apply(style, to: snapshotter, show3DBuildings: false)

            snapshotter.start(overlayHandler: { overlay in
                Self.draw(pin: pin, at: coordinate, in: overlay)
                if let userCoordinate {
                    Self.drawUserDot(at: userCoordinate, color: dotColor, in: overlay, size: size)
                }
            }, completion: { [weak self] result in
                guard let self else { return }
                if case .success(let rendered) = result {
                    self.image = rendered
                }
                // Release GPU/tile resources — the whole point of the snapshot.
                self.snapshotter = nil
                self.cancelables.removeAll()
            })
        }
        .store(in: &cancelables)
    }

    deinit {
        snapshotter?.cancel()
    }

    // MARK: - Overlay Drawing

    /// Draw the project pin bottom-anchored at its coordinate — matching the
    /// live map's `iconAnchor = .bottom` so the pin sits identically.
    private static func draw(pin: UIImage, at coordinate: CLLocationCoordinate2D, in overlay: SnapshotOverlay) {
        let point = overlay.pointForCoordinate(coordinate)
        let origin = CGPoint(x: point.x - pin.size.width / 2, y: point.y - pin.size.height)
        UIGraphicsPushContext(overlay.context)
        pin.draw(at: origin)
        UIGraphicsPopContext()
    }

    /// Draw a "you are here" dot — but only if the operator is fully inside the
    /// framed area. Out-of-frame coordinates project outside the image rect and
    /// are skipped, satisfying "show it only if within the bounds of the snapshot."
    private static func drawUserDot(
        at coordinate: CLLocationCoordinate2D,
        color: UIColor,
        in overlay: SnapshotOverlay,
        size: CGSize
    ) {
        let point = overlay.pointForCoordinate(coordinate)
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.insetBy(dx: 10, dy: 10).contains(point) else { return }

        let ctx = overlay.context
        ctx.saveGState()

        // Soft accuracy halo
        let haloRadius: CGFloat = 16
        ctx.setFillColor(color.withAlphaComponent(0.18).cgColor)
        ctx.fillEllipse(in: CGRect(
            x: point.x - haloRadius, y: point.y - haloRadius,
            width: haloRadius * 2, height: haloRadius * 2
        ))

        // White contrast ring under the core, for legibility on the dark map
        let ringRadius: CGFloat = 7
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: point.x - ringRadius, y: point.y - ringRadius,
            width: ringRadius * 2, height: ringRadius * 2
        ))

        // Accent core
        let coreRadius: CGFloat = 5
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(
            x: point.x - coreRadius, y: point.y - coreRadius,
            width: coreRadius * 2, height: coreRadius * 2
        ))

        ctx.restoreGState()
    }
}
