import SwiftUI
import DeckKit
import OPSDesignKit

@main
struct OPSDecksApp: App {
    var body: some Scene {
        WindowGroup {
            OPSDecksRootView()
                .preferredColorScheme(.dark)
        }
    }
}
