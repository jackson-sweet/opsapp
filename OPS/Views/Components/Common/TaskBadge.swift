//
//  TaskBadge.swift
//  OPS
//
//  Reusable task type badge: color text, color border, low opacity color fill.
//  All caps label. No dot. Three sizes: small, medium, large.
//

import SwiftUI

struct TaskBadge: View {
    let name: String
    let color: Color
    var size: BadgeSize = .medium
    var faded: Bool = false

    enum BadgeSize {
        case small
        case medium
        case large
        case navBar   // Matches DONE button height

        var font: Font {
            switch self {
            case .small: return Font.custom("Kosugi-Regular", size: 8)
            case .medium: return Font.custom("Kosugi-Regular", size: 9)
            case .large: return Font.custom("Kosugi-Regular", size: 11)
            case .navBar: return Font.custom("Kosugi-Regular", size: 13)
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .small: return 5
            case .medium: return 8
            case .large: return 10
            case .navBar: return 12
            }
        }

        var paddingV: CGFloat {
            switch self {
            case .small: return 3
            case .medium: return 5
            case .large: return 5
            case .navBar: return 6
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .small: return 3
            case .medium: return 4
            case .large: return 4
            case .navBar: return OPSStyle.Layout.buttonRadius
            }
        }

        var tracking: CGFloat {
            switch self {
            case .small: return 0.2
            case .medium: return 0.3
            case .large: return 0.5
            case .navBar: return 0.5
            }
        }
    }

    var body: some View {
        Text(name.uppercased())
            .font(size.font)
            .tracking(size.tracking)
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, size.paddingH)
            .padding(.vertical, size.paddingV)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(color, lineWidth: 1)
            )
            .opacity(faded ? 0.4 : 1.0)
    }
}

/// Status badge (ACTIVE, SELECTED, COMPLETE) — same style but distinct from task type
struct StatusBadgePill: View {
    let text: String
    let color: Color
    var size: TaskBadge.BadgeSize = .medium

    var body: some View {
        Text(text)
            .font(size.font)
            .tracking(size.tracking)
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, size.paddingH)
            .padding(.vertical, size.paddingV)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(color, lineWidth: 1)
            )
    }
}
