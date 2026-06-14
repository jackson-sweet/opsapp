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
            case .small: return Font.custom("JetBrainsMono-Regular", size: 8)
            case .medium: return Font.custom("JetBrainsMono-Regular", size: 9)
            case .large: return Font.custom("JetBrainsMono-Regular", size: 11)
            case .navBar: return Font.custom("JetBrainsMono-Regular", size: 13)
            }
        }

        // Bug 3685b6e8 — paddings audited across all sizes. Old values had
        // small=3/5 (cramped) and large=5/10 (paddingV didn't grow with the
        // font). New ladder scales paddingV proportionally to the font so
        // every size has a balanced badge body.
        var paddingH: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 10
            case .navBar: return 12
            }
        }

        var paddingV: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 5
            case .large: return 6
            case .navBar: return 7
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

        // Border stroke weight — half-pixel hairlines on small/medium read
        // cleaner against the calendar card background; navBar gets the
        // full pixel so it reads as authoritative chrome.
        var borderWidth: CGFloat {
            switch self {
            case .small, .medium: return 0.5
            case .large: return 0.75
            case .navBar: return 1
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
                    .stroke(color, lineWidth: size.borderWidth)
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
                    .stroke(color, lineWidth: size.borderWidth)
            )
    }
}
