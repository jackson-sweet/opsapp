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

    enum DragAxisState {
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
                guard state != .vertical else { return }
                let t = value.translation
                if state == .undecided {
                    guard abs(t.width) > threshold || abs(t.height) > threshold else { return }
                    state = abs(t.width) > abs(t.height) ? .horizontal : .vertical
                }
                if state == .horizontal {
                    onChanged?(t.width)
                }
            }
            .onEnded { value in
                // Only fire onEnded if gesture was horizontal
                // We infer this from the final translation ratio
                let t = value.translation
                if abs(t.width) > abs(t.height) {
                    onEnded?(t.width)
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
