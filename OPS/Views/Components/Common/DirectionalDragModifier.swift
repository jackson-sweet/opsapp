//
//  DirectionalDragModifier.swift
//  OPS
//
//  Resolves scroll vs. swipe gesture conflict by committing to a drag axis
//  within the first 10pt of movement. Horizontal intent = swipe captured.
//  Vertical intent = gesture released to ScrollView.
//

import SwiftUI

struct DirectionalDragModifier: ViewModifier {
    let isEnabled: Bool
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat) -> Void)?

    @GestureState private var dragState: DragAxisState = .undecided

    private let threshold: CGFloat = 10

    enum DragAxisState: Equatable {
        case undecided
        case horizontal
        case vertical
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(isEnabled ? horizontalGesture : nil)
    }

    private var horizontalGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .updating($dragState) { value, state, _ in
                let t = value.translation
                switch state {
                case .undecided:
                    guard abs(t.width) > threshold || abs(t.height) > threshold else { return }
                    if abs(t.width) > abs(t.height) {
                        state = .horizontal
                    } else {
                        state = .vertical
                    }
                case .horizontal:
                    onChanged?(t.width)
                case .vertical:
                    break
                }
            }
            .onEnded { value in
                // dragState is still valid here — @GestureState resets after onEnded fires
                if dragState == .horizontal {
                    onEnded?(value.translation.width)
                }
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
