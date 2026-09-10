//
//  BugReportScreenshotViewer.swift
//  OPS
//
//  The report's screenshot, full screen: drag down or CLOSE to leave. When the
//  operator picked an element with POINT AT IT, it is outlined on the shot —
//  the same outline the evidence card's thumbnail carries.
//
//  Display only. Picking happens on the live app now (bug 14e5a792), not by
//  aiming at this picture.
//
//  Kept as its own view so it can be rendered on its own: a `fullScreenCover`
//  presents outside its host's view, so a snapshot of the sheet never
//  captures the cover.
//

import SwiftUI
import UIKit

struct BugReportScreenshotViewer: View {
    let image: UIImage?
    /// The picked element, outlined when present.
    let element: BugReportElementPick?
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            if let image {
                shot(image)
                    .offset(y: dragOffset)
            }

            controls
        }
        .opacity(1.0 - Double(dragOffset) / 400.0)
    }

    // MARK: - The shot

    private func shot(_ image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)

                if let element {
                    BugReportMarkOutline(
                        element: element,
                        imageSize: image.size,
                        container: geo.size
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(dismissGesture)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    onClose()
                }
                withAnimation(OPSStyle.Animation.spring) {
                    dragOffset = 0
                }
            }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)

                Button(action: onClose) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.xmark)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .bold))
                        Text("CLOSE")
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(OPSStyle.Typography.trackingCompact)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.overlayMedium)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, OPSStyle.Layout.spacing3)
            }
            .padding(.top, OPSStyle.Layout.spacing5 + OPSStyle.Layout.spacing4)

            Spacer()
        }
    }
}

// MARK: - The outline on a shot

/// The picked element's rect, drawn on an aspect-fit screenshot of any size.
///
/// `text` white at the outline weight, over a dark halo: the halo is what
/// keeps the line readable when the element itself is white or light.
struct BugReportMarkOutline: View {
    let element: BugReportElementPick
    let imageSize: CGSize
    let container: CGSize

    var body: some View {
        let fitted = BugReportShotGeometry.fittedRect(imageSize: imageSize, in: container)
        let rect = BugReportShotGeometry.project(
            element.resolution.outlineRect,
            from: element.viewport,
            into: fitted
        )
        let scale = element.viewport.width > 0 ? fitted.width / element.viewport.width : 1
        let radius = OPSStyle.Layout.buttonRadius * scale

        ZStack(alignment: .topLeading) {
            BugReportPickOutline(rect: rect, cornerRadius: radius)
                .stroke(OPSStyle.Colors.overlayMedium, lineWidth: OPSStyle.Layout.Border.outline * 3)
            BugReportPickOutline(rect: rect, cornerRadius: radius)
                .stroke(OPSStyle.Colors.text, lineWidth: OPSStyle.Layout.Border.outline)
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
