//
//  BugReportScreenshotViewer.swift
//  OPS
//
//  The captured shot, full screen — and, when armed, the POINT AT IT surface
//  (bug 5aabcc3a).
//
//  One view, two modes. Unarmed it is the plain enlarge view the bug report has
//  always had: drag down to dismiss, CLOSE in the corner. Armed it takes exactly
//  one tap and leaves. Drag-to-dismiss is suspended while armed — the operator
//  is aiming, and a stray downward drag should not throw the aim away — so SKIP
//  is the way out, and it is right where CLOSE was.
//
//  Extracted from `BugReportSheet` so it can be rendered on its own: a
//  `fullScreenCover` presents outside its host's view, which means a snapshot
//  of the sheet captures the sheet, never the cover.
//

import SwiftUI
import UIKit

struct BugReportScreenshotViewer: View {
    let image: UIImage?
    /// Drawn whenever present, in either mode.
    let mark: BugReportElementMark?
    /// Armed for a single tap.
    let isPointing: Bool
    /// Called with a 0…1 position inside the image. A tap on the letterbox
    /// never reaches here — the operator pointed at nothing.
    let onPlace: (CGPoint) -> Void
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                shot(image)
                    .offset(y: isPointing ? 0 : dragOffset)
            }

            controls
        }
        .opacity(1.0 - Double(dragOffset) / 400.0)
    }

    // MARK: - The shot

    private func shot(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let rect = BugReportElementHitTest.fittedRect(
                imageSize: image.size,
                in: geo.size
            )
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)

                if let mark {
                    markRing
                        .position(
                            x: rect.minX + mark.normalized.x * rect.width,
                            y: rect.minY + mark.normalized.y * rect.height
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(gesture(in: geo.size, imageSize: image.size))
        }
    }

    /// The one accent element on this surface: a ring on the spot, with a solid
    /// centre so the exact point is unambiguous at any zoom.
    ///
    /// The dark halo underneath is legibility, not decoration — the mark can
    /// land on a filled accent CTA, where a bare steel-blue ring disappears.
    private var markRing: some View {
        ZStack {
            Circle()
                .stroke(OPSStyle.Colors.background.opacity(0.6), lineWidth: 5)
                .frame(width: 36, height: 36)
            Circle()
                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                .frame(width: 36, height: 36)
            Circle()
                .fill(OPSStyle.Colors.background.opacity(0.6))
                .frame(width: 9, height: 9)
            Circle()
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Gestures

    /// Armed: a zero-distance drag, read as a tap, places the mark. Unarmed:
    /// the long-standing drag-down-to-dismiss.
    private func gesture(in container: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: isPointing ? 0 : 10)
            .onChanged { value in
                guard !isPointing, value.translation.height > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if isPointing {
                    guard let normalized = BugReportElementHitTest.normalizedPoint(
                        ofTap: value.location,
                        in: container,
                        imageSize: imageSize
                    ) else { return }
                    onPlace(normalized)
                    return
                }
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
            HStack(alignment: .top) {
                if isPointing {
                    Text("[TAP THE SPOT]")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.overlayMedium)
                        .clipShape(Capsule())
                        .padding(.leading, OPSStyle.Layout.spacing3)
                        .allowsHitTesting(false)
                }

                Spacer(minLength: 0)

                Button(action: onClose) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: OPSStyle.Icons.xmark)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .bold))
                        Text(isPointing ? "SKIP" : "CLOSE")
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(0.5)
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
