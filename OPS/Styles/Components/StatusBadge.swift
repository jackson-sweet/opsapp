import SwiftUI

// Using the Status enum from DataModels/Status.swift

/// Convenience asset-backed color references for status badges.
/// Prefer the new semantic tokens on `OPSStyle.Colors` (`olive`, `tan`, `rose`, `brick`)
/// for new code. These aliases remain for call-site backwards compatibility.
extension OPSStyle.Colors {
    enum Statuses {
        static let success = Color("StatusSuccess") // #9DB582 olive
        static let warning = Color("StatusWarning") // #C4A868 tan
        static let error   = Color("StatusError")   // #93321A brick
    }
}

/// Status badge — spec v2 pattern: colored text + 15% color fill + 30% color border.
///
///   Font:    JetBrains Mono 11pt, tracking-wide, UPPERCASE
///   Padding: 2pt vertical, 6pt horizontal
///   Radius:  `chipRadius` (4pt)
///   Color:   text = color, bg = color.opacity(0.15), border = color.opacity(0.30)
///
/// The `outlined` flag is deprecated — the spec's single badge pattern already reads as
/// outlined. The parameter is preserved for call-site compatibility but has no visual effect.
struct StatusBadge: View {
    var status: String
    var color: Color
    var size: StatusBadgeSize = .medium

    /// Deprecated — spec v2 has a single badge pattern. Flag is ignored.
    var outlined: Bool = false

    enum StatusBadgeSize {
        case small
        case medium
        case large

        var padding: EdgeInsets {
            switch self {
            case .small:  return EdgeInsets(top: 1, leading: 5,  bottom: 1, trailing: 5)
            case .medium: return EdgeInsets(top: 2, leading: 6,  bottom: 2, trailing: 6)
            case .large:  return EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
            }
        }

        /// All chip sizes use the same radius per spec — shape tells you "chip",
        /// size tells you "density of layout".
        var cornerRadius: CGFloat { OPSStyle.Layout.chipRadius }

        /// 11pt JetBrains Mono at every size — 11pt is the spec floor and the badge role.
        var font: Font { OPSStyle.Typography.badgeCake }
    }

    var body: some View {
        Text(status.uppercased())
            .font(size.font)
            .tracking(0.12 * 11)   // 0.12em at 11pt ≈ 1.3pt
            .foregroundColor(color)
            .padding(size.padding)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(color.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .stroke(color.opacity(0.30), lineWidth: 1)
            )
    }
}

// MARK: - Status enum helpers

extension StatusBadge {
    static func forJobStatus(_ status: Status, size: StatusBadgeSize = .medium) -> StatusBadge {
        let color = OPSStyle.Colors.statusColor(for: status)
        return StatusBadge(status: status.rawValue, color: color, size: size)
    }

    /// TaskStatus palette per spec v2: steel (Active) → sage (Completed) → dim rose (Cancelled).
    static func forTaskStatus(_ status: TaskStatus, size: StatusBadgeSize = .small) -> StatusBadge {
        let color: Color
        switch status {
        case .active:     color = Color(hex: "#6E9CB8")! // warm steel — crew on site
        case .completed:  color = Color(hex: "#95B07A")! // sage — signed off by lead
        case .cancelled:  color = Color(hex: "#8E6E73")! // dim rose — removed from scope
        }
        return StatusBadge(status: status.rawValue, color: color, size: size)
    }
}

// MARK: - Previews

struct StatusBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            Text("STATUS BADGES")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                StatusBadge(status: "Active",  color: OPSStyle.Colors.olive)
                StatusBadge(status: "Pending", color: OPSStyle.Colors.tan)
                StatusBadge(status: "Error",   color: OPSStyle.Colors.rose)
            }

            Text("SIZE VARIATIONS")
                .font(OPSStyle.Typography.section)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.bottom, 8)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                StatusBadge(status: "Small",  color: OPSStyle.Colors.olive, size: .small)
                StatusBadge(status: "Medium", color: OPSStyle.Colors.olive)
                StatusBadge(status: "Large",  color: OPSStyle.Colors.olive, size: .large)
            }

            Text("JOB STATUS")
                .font(OPSStyle.Typography.section)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.bottom, 8)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                StatusBadge.forJobStatus(.rfq)
                StatusBadge.forJobStatus(.estimated)
                StatusBadge.forJobStatus(.accepted)
                StatusBadge.forJobStatus(.inProgress)
                StatusBadge.forJobStatus(.completed)
                StatusBadge.forJobStatus(.closed)
                StatusBadge.forJobStatus(.archived)
            }
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .previewLayout(.sizeThatFits)
    }
}
