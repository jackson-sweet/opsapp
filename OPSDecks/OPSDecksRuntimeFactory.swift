import Foundation
import DeckKit

enum OPSDecksRuntimeFactory {
    @MainActor
    static func make(companyId: String, projectName: String? = nil) -> DeckRuntime {
        DeckRuntime(
            context: DeckRuntimeContext(
                companyId: companyId,
                projectId: nil,
                projectName: projectName,
                appSurface: .opsDecks
            ),
            store: nil
        )
    }
}
