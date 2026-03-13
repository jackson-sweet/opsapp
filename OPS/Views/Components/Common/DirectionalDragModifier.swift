//
//  DirectionalDragModifier.swift
//  OPS
//
//  Resolves scroll vs. swipe gesture conflict by committing to a drag axis
//  within the first few points of movement. Horizontal intent = swipe captured.
//  Vertical intent = gesture ignored so ScrollView can scroll normally.
//

import SwiftUI

struct DirectionalDragModifier: ViewModifier {
    let isEnabled: Bool
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat) -> Void)?

    // @State so the axis decision survives into onEnded
    // (@GestureState resets BEFORE onEnded fires — cannot be used for axis tracking)
    @State private var resolvedAxis: DragAxis = .undecided

    /// Minimum movement before we commit to an axis direction
    private let axisThreshold: CGFloat = 12

    enum DragAxis: Equatable {
        case undecided
        case horizontal
        case vertical
    }

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .simultaneousGesture(horizontalGesture)
        } else {
            content
        }
    }

    private var horizontalGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                let t = value.translation
                switch resolvedAxis {
                case .undecided:
                    let absW = abs(t.width)
                    let absH = abs(t.height)
                    // Wait until movement exceeds threshold before deciding
                    guard absW > axisThreshold || absH > axisThreshold else { return }
                    // Require horizontal to be clearly dominant (3× vertical)
                    if absW > absH * 3 {
                        resolvedAxis = .horizontal
                        onChanged?(t.width)
                    } else {
                        resolvedAxis = .vertical
                    }
                case .horizontal:
                    onChanged?(t.width)
                case .vertical:
                    break
                }
            }
            .onEnded { value in
                if resolvedAxis == .horizontal {
                    onEnded?(value.translation.width)
                }
                resolvedAxis = .undecided
            }
    }
}

extension View {
    func directionalDrag(
        isEnabled: Bool = true,
        onChanged: ((CGFloat) -> Void)? = nil,
        onEnded: ((CGFloat) -> Void)? = nil
    ) -> some View {
        modifier(DirectionalDragModifier(
            isEnabled: isEnabled,
            onChanged: onChanged,
            onEnded: onEnded
        ))
    }
}
