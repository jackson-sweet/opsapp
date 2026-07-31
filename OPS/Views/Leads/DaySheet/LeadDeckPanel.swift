//
//  LeadDeckTile.swift
//  OPS
//
//  The deck design on the expanded day-sheet card — one L2 tile that says what
//  was drawn and opens it. A runner standing at the door needs to recognize the
//  drawing he's about to talk through, not author it: creating and attaching
//  decks stays in FULL LEAD and the site-visit flow (spec §3.4.2).
//
//  Thumbnail reuses the SHIPPED deck preview asset — `DeckDesign.thumbnailURL`,
//  the PNG `DeckRenderer` renders and uploads on every builder save (the same
//  image `TemplatePickerView`'s recents list shows). No bespoke renderer: a
//  design saved offline, or saved before the thumbnail upload landed, falls
//  back to the deck surface's own empty glyph rather than re-drawing geometry
//  inside a scrolling list.
//
//  This view is deliberately dumb — it takes a design and a closure. Resolution
//  (display-candidate + remote self-repair) lives in the card, matching
//  `LeadDeckSection`.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3.4
//

import SwiftUI
import UIKit

struct LeadDeckTile: View {

    let design: DeckDesign
    var onOpen: (DeckDesign) -> Void = { _ in }

    /// `W × L · MATERIAL · RAIL`, resolved once at construction. Reading
    /// `design.drawingData` decodes the whole drawing JSON, so it must never
    /// sit in a computed property the body re-evaluates.
    private let meta: String?

    /// Square preview, sized to the row thumb (`LeadThumbView.side`) so the
    /// card's two images sit on the same grid.
    private static var previewSide: CGFloat { LeadThumbView.side }

    init(design: DeckDesign, onOpen: @escaping (DeckDesign) -> Void = { _ in }) {
        self.design = design
        self.onOpen = onOpen
        self.meta = Self.metaLine(for: design)
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen(design)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                thumbnail
                identity
                Spacer(minLength: 0)
                Image(systemName: OPSStyle.Icons.forward)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.nestedBorder,
                                  lineWidth: OPSStyle.Layout.Border.standard)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(accessibilityLabelText)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        if let url = thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    // Loading and failure both land on the placeholder — a
                    // spinner inside a card that is already open reads as a
                    // stall, not as progress.
                    placeholderTile
                }
            }
            .frame(width: Self.previewSide, height: Self.previewSide)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous))
        } else {
            placeholderTile
        }
    }

    /// The deck surface's own "nothing drawn yet" glyph (`DeckTabView`), so an
    /// un-rendered design reads the same here as it does on the project tab.
    private var placeholderTile: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
            .fill(OPSStyle.Colors.fillNeutralDim)
            .overlay(
                Image(systemName: "square.dashed")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .light))
                    .foregroundColor(OPSStyle.Colors.textMute)
            )
            .frame(width: Self.previewSide, height: Self.previewSide)
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(design.title)
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)
                .truncationMode(.tail)

            if let meta = meta {
                Text(meta)
                    .font(OPSStyle.Typography.nanoLabel)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var thumbnailURL: URL? {
        guard let raw = design.thumbnailURL?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty
        else { return nil }
        return URL(string: raw)
    }

    private var accessibilityLabelText: String {
        let tail = meta.map { ", \($0.lowercased())" } ?? ""
        return "Deck design \(design.title)\(tail)"
    }

    // MARK: - Meta line

    /// `12' × 16' · COMPOSITE · GLASS`. Every segment is omitted when its data
    /// is absent — a deck drawn without railings says nothing about railings
    /// rather than saying `—`.
    private static func metaLine(for design: DeckDesign) -> String? {
        let data = design.drawingData
        var parts: [String] = []
        if let span = dimensionSpan(data) { parts.append(span) }
        if let material = dominantMaterial(data) { parts.append(material) }
        if let railing = dominantRailing(data) { parts.append(railing) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The deck's two longest distinct runs — its span. (Deliberately NOT
    /// `TemplatePickerView.dimensionSummary`'s ascending `prefix(2)`: on an
    /// L-shaped deck the two SMALLEST edges are the jogs, and reporting those
    /// as `W × L` would understate the job.)
    private static func dimensionSpan(_ data: DeckDrawingData) -> String? {
        let dimensions = data.allEdges.compactMap(\.dimension).filter { $0 > 0 }
        guard !dimensions.isEmpty else { return nil }
        let distinct = Array(Set(dimensions)).sorted(by: >).prefix(2)
        let system = data.config.measurementSystem
        return distinct
            .map { DimensionEngine.format($0, system: system) }
            .joined(separator: " × ")
    }

    private static func dominantMaterial(_ data: DeckDrawingData) -> String? {
        let surfaces = data.isMultiLevel ? data.levels.flatMap(\.surfaces) : data.surfaces
        return mostCommon(surfaces.map(\.boardMaterial))?.uppercased()
    }

    private static func dominantRailing(_ data: DeckDrawingData) -> String? {
        let types = data.allEdges.compactMap { $0.railingConfig?.railingType.displayName }
        return mostCommon(types)?.uppercased()
    }

    /// Most-frequent value, ties broken by first appearance so the same drawing
    /// always reports the same material.
    private static func mostCommon(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for value in values where !value.isEmpty {
            counts[value, default: 0] += 1
        }
        guard !counts.isEmpty else { return nil }
        let best = counts.values.max() ?? 0
        return values.first { counts[$0] == best }
    }
}
