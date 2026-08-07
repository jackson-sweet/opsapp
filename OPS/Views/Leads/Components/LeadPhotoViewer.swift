//
//  LeadPhotoViewer.swift
//  OPS
//
//  Full-screen pager for lead photos. Black canvas, mono counter, explicit
//  close (full sheets never scrim-dismiss — MOBILE.md §6.3). Pinch +
//  double-tap zoom per page. DELETE (pipeline.manage only) confirms, then
//  removes via LeadImageService — remote URLs PATCH the row, queued tiles
//  drop from the local queue.
//

import SwiftUI

/// Identifiable payload for `.fullScreenCover(item:)`.
struct LeadPhotoViewerState: Identifiable {
    let id = UUID()
    let items: [LeadPhotoItem]
    let initialIndex: Int
}

struct LeadPhotoViewer: View {
    let opportunity: Opportunity
    let canManage: Bool
    let initialState: LeadPhotoViewerState

    @Environment(\.dismiss) private var dismiss
    @State private var items: [LeadPhotoItem]
    @State private var currentIndex: Int
    @State private var confirmingDelete = false
    @State private var isDeleting = false

    init(opportunity: Opportunity, canManage: Bool, initialState: LeadPhotoViewerState) {
        self.opportunity = opportunity
        self.canManage = canManage
        self.initialState = initialState
        _items = State(initialValue: initialState.items)
        _currentIndex = State(initialValue: initialState.initialIndex)
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ZoomablePhotoPage(item: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if canManage && currentItemCanDelete {
                    deleteBar
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "DELETE THIS PHOTO?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("DELETE PHOTO", role: .destructive) { deleteCurrent() }
            Button("KEEP", role: .cancel) {}
        } message: {
            Text("Removed from this lead for everyone.")
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Text(counterText)
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .kerning(1.4)
                .foregroundColor(OPSStyle.Colors.text2)
                .monospacedDigit()

            Spacer()

            SheetCloseButton { dismiss() }
        }
        .padding(.leading, OPSStyle.Layout.spacing3_5)
        .padding(.trailing, 6)
        .padding(.top, OPSStyle.Layout.spacing1)
    }

    private var counterText: String {
        String(format: "%02d / %02d", min(currentIndex + 1, items.count), items.count)
    }

    private var currentItemCanDelete: Bool {
        guard items.indices.contains(currentIndex) else { return false }
        return items[currentIndex].canDeleteFromLead
    }

    private var deleteBar: some View {
        HStack {
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                confirmingDelete = true
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(OPSStyle.Colors.roseTextM)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .regular))
                    }
                    Text("DELETE")
                        .font(.custom("JetBrainsMono-Medium", size: 11))
                        .kerning(1.4)
                }
                .foregroundColor(OPSStyle.Colors.roseTextM)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.roseFillM)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(OPSStyle.Colors.roseLineM, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDeleting)
            .accessibilityLabel("Delete this photo")
            Spacer()
        }
        .padding(.bottom, 34)
    }

    // MARK: - Delete

    private func deleteCurrent() {
        guard items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        guard item.canDeleteFromLead else { return }
        let itemID = item.id
        isDeleting = true

        Task {
            let url: String
            switch item {
            case .remote(let photo):     url = photo.storedURL
            case .queued(let pending):   url = pending.localURL
            case .emailAttachment:
                isDeleting = false
                return
            }

            let ok = await LeadImageService.shared.deleteImage(url, from: opportunity)
            isDeleting = false
            guard ok else {
                ToastCenter.shared.present(Toast(label: Feedback.Err.deleteFailed, tone: .error))
                return
            }
            guard let removedIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            items.remove(at: removedIndex)
            if items.isEmpty {
                dismiss()
            } else if currentIndex > removedIndex {
                currentIndex -= 1
            } else if currentIndex == removedIndex {
                currentIndex = min(removedIndex, items.count - 1)
            }
        }
    }
}

// MARK: - Zoomable page

/// One photo, pinch + double-tap zoomable. Transform-only (scale/offset) so
/// it stays 60fps; honors the standard easing for the double-tap snap.
private struct ZoomablePhotoPage: View {
    let item: LeadPhotoItem

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(zoomGesture.simultaneously(with: scale > 1 ? panGesture : nil))
                .onTapGesture(count: 2) {
                    withAnimation(OPSStyle.Animation.standard) {
                        if scale > 1 {
                            scale = 1; lastScale = 1
                            offset = .zero; lastOffset = .zero
                        } else {
                            scale = 2.5; lastScale = 2.5
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .remote(let photo):
            AsyncImage(url: URL(string: photo.displayURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundColor(OPSStyle.Colors.textMute)
                        Text("// COULD NOT LOAD")
                            .font(OPSStyle.Typography.miniLabel)
                            .kerning(1.4)
                            .foregroundColor(OPSStyle.Colors.textMute)
                    }
                default:
                    ProgressView()
                        .tint(OPSStyle.Colors.text3)
                }
            }
        case .queued(let pending):
            if let image = LeadImageService.shared.queuedImage(for: pending) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        case .emailAttachment(let attachment):
            LeadAttachmentPreview(
                attachment: attachment,
                maxPixelSize: LeadAttachmentContentLoader.viewerMaxPixelSize,
                contentMode: .fit,
                showsFailureMessage: true
            )
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.02 {
                    withAnimation(OPSStyle.Animation.standard) {
                        scale = 1; lastScale = 1
                        offset = .zero; lastOffset = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}
