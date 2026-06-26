import OPSDesignKit
import SwiftUI

extension OPSStyle.Colors {
    static func pipelineStageColor(for stage: PipelineStage) -> Color {
        switch stage {
        case .newLead:
            return OPSStyle.Colors.pipelineNewLead
        case .qualifying:
            return OPSStyle.Colors.pipelineQualifying
        case .quoting:
            return OPSStyle.Colors.pipelineQuoting
        case .quoted:
            return OPSStyle.Colors.pipelineQuoted
        case .followUp:
            return OPSStyle.Colors.pipelineFollowUp
        case .negotiation:
            return OPSStyle.Colors.pipelineNegotiation
        case .won:
            return OPSStyle.Colors.pipelineWon
        case .lost:
            return OPSStyle.Colors.pipelineLost
        case .discarded:
            return OPSStyle.Colors.pipelineDiscarded
        }
    }

    static func statusColor(for status: Status) -> Color {
        switch status {
        case .rfq:
            return OPSStyle.Colors.statusRFQ
        case .estimated:
            return OPSStyle.Colors.statusEstimated
        case .accepted:
            return OPSStyle.Colors.statusAccepted
        case .inProgress:
            return OPSStyle.Colors.statusInProgress
        case .completed:
            return OPSStyle.Colors.statusCompleted
        case .closed:
            return OPSStyle.Colors.statusClosed
        case .archived:
            return OPSStyle.Colors.statusArchived
        }
    }
}

struct LegacyStatusBadge: View {
    let status: Status

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(OPSStyle.Typography.status)
            .foregroundColor(OPSStyle.Colors.buttonText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(OPSStyle.Colors.statusColor(for: status))
            .cornerRadius(OPSStyle.Layout.chipRadius)
    }
}
