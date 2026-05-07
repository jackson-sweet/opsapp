//
//  StockGridView.swift
//  OPS
//
//  GRID view mode for the STOCK segment. `LazyVGrid` of `VariantCard`
//  with pinch-to-zoom controlled by `@AppStorage("catalog.stock.cardScale")`.
//  Column count derives from the current scale so cards keep a
//  comfortable size at every zoom level.
//

import SwiftUI

struct StockGridView: View {
    let rows: [EnrichedVariantRow]
    var onTap: ((EnrichedVariantRow) -> Void)? = nil

    @AppStorage("catalog.stock.cardScale") private var cardScale: Double = 1.0
    @State private var gestureStartScale: CGFloat = 1.0

    private let minScale: CGFloat = 0.7
    private let maxScale: CGFloat = 1.5

    /// Column count adapts to scale: at scale 1.0, 2 columns; at <0.85,
    /// 3 columns; at >1.25, 1 column. Keeps cards inside a tappable range.
    private var columns: [GridItem] {
        let count: Int
        if cardScale < 0.85 { count = 3 }
        else if cardScale > 1.25 { count = 1 }
        else { count = 2 }
        return Array(
            repeating: GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
            count: count
        )
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: OPSStyle.Layout.spacing2) {
                ForEach(rows) { row in
                    Button {
                        onTap?(row)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VariantCard(row: row, scale: CGFloat(cardScale))
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 100) // FAB clearance
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let newScale = gestureStartScale * value
                    cardScale = Double(min(max(newScale, minScale), maxScale))
                }
                .onEnded { _ in
                    gestureStartScale = CGFloat(cardScale)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        )
        .onAppear {
            gestureStartScale = CGFloat(cardScale)
        }
    }
}
