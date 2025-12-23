//
//  OptionalSectionPill.swift
//  OPS
//
//  Pill-styled button for optional form sections
//

import SwiftUI

struct OptionalSectionPill: View {
    let title: String
    let icon: String?
    let action: () -> Void
    let isDisabled: Bool
    let isHighlighted: Bool
    let highlightPulse: Bool

    init(title: String, icon: String? = nil, isDisabled: Bool = false, isHighlighted: Bool = false, highlightPulse: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDisabled = isDisabled
        self.isHighlighted = isHighlighted
        self.highlightPulse = highlightPulse
        self.action = action
    }

    private var borderColor: Color {
        if isHighlighted {
            return OPSStyle.Colors.primaryAccent
        }
        return OPSStyle.Colors.separator
    }

    private var borderOpacity: Double {
        guard isHighlighted else { return 1.0 }
        return highlightPulse ? 1.0 : 0.3
    }

    private var textColor: Color {
        if isDisabled {
            return OPSStyle.Colors.tertiaryText
        }
        if isHighlighted {
            return OPSStyle.Colors.primaryAccent
        }
        return OPSStyle.Colors.secondaryText
    }

    private var textOpacity: Double {
        guard isHighlighted else { return 1.0 }
        return highlightPulse ? 1.0 : 0.3
    }

    var body: some View {
        Button(action: {
            guard !isDisabled else { return }
            action()
        }) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .opacity(textOpacity)
                        .animation(isHighlighted ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isHighlighted)
                }

                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(textColor)
                    .opacity(textOpacity)
                    .animation(isHighlighted ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isHighlighted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(borderColor, lineWidth: isHighlighted ? 2 : 1)
                    .opacity(borderOpacity)
                    .animation(isHighlighted ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isHighlighted)
            )
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .allowsHitTesting(!isDisabled)
    }
}

struct OptionalSectionPillGroup: View {
    let pills: [(title: String, icon: String?, isExpanded: Bool, isDisabled: Bool, isHighlighted: Bool, action: () -> Void)]
    var highlightPulse: Bool = false

    // Convenience initializer for backward compatibility
    init(pills: [(title: String, icon: String?, isExpanded: Bool, action: () -> Void)]) {
        self.pills = pills.map { ($0.title, $0.icon, $0.isExpanded, false, false, $0.action) }
        self.highlightPulse = false
    }

    // Full initializer with all parameters
    init(pills: [(title: String, icon: String?, isExpanded: Bool, isDisabled: Bool, isHighlighted: Bool, action: () -> Void)], highlightPulse: Bool = false) {
        self.pills = pills
        self.highlightPulse = highlightPulse
    }

    var body: some View {
        let collapsedPills = pills.filter { !$0.isExpanded }

        if !collapsedPills.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(Array(collapsedPills.enumerated()), id: \.offset) { _, pill in
                    OptionalSectionPill(
                        title: pill.title,
                        icon: pill.icon,
                        isDisabled: pill.isDisabled,
                        isHighlighted: pill.isHighlighted,
                        highlightPulse: highlightPulse,
                        action: pill.action
                    )
                }
            }
        }
    }
}

// MARK: - Flow Layout for Pills

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    // Move to next line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))

                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
