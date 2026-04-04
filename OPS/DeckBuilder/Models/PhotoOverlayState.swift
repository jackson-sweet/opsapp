// OPS/OPS/DeckBuilder/Models/PhotoOverlayState.swift

import Foundation

struct PhotoOverlayState: Codable, Equatable {
    var photoURL: String           // S3 URL or local path of the base site photo
    var offsetX: Double = 0        // overlay center X offset from photo center (points)
    var offsetY: Double = 0        // overlay center Y offset from photo center (points)
    var scale: Double = 1.0        // overlay scale factor
    var rotation: Double = 0       // degrees
    var opacity: Double = 0.3      // fill opacity (0.1 to 0.8)
}
