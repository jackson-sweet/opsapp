// OPS/OPS/DeckBuilder/Models/PhotoOverlayState.swift

import Foundation

public struct PhotoOverlayState: Codable, Equatable {
    public var photoURL: String           // S3 URL or local path of the base site photo
    public var offsetX: Double = 0        // overlay center X offset from photo center (points)
    public var offsetY: Double = 0        // overlay center Y offset from photo center (points)
    public var scale: Double = 1.0        // overlay scale factor
    public var rotation: Double = 0       // degrees
    public var opacity: Double = 0.3      // fill opacity (0.1 to 0.8)
}
