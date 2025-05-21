import SwiftUI

// Using the Status enum from DataModels/Status.swift

/// Add convenience color references for status badges
extension OPSStyle.Colors {
    enum Statuses {
        static let success = Color("StatusSuccess")
        static let warning = Color("StatusWarning")
        static let error = Color("StatusError")
    }
}

/// A standardized badge component for displaying status information
struct StatusBadge: View {
    var status: String
    var color: Color
    var size: StatusBadgeSize = .medium
    var outlined: Bool = false
    
    enum StatusBadgeSize {
        case small
        case medium
        case large
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
            case .medium: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .large: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
        
        var font: Font {
            switch self {
            case .small: return OPSStyle.Typography.smallCaption
            case .medium: return OPSStyle.Typography.caption
            case .large: return OPSStyle.Typography.body
            }
        }
    }
    
    var body: some View {
        Text(status.uppercased())
            .font(size.font)
            .foregroundColor(outlined ? color : .white)
            .padding(size.padding)
            .background(
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(outlined ? Color.clear : color)
                    .overlay(
                        RoundedRectangle(cornerRadius: size.cornerRadius)
                            .stroke(color, lineWidth: outlined ? 1 : 0)
                    )
            )
    }
}

// Helper extension to create status badges from Status enum
extension StatusBadge {
    static func forJobStatus(_ status: Status) -> StatusBadge {
        // Use the centralized statusColor method to get the appropriate color
        let color = OPSStyle.Colors.statusColor(for: status)
        return StatusBadge(status: status.rawValue, color: color)
    }
}

struct StatusBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            Text("Standard Status Badges")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.bottom, 8)
            
            HStack(spacing: 8) {
                StatusBadge(status: "Active", color: OPSStyle.Colors.Statuses.success)
                StatusBadge(status: "Pending", color: OPSStyle.Colors.Statuses.warning)
                StatusBadge(status: "Error", color: OPSStyle.Colors.Statuses.error)
            }
            
            Text("Size Variations")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.bottom, 8)
                .padding(.top, 16)
            
            VStack(alignment: .leading, spacing: 8) {
                StatusBadge(status: "Small", color: OPSStyle.Colors.primaryAccent, size: .small)
                StatusBadge(status: "Medium", color: OPSStyle.Colors.primaryAccent)
                StatusBadge(status: "Large", color: OPSStyle.Colors.primaryAccent, size: .large)
            }
            
            Text("Outlined Variations")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.bottom, 8)
                .padding(.top, 16)
            
            HStack(spacing: 8) {
                StatusBadge(status: "Outlined", color: OPSStyle.Colors.Statuses.success, outlined: true)
                StatusBadge(status: "Solid", color: OPSStyle.Colors.Statuses.success)
            }
            
            Text("Job Status Badges")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
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
                StatusBadge.forJobStatus(.pending)
            }
        }
        .padding()
        .background(OPSStyle.Colors.background)
        .previewLayout(.sizeThatFits)
    }
}