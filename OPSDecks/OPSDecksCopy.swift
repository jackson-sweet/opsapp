import Foundation

enum OPSDecksCopy {
    static let statusEyebrow = String(localized: "// STANDALONE")
    static let shellTitle = String(localized: "OPS DECKS")
    static let shellSubtitle = String(localized: "Draw the deck. Build the quote. Keep the job moving.")
    static let defaultDeckTitle = String(localized: "UNTITLED DECK")
    static let primaryActionPlaceholder = String(localized: "NEW DECK")
    static let libraryEyebrow = String(localized: "// SAVED DECKS")
    static let emptyLibraryTitle = String(localized: "NO DECKS SAVED")
    static let emptyLibraryBody = String(localized: "Start one in the field. It stays here when you close it.")
    static let openDeck = String(localized: "OPEN")
    static let deleteDeck = String(localized: "DELETE")
    static let localStatus = String(localized: "LOCAL")
    static let updatedPrefix = String(localized: "UPDATED")
    static let storageErrorStatus = String(localized: "SYS :: STORAGE")
    static let storageErrorMessage = String(localized: "Deck storage failed. Restart OPS Decks and try again.")
    static let deleteConfirmationTitle = String(localized: "DELETE DECK")
    static let deleteConfirmationMessage = String(localized: "DESTRUCTIVE. NO UNDO.")
    static let cancel = String(localized: "CANCEL")
    static let freeLimitStatus = String(localized: "SYS :: FREE LIMIT")
    static let freeLimitMessage = String(localized: "Free saves one deck. Get Pro to save another.")
    static let proActionPlaceholder = String(localized: "GET PRO")
    static let workspaceEyebrow = String(localized: "// OPS DECKS")
    static let closeWorkspace = String(localized: "CLOSE")

    static func updatedLabel(_ formattedDate: String) -> String {
        "\(updatedPrefix) :: \(formattedDate)"
    }
}

enum OPSDecksUpgradeCopy {
    static let title = String(localized: "Bring this into OPS")
    static let body = String(localized: "Turn the deck into a live job without redrawing it.")
}
