//
//  LeadDeckPanel.swift
//  OPS
//
//  The deck design on the expanded day-sheet card — a viewer, not a list row.
//  A runner standing at the door opens the card, RECOGNISES the drawing, and
//  taps it to fill the screen and talk the homeowner through it. The tap goes
//  to the same fullscreen viewer the project deck tab expands into, so a deck
//  reads and behaves identically wherever it was drawn.
//
//  The preview is the SHIPPED deck render — `DeckDesign.thumbnailURL`, the PNG
//  `DeckRenderer` writes and uploads on every builder save that has geometry
//  (the same image `TemplatePickerView`'s recents list shows). Deliberately a
//  STATIC image: the day sheet is a scrolling list of cards, and a live
//  SceneKit or blueprint canvas inline would pay a full render per card.
//  Interaction lives in fullscreen, one tap away.
//
//  Aspect is 1:1 because the asset is: `DeckRenderer.renderToPNG` defaults to
//  1024×1024 and fits the geometry inside it, and the project deck tab frames
//  its own viewport the same way. Any other ratio either crops the drawing or
//  letterboxes it inside dead space.
//
//  A design saved offline, saved before thumbnail upload landed, or whose URL
//  will not load falls back to the deck surface's own `square.dashed` glyph at
//  full panel size — never a blank plate, never a spinner in an open card.
//
//  This view is deliberately dumb — it takes a design and a closure. Resolution
//  (display-candidate + remote self-repair) lives in the card, matching
//  `LeadDeckSection`.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3.4
//

import SwiftUI
import UIKit

struct LeadDeckPanel: View {

    let design: DeckDesign
    let displayTitle: String
    var onOpen: (DeckDesign) -> Void = { _ in }

    /// `W × L · MATERIAL · RAIL`, resolved once at construction. Reading
    /// `design.drawingData` decodes the whole drawing JSON, so it must never
    /// sit in a computed property the body re-evaluates.
    private let meta: String?

    /// Test seam: an already-decoded preview, so a snapshot harness can prove
    /// the LOADED panel without a network round trip. Always nil in production
    /// — the app resolves its preview from `thumbnailURL` like every other deck
    /// surface. Same spirit as `DaySheetLeadCard.DeckSource`, and left out of
    /// `#if DEBUG` for the same reason that enum is: the card's production
    /// switch has to construct this initializer in every configuration.
    private let injectedPreview: UIImage?

    init(
        design: DeckDesign,
        displayTitle: String? = nil,
        injectedPreview: UIImage? = nil,
        onOpen: @escaping (DeckDesign) -> Void = { _ in }
    ) {
        self.design = design
        self.displayTitle = DeckDesignTitlePolicy.resolve(
            preferred: displayTitle,
            fallback: design.title
        )
        self.onOpen = onOpen
        self.meta = Self.metaLine(for: design)
        self.injectedPreview = injectedPreview
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen(design)
        } label: {
            VStack(spacing: 0) {
                preview
                caption
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.nestedBorder,
                                  lineWidth: OPSStyle.Layout.Border.standard)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Opens the drawing full screen")
    }

    // MARK: - Preview

    /// The drawing itself, square and full width. Loading and failure both land
    /// on the placeholder: a spinner inside a card the operator has already
    /// opened reads as a stall, not as progress.
    @ViewBuilder
    private var preview: some View {
        Group {
            if let injectedPreview = injectedPreview {
                Image(uiImage: injectedPreview).resizable().scaledToFill()
            } else if let url = thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    /// The deck surface's own "nothing drawn yet" glyph (`DeckTabView`), so an
    /// un-rendered design reads the same here as it does on the project tab.
    private var placeholder: some View {
        Rectangle()
            .fill(OPSStyle.Colors.fillNeutralDim)
            .overlay(
                Image(systemName: "square.dashed")
                    .font(.system(size: OPSStyle.Layout.IconSize.xxl, weight: .light))
                    .foregroundColor(OPSStyle.Colors.textMute)
            )
    }

    // MARK: - Caption

    /// Identity plate under the drawing, not floating on it: the render is a
    /// plan on white paper, and a dark glass pill laid over it would fight the
    /// thing it is labelling. The expand glyph is the panel's only mark of a
    /// verb — tap-to-fullscreen is otherwise invisible.
    private var caption: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(displayTitle)
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

            Spacer(minLength: 0)

            Image(systemName: OPSStyle.Icons.expand)
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .regular))
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private var thumbnailURL: URL? {
        guard let raw = design.thumbnailURL?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty
        else { return nil }
        return URL(string: raw)
    }

    private var accessibilityLabelText: String {
        let tail = meta.map { ", \($0.lowercased())" } ?? ""
        return "Deck design \(displayTitle)\(tail)"
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
        return mostCommon(surfaces.compactMap(\.boardMaterial))?.uppercased()
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
