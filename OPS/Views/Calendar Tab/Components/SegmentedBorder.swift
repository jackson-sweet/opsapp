//
//  SegmentedBorder.swift
//  OPS
//
//  Segmented border view showing proportional task type colors
//

import SwiftUI

// View modifier for segmented border overlay
struct SegmentedBorderModifier: ViewModifier {
    let calendarEvents: [CalendarEvent]
    let isSelected: Bool
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if isSelected {
                        // White border for selected state
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white, lineWidth: 2)
                    } else if !calendarEvents.isEmpty {
                        // Segmented border for events
                        SegmentedBorderView(events: calendarEvents, cornerRadius: cornerRadius)
                    }
                }
            )
    }
}

// Segmented border view that calculates segments from events
struct SegmentedBorderView: View {
    let events: [CalendarEvent]
    let cornerRadius: CGFloat
    @EnvironmentObject private var dataController: DataController
    
    private var taskColorSegments: [(color: Color, count: Int)] {
        // Task-only scheduling migration: All events are task events
        var colorCounts: [String: Int] = [:]
        var colorMap: [String: Color] = [:]

        for event in events {
            if let task = event.task {
                // Use the task's effective color (from task type)
                let colorKey = "task_\(task.effectiveColor)"
                colorCounts[colorKey, default: 0] += 1

                if let color = Color(hex: task.effectiveColor) {
                    colorMap[colorKey] = color
                } else {
                    // Fallback for invalid task colors
                    colorMap[colorKey] = Color.gray.opacity(0.6)
                }
            }
        }

        // Convert to array of (color, count) tuples
        return colorCounts.compactMap { key, count in
            guard let color = colorMap[key] else { return nil }
            return (color, count)
        }.sorted { $0.count > $1.count } // Sort by count for visual consistency
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if taskColorSegments.isEmpty {
                    // No events - no border
                    EmptyView()
                } else if taskColorSegments.count == 1 {
                    // Single color border - same thickness as multi-segment
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(taskColorSegments[0].color, lineWidth: 2)
                } else {
                    // Multiple colors - create segmented border
                    SegmentedRoundedRectangle(
                        segments: taskColorSegments,
                        cornerRadius: cornerRadius
                    )
                }
            }
        }
    }
}

// Simplified segmented rounded rectangle
struct SegmentedRoundedRectangle: View {
    let segments: [(color: Color, count: Int)]
    let cornerRadius: CGFloat
    let lineWidth: CGFloat = 2
    
    private var totalCount: Int {
        segments.reduce(0) { $0 + $1.count }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            
            // For simplicity, we'll use overlapping strokes with dash patterns
            // This creates a visual effect of segments
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    let startAngle = angleForIndex(index)
                    let proportion = CGFloat(segment.count) / CGFloat(totalCount)
                    let sweepAngle = proportion * 360
                    
                    RoundedRectangleBorder(
                        cornerRadius: cornerRadius,
                        startAngle: startAngle,
                        sweepAngle: sweepAngle,
                        color: segment.color,
                        lineWidth: lineWidth
                    )
                }
            }
        }
    }
    
    private func angleForIndex(_ index: Int) -> Double {
        var angle: Double = -90 // Start from top
        for i in 0..<index {
            let proportion = Double(segments[i].count) / Double(totalCount)
            angle += proportion * 360
        }
        return angle
    }
}

// Custom shape for drawing a portion of a rounded rectangle border
struct RoundedRectangleBorder: View {
    let cornerRadius: CGFloat
    let startAngle: Double
    let sweepAngle: Double
    let color: Color
    let lineWidth: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let path = RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
            
            // Calculate the perimeter
            let perimeter = calculatePerimeter(rect: rect, cornerRadius: cornerRadius)
            
            // Convert angles to perimeter positions
            let startProgress = startAngle / 360.0
            let endProgress = (startAngle + sweepAngle) / 360.0
            
            // Calculate dash pattern based on segment position
            let dashLength = perimeter * CGFloat(endProgress - startProgress)
            let gapLength = perimeter - dashLength
            let dashPhase = -perimeter * CGFloat(startProgress)
            
            // Draw the segment using dash pattern
            path.stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .butt,
                    lineJoin: .miter,
                    dash: [dashLength, gapLength],
                    dashPhase: dashPhase
                )
            )
        }
    }
    
    private func calculatePerimeter(rect: CGRect, cornerRadius: CGFloat) -> CGFloat {
        let width = rect.width
        let height = rect.height
        
        // Calculate straight sides
        let horizontalSides = 2 * (width - 2 * cornerRadius)
        let verticalSides = 2 * (height - 2 * cornerRadius)
        
        // Calculate corner arcs (4 quarter circles)
        let cornerPerimeter = 2 * .pi * cornerRadius
        
        return horizontalSides + verticalSides + cornerPerimeter
    }
}

// Extension to make it easy to use
extension View {
    func segmentedEventBorder(events: [CalendarEvent], isSelected: Bool, cornerRadius: CGFloat = 8) -> some View {
        self.modifier(SegmentedBorderModifier(
            calendarEvents: events,
            isSelected: isSelected,
            cornerRadius: cornerRadius
        ))
    }
}