import Foundation

enum OPSDecksCopy {
    static let statusEyebrow = String(localized: "// STANDALONE")
    static let shellTitle = String(localized: "OPS DECKS")
    static let shellSubtitle = String(localized: "Draw the deck. Build the quote. Keep the job moving.")
    static let defaultDeckTitle = String(localized: "UNTITLED DECK")
    static let defaultCompanyName = String(localized: "My Decks")
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
    static let codeProfileEyebrow = String(localized: "// CODE PROFILE")
    static let codeProfileNotConfigured = String(localized: "NOT SET")
    static let codeProfileAvailable = String(localized: "ACTIVE")
    static let codeProfileUnavailable = String(localized: "NO PROFILE")
    static let codeProfileFailed = String(localized: "FAILED")
    static let codeProfileNotConfiguredMessage = String(localized: "Pick the site jurisdiction before live code checks run.")
    static let codeProfileAvailableMessage = String(localized: "Live checks use this jurisdiction profile.")
    static let codeProfileUnavailableMessage = String(localized: "No verified profile is loaded for this jurisdiction.")
    static let codeProfileFailedMessage = String(localized: "Profile lookup failed. Check settings and try again.")
    static let codeProfileEmptyMessage = String(localized: "No code profiles loaded. Live checks stay off until OPS Decks receives a verified jurisdiction profile.")
    static let codeProfileSourceFallback = String(localized: "PROFILE")
    static let codeProfileUse = String(localized: "USE")
    static let codeProfileClear = String(localized: "CLEAR")

    static func updatedLabel(_ formattedDate: String) -> String {
        "\(updatedPrefix) :: \(formattedDate)"
    }
}

enum OPSDecksUpgradeCopy {
    static let title = String(localized: "Bring this into OPS")
    static let body = String(localized: "Turn the deck into a live job without redrawing it.")
}
