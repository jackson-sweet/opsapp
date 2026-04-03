// OPS/OPS/DeckBuilder/Views/AssignmentWheelView.swift

import SwiftUI

struct AssignmentWheelView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @State private var isExpanded = false
    @State private var dragAngle: Double?
    @State private var highlightedIndex: Int?

    private let wheelRadius: CGFloat = 110
    private let slotCount = 8

    // Built-in edge type items + slot for company products
    private var wheelItems: [WheelSlot] {
        var items: [WheelSlot] = []

        if viewModel.selection.hasEdges {
            items.append(WheelSlot(name: "House Edge", icon: "house", action: .edgeType(.houseEdge)))
            items.append(WheelSlot(name: "Deck Edge", icon: "rectangle", action: .edgeType(.deckEdge)))
            items.append(WheelSlot(name: "Glass Rail", icon: "rectangle.split.3x1", action: .railing(.glass)))
            items.append(WheelSlot(name: "Picket Rail", icon: "line.3.horizontal", action: .railing(.picket)))
            items.append(WheelSlot(name: "Cable Rail", icon: "cable.connector.horizontal", action: .railing(.cable)))
            items.append(WheelSlot(name: "No Railing", icon: "xmark", action: .removeRailing))
            items.append(WheelSlot(name: "Add Stairs", icon: "stairs", action: .addStairs))
            items.append(WheelSlot(name: "Dimension", icon: "ruler", action: .dimension))
        } else if viewModel.selection.selectedFootprint {
            items.append(WheelSlot(name: "Composite", icon: "square.grid.3x3", action: .assignItem(
                AssignedItem(name: "Composite Decking", unitType: .squareFoot)
            )))
            items.append(WheelSlot(name: "Vinyl", icon: "square.grid.3x3.fill", action: .assignItem(
                AssignedItem(name: "Vinyl Surfacing", unitType: .squareFoot)
            )))
            items.append(WheelSlot(name: "Wood", icon: "rectangle.split.3x1.fill", action: .assignItem(
                AssignedItem(name: "Wood Decking", unitType: .squareFoot)
            )))
            items.append(WheelSlot(name: "Plywood", icon: "square.stack.fill", action: .assignItem(
                AssignedItem(name: "Plywood", unitType: .squareFoot)
            )))
        }

        return items
    }

    var body: some View {
        ZStack {
            if isExpanded {
                // Background overlay
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { collapse() }

                // Wheel slots
                ForEach(Array(wheelItems.enumerated()), id: \.offset) { index, slot in
                    let angle = slotAngle(index: index)
                    let isHighlighted = highlightedIndex == index

                    VStack(spacing: 4) {
                        Image(systemName: slot.icon)
                            .font(.system(size: isHighlighted ? 22 : 18, weight: .medium))
                            .foregroundColor(isHighlighted ? OPSStyle.Colors.primaryAccent : .white)

                        Text(slot.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isHighlighted ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                    }
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(isHighlighted
                                  ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                                  : OPSStyle.Colors.cardBackground)
                    )
                    .offset(
                        x: cos(angle) * wheelRadius,
                        y: sin(angle) * wheelRadius
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Center button
            centerButton
        }
        .animation(OPSStyle.Animation.spring, value: isExpanded)
    }

    // MARK: - Center Button

    private var centerButton: some View {
        Circle()
            .fill(OPSStyle.Colors.primaryAccent.opacity(isExpanded ? 0.3 : 1.0))
            .frame(width: 56, height: 56)
            .overlay(
                Group {
                    if let assignment = viewModel.activeAssignment {
                        Text(assignment.name.prefix(3).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: isExpanded ? "xmark" : "circle.grid.2x2")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        switch value {
                        case .second(true, let drag):
                            if !isExpanded {
                                isExpanded = true
                            }
                            if let drag = drag {
                                updateHighlight(drag: drag)
                            }
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        if let index = highlightedIndex, index < wheelItems.count {
                            executeAction(wheelItems[index].action)
                        }
                        collapse()
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if isExpanded {
                            collapse()
                        } else {
                            isExpanded = true
                        }
                    }
            )
    }

    // MARK: - Helpers

    private func slotAngle(index: Int) -> Double {
        let angleStep = (2 * .pi) / Double(max(wheelItems.count, 1))
        return Double(index) * angleStep - .pi / 2 // start at top
    }

    private func updateHighlight(drag: DragGesture.Value) {
        let dx = Double(drag.location.x - 28) // center offset
        let dy = Double(drag.location.y - 28)
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > 30 else {
            highlightedIndex = nil
            return
        }

        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        // Offset to match slot positions (starting at top)
        angle = angle + .pi / 2
        if angle > 2 * .pi { angle -= 2 * .pi }

        let angleStep = (2 * .pi) / Double(max(wheelItems.count, 1))
        highlightedIndex = Int((angle + angleStep / 2) / angleStep) % wheelItems.count
    }

    private func collapse() {
        isExpanded = false
        highlightedIndex = nil
        dragAngle = nil
    }

    private func executeAction(_ action: WheelAction) {
        guard let edgeId = viewModel.selection.selectedEdgeIds.first else {
            // Footprint actions
            if case .assignItem(let item) = action, viewModel.selection.selectedFootprint {
                viewModel.assignItemToFootprint(item)
            }
            return
        }

        switch action {
        case .edgeType(let type):
            for id in viewModel.selection.selectedEdgeIds {
                viewModel.setEdgeType(id, type: type)
            }
        case .railing(let type):
            let config = RailingConfig(railingType: type, maxPostSpacing: type.defaultMaxPostSpacing)
            for id in viewModel.selection.selectedEdgeIds {
                viewModel.setRailing(id, config: config)
            }
        case .removeRailing:
            for id in viewModel.selection.selectedEdgeIds {
                viewModel.setRailing(id, config: nil)
            }
        case .addStairs:
            viewModel.editingEdgeId = edgeId
            viewModel.showingStairConfig = true
        case .dimension:
            viewModel.editingEdgeId = edgeId
            viewModel.showingDimensionInput = true
        case .assignItem(let item):
            viewModel.assignItemToSelectedEdges(item)
        }
    }
}

// MARK: - Types

private struct WheelSlot {
    let name: String
    let icon: String
    let action: WheelAction
}

private enum WheelAction {
    case edgeType(EdgeType)
    case railing(RailingType)
    case removeRailing
    case addStairs
    case dimension
    case assignItem(AssignedItem)
}
