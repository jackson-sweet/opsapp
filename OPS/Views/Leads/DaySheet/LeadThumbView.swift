//
//  LeadThumbView.swift
//  OPS
//
//  The day-sheet row's leading 56pt tile. Three sources, in the order an
//  operator recognizes a job fastest: the site photo they took, else where the
//  job is, else the initial. Never blank, never a spinner farm — the row is a
//  scan surface and the tile has to resolve instantly whatever the data holds.
//
//  Address-only leads (no coordinates) deliberately do NOT geocode: a scroll
//  surface that fires a geocode per row is a rate-limit and a battery bill.
//  Same coordinates-only rule LeadMapHeader ships.
//
//  The photo tile reads the app's OWN photo cache before it reaches for the
//  network. `AsyncImage` has no knowledge of `ImageFileManager` — offline, an
//  URLSession-backed tile resolves to nothing and every photographed lead falls
//  back to its initial. The day sheet is an offline surface (spec §6): the shot
//  the runner took this morning has to be on the row this afternoon in a
//  basement with no bars. Memory → disk → network, the chain PhotoGalleryViewer
//  already speaks.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3.3
//

import SwiftUI
import CoreLocation
import UIKit

struct LeadThumbView: View {

    let lead: Opportunity

    /// Resolved from the local caches. Nil until the lookup runs (or when the
    /// photo has never been on this device), which is when `AsyncImage` owns
    /// the tile.
    @State private var cachedPhoto: UIImage?

    /// Spec §3.3 — 56pt square tile (component dimension, à la
    /// `LeadMapHeader.mapHeight`).
    static let side: CGFloat = 56

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            source
            // Two or more shots is the only case worth counting — a single
            // photo is already the whole tile.
            if photoCount >= 2 {
                photoCountBadge
            }
        }
        .frame(width: Self.side, height: Self.side)
        // Decorative: the row's label already names the lead.
        .accessibilityHidden(true)
    }

    // MARK: - Source chain

    @ViewBuilder
    private var source: some View {
        if let newest = newestPhoto {
            photoTile(newest)
        } else if let coordinate {
            ProjectLocationSnapshotView(
                coordinate: coordinate,
                projectName: lead.displayContactName,
                // Leads are pre-project by definition — the RFQ pin is the
                // honest state for a job that doesn't exist yet (LeadMapHeader).
                status: .rfq,
                taskColorHexes: [],
                // Tighter than the detail hero's 13: at 56pt the frame has to
                // read as "this block", not "this side of town".
                zoomLevel: 15.0
            )
            .frame(width: Self.side, height: Self.side)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous))
            .allowsHitTesting(false)
        } else {
            initialTile
        }
    }

    /// Cache first, network second. `ZStack` (never a bare `Group`) anchors the
    /// lookup — a childless Group's `.task` never fires.
    private func photoTile(_ photo: (url: URL, key: String)) -> some View {
        ZStack {
            if let cachedPhoto {
                Image(uiImage: cachedPhoto)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: photo.url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        // Loading AND failure both land on the initial tile —
                        // the row must never flash empty or hold a spinner
                        // mid-scroll.
                        initialTile
                    }
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous))
        .task(id: photo.key) { await resolveCachedPhoto(photo.key) }
    }

    /// Memory → disk → give up (and let `AsyncImage` try the wire).
    ///
    /// The disk read is detached so a scroll never waits on file IO; only
    /// `Data` crosses back, so no image object is passed between actors. The
    /// decoded result is promoted into the memory cache, which is what makes
    /// the second appearance of a row instant.
    @MainActor
    private func resolveCachedPhoto(_ key: String) async {
        if let memory = ImageCache.shared.get(forKey: key) {
            cachedPhoto = memory
            return
        }
        guard PhotoDownloadManager.shared.isOnDevice(key) else { return }
        let data = await Task.detached(priority: .userInitiated) {
            ImageFileManager.shared.getImageData(localID: key)
        }.value
        guard let data, let image = UIImage(data: data) else { return }
        ImageCache.shared.set(image, forKey: key)
        cachedPhoto = image
    }

    private var initialTile: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
            .fill(OPSStyle.Colors.surfaceInput)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .overlay(
                Text(initial)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.text3)
            )
            .frame(width: Self.side, height: Self.side)
    }

    // MARK: - Photo count badge

    private var photoCountBadge: some View {
        Text("\(photoCount)")
            .font(OPSStyle.Typography.nanoLabel)
            .monospacedDigit()
            .foregroundColor(OPSStyle.Colors.text)
            .padding(.horizontal, OPSStyle.Layout.spacing1)
            .frame(minWidth: OPSStyle.Layout.IconSize.sm, minHeight: OPSStyle.Layout.IconSize.sm)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(OPSStyle.Colors.imageOverlay)
            )
            .padding(OPSStyle.Layout.spacing1)
    }

    // MARK: - Derived

    /// `images` holds full public S3 URLs written by the web extract pipeline;
    /// blank entries have shown up in the wild, so filter before indexing
    /// (same guard LeadPhotosSection applies to the strip).
    private var photoURLs: [String] {
        lead.images.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var photoCount: Int { photoURLs.count }

    /// The NEWEST shot, not the oldest: the web extract pipeline appends to
    /// `images`, so the server's order is oldest-first (LeadPhotosSection
    /// reverses it for the same reason). The tile has to show what the operator
    /// photographed last, not what the lead looked like the day it landed.
    ///
    /// `key` is the protocol-normalized string the whole photo stack caches
    /// under (`//host/x.jpg` → `https://host/x.jpg`), so a tile and a prefetch
    /// of the same shot can never miss each other over a scheme.
    private var newestPhoto: (url: URL, key: String)? {
        guard let newest = photoURLs.last else { return nil }
        let key = newest.hasPrefix("//") ? "https:" + newest : newest
        guard let url = URL(string: key) else { return nil }
        return (url, key)
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = lead.latitude, let longitude = lead.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var initial: String {
        String(lead.displayContactName.prefix(1)).uppercased()
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadThumbView / sources") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // Initial tile — no photo, no coordinates.
            LeadThumbView(lead: Opportunity.preview(contactName: "Marcus Webb", stage: .quoting))

            // Map tile — coordinates only.
            LeadThumbView(lead: {
                let lead = Opportunity.preview(contactName: "Dana Ruiz", stage: .quoted)
                lead.latitude = 49.2827
                lead.longitude = -123.1207
                return lead
            }())

            // Photo tile + count badge.
            LeadThumbView(lead: {
                let lead = Opportunity.preview(contactName: "Jamie Park", stage: .newLead)
                lead.images = ["https://example.com/a.jpg", "https://example.com/b.jpg"]
                return lead
            }())
        }
    }
    .leadsPreviewEnvironment()
}
#endif
