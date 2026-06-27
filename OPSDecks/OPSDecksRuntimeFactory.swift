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

    @MainActor
    static func make(
        document: OPSDecksDeckDocument,
        libraryStore: OPSDecksDeckLibraryStore
    ) -> DeckRuntime {
        DeckRuntime(
            context: DeckRuntimeContext(
                companyId: document.companyId,
                projectId: document.projectId,
                projectName: document.title,
                appSurface: .opsDecks
            ),
            store: OPSDecksActiveDeckStore(
                documentId: document.id,
                libraryStore: libraryStore
            )
        )
    }
}
