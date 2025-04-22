//
//  BubbleImage.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation

/// Bubble's image structure
struct BubbleImage: Codable {
    let url: String?
    let width: Int?
    let height: Int?
    
    enum CodingKeys: String, CodingKey {
        case url
        case width = "image_width"
        case height = "image_height"
    }
}
