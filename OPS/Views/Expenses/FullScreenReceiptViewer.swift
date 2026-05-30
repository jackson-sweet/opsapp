//
//  FullScreenReceiptViewer.swift
//  OPS
//
//  Full-screen receipt image viewer with pinch-to-zoom, pan, and swipe-to-dismiss.
//

import SwiftUI

struct FullScreenReceiptViewer: View {
    let imageUrl: String

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            receiptImage

            closeButton
        }
        .statusBarHidden(true)
    }

    // MARK: - Receipt Image

    private var receiptImage: some View {
        AsyncImage(url: URL(string: imageUrl)) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .tint(OPSStyle.Colors.loadingSpinner)

            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(
                        x: offset.width + dragOffset.width,
                        y: offset.height + dragOffset.height
                    )
                    .gesture(magnifyGesture)
                    .gesture(panGesture)
                    .gesture(doubleTapGesture)

            case .failure:
                errorState

            @unknown default:
                ProgressView()
                    .tint(OPSStyle.Colors.loadingSpinner)
            }
        }
    }

    // MARK: - Error State

    private var errorState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(OPSStyle.Icons.alert)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.warningStatus)

            Text("Failed to load receipt")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(OPSStyle.Icons.xmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.overlayMedium)
                        .clipShape(Circle())
                }
                .padding(.top, OPSStyle.Layout.spacing5 + OPSStyle.Layout.spacing4)
                .padding(.trailing, OPSStyle.Layout.spacing3_5)
            }
            Spacer()
        }
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = max(newScale, 1.0)
            }
            .onEnded { value in
                let newScale = lastScale * value.magnification
                if newScale < 1.0 {
                    withAnimation(OPSStyle.Animation.smooth) {
                        scale = 1.0
                        offset = .zero
                    }
                    lastScale = 1.0
                    lastOffset = .zero
                } else {
                    lastScale = scale
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                if scale > 1.0 {
                    state = value.translation
                } else {
                    state = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { value in
                if scale > 1.0 {
                    // Panning while zoomed in
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    lastOffset = offset
                } else {
                    // Swipe down to dismiss at 1.0x
                    if value.translation.height > 100 {
                        dismiss()
                    }
                }
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(OPSStyle.Animation.smooth) {
                    if scale > 1.0 {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                        lastScale = 1.0
                    } else {
                        scale = 3.0
                        lastScale = 3.0
                    }
                }
            }
    }
}

// MARK: - Preview

#Preview {
    FullScreenReceiptViewer(imageUrl: "https://example.com/receipt.jpg")
}
