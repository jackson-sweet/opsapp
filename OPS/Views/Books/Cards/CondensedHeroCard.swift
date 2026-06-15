//
//  CondensedHeroCard.swift
//  OPS
//
//  Books P6 — UX overhaul. The uniform CONDENSED face every hero-carousel
//  lens renders inside the paging strip: an L2 tile (white@0.04 fill, white@0.08
//  hairline, 6pt radius) at ONE fixed height, showing the lens's headline metric
//  + a single signature mini-viz + one sub-stat. Tapping anywhere expands the
//  lens's full content into a half-sheet (see `ExpandedCardSheet`).
//
//  Spec: docs/superpowers/specs/2026-06-01-books-condensed-cards-ux-overhaul-design.md
//

import SwiftUI

/// Which face a hero-carousel card renders.
/// `.condensed` = the compact glance tile in the paging strip.
/// `.full`      = the rich detail, shown inside the expand-to-sheet.
enum BooksCardStyle {
    case condensed
    case full
}

/// Shared geometry for the condensed strip so every lens — and its skeleton —
/// is exactly the same height (kills the pre-overhaul carousel jump).
enum BooksCondensedMetrics {
    /// One fixed height for all five condensed cards. Tuned so the tallest
    /// composition (the sparkline lens) fits with no dead space.
    static let cardHeight: CGFloat = 150
    /// Height of the mini-viz band shared by meter / sparkline / ramp / bars.
    static let vizHeight: CGFloat = 22
}

/// The uniform condensed tile. Generic over the viz + sub-stat content each
/// lens supplies; the shell owns the L2 chrome, fixed height, expand affordance,
/// press feedback, and the earned `.selection` haptic.
struct CondensedHeroCard<Viz: View, SubStat: View>: View {
    let caption: String
    let heroText: String
    var heroColor: Color = OPSStyle.Colors.text
    /// Optional colored scope hint shown beside the caption (A/R · Forecast).
    var scopeBadge: BooksScopeHintBadge? = nil
    let onExpand: () -> Void
    @ViewBuilder var viz: () -> Viz
    @ViewBuilder var subStat: () -> SubStat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onExpand()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                    Text(caption)
                        .font(.custom("JetBrainsMono-Medium", size: 10))
                        .tracking(1.6)  // 0.16em at 10pt
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    if let scopeBadge { scopeBadge }
                    Spacer(minLength: OPSStyle.Layout.spacing1)
                    // "Expand" affordance — drills now live inside the sheet, so
                    // there is no competing arrow.right on the condensed face.
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .accessibilityHidden(true)
                }

                Text(heroText)
                    .font(OPSStyle.Typography.heroNumberCondensed)
                    .tracking(-0.95)  // ~-0.025em at 38pt
                    .foregroundColor(heroColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .booksNumericContentTransition(reduceMotion: reduceMotion)

                Spacer(minLength: OPSStyle.Layout.spacing2)

                viz()
                    .frame(height: BooksCondensedMetrics.vizHeight)

                subStat()
                    .padding(.top, OPSStyle.Layout.spacing2)
            }
        }
        .buttonStyle(CondensedCardButtonStyle(reduceMotion: reduceMotion))
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to expand")
    }

    /// Fixed-height skeleton placeholder so the cold-paint state holds the same
    /// strip height as a loaded card.
    static func skeleton() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                BooksSkeleton.bar(width: 84, height: 9)
                Spacer()
                BooksSkeleton.bar(width: 11, height: 11)
            }
            BooksSkeleton.bar(width: 150, height: 34).padding(.top, OPSStyle.Layout.spacing2)
            Spacer(minLength: OPSStyle.Layout.spacing2)
            BooksSkeleton.bar(width: nil, height: BooksCondensedMetrics.vizHeight)
            BooksSkeleton.bar(width: 120, height: 10).padding(.top, OPSStyle.Layout.spacing2)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .frame(height: BooksCondensedMetrics.cardHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                .strokeBorder(OPSStyle.Colors.surfaceActive, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .accessibilityHidden(true)
    }
}

/// L2 condensed-tile chrome + press feedback. Fixed height enforces strip
/// uniformity. Mirrors `BooksDrillTile`'s pressed tints on the canonical hover curve.
private struct CondensedCardButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: BooksCondensedMetrics.cardHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                    .fill(pressed ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius)
                    .strokeBorder(pressed ? Color.white.opacity(0.18) : OPSStyle.Colors.surfaceActive,
                                  lineWidth: OPSStyle.Layout.Border.standard)
            )
            .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: pressed)
    }
}

// MARK: - Shared mini-viz primitives (condensed band)

/// Thin horizontal meter — fraction fill over a soft track. Used by the P&L
/// margin glance. Centered in the shared viz band.
struct CondensedMeter: View {
    let fraction: Double          // 0…1, clamped by caller
    var fill: Color = OPSStyle.Colors.olive
    var track: Color = OPSStyle.Colors.warningStatus.opacity(0.30)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(track)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                    .fill(fill)
                    .frame(width: geo.size.width * max(0, min(1, fraction)), height: 6)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

/// Stacked proportional segment bar (aging ramp / pipeline stage mix / win-loss).
/// Each segment width is its share of the total; zero-value segments collapse.
struct CondensedSegmentBar: View {
    struct Segment: Identifiable {
        let id: Int
        let value: Double
        let color: Color
    }
    let segments: [Segment]
    var barHeight: CGFloat = 10

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 1)
        let visible = segments.filter { $0.value > 0 }
        return GeometryReader { geo in
            let gap: CGFloat = 2
            let gapCount = max(visible.count - 1, 0)
            let avail = max(geo.size.width - CGFloat(gapCount) * gap, 0)
            HStack(spacing: gap) {
                ForEach(visible) { seg in
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                        .fill(seg.color)
                        .frame(width: avail * CGFloat(seg.value / total), height: barHeight)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("CondensedHeroCard — P&L glance") {
    VStack(spacing: OPSStyle.Layout.spacing3) {
        CondensedHeroCard(
            caption: "NET CASH",
            heroText: "$42,180",
            onExpand: {},
            viz: { CondensedMeter(fraction: 0.36) },
            subStat: {
                Text("+36% MARGIN")
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(0.44)
                    .foregroundColor(OPSStyle.Colors.olive)
                    .monospacedDigit()
            }
        )
        CondensedHeroCard(
            caption: "TOTAL OUTSTANDING",
            heroText: "$22,800",
            heroColor: OPSStyle.Colors.rose,
            scopeBadge: BooksScopeHintBadge(variant: .allOpen),
            onExpand: {},
            viz: {
                CondensedSegmentBar(segments: [
                    .init(id: 0, value: 8, color: OPSStyle.Colors.olive),
                    .init(id: 1, value: 3, color: OPSStyle.Colors.accountingReceivables),
                    .init(id: 2, value: 2, color: OPSStyle.Colors.warningStatus),
                    .init(id: 3, value: 5, color: OPSStyle.Colors.accountingOverdue),
                ])
            },
            subStat: {
                Text("5 OPEN · 4 OVERDUE")
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(1.32)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .monospacedDigit()
            }
        )
        CondensedHeroCard<EmptyView, EmptyView>.skeleton()
    }
    .padding(.vertical, OPSStyle.Layout.spacing4)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
