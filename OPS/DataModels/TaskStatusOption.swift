import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskStatusOption {
    var id: String
    var display: String
    var color: String
    var index: Int
    var companyId: String

    var lastSyncedAt: Date?
    var needsSync: Bool = false

    init(
        id: String,
        display: String,
        color: String,
        index: Int,
        companyId: String
    ) {
        self.id = id
        self.display = display
        self.color = color
        self.index = index
        self.companyId = companyId
    }
}

extension TaskStatus {
    func color(from options: [TaskStatusOption]) -> Color {
        guard let option = options.first(where: { $0.display == self.rawValue }) else {
            return OPSStyle.Colors.primaryAccent
        }
        return Color(hex: option.color) ?? OPSStyle.Colors.primaryAccent
    }
}
