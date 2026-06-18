//
//  SparklineView.swift
//  OPS
//
//  Tiny inline trend line for top movers list.
//  No axes, no labels — just the shape of the data.
//

import SwiftUI

struct SparklineView: View {
    let points: [Double] // Normalized 0-1
    let color: Color
    var width: CGFloat = 40
    var height: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            var path = Path()
            let stepX = size.width / CGFloat(points.count - 1)

            for (index, point) in points.enumerated() {
                let x = CGFloat(index) * stepX
                let y = size.height - (CGFloat(point) * size.height)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
        .frame(width: width, height: height)
    }
}

#Preview {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()
        HStack(spacing: OPSStyle.Layout.spacing3_5) {
            SparklineView(points: [0.8, 0.7, 0.5, 0.3, 0.1], color: .red)
            SparklineView(points: [0.2, 0.4, 0.3, 0.6, 0.8], color: .green)
            SparklineView(points: [0.5, 0.5, 0.5, 0.5, 0.5], color: .gray)
        }
    }
}
