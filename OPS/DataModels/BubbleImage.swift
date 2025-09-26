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
    
    // Custom init to handle either direct URL string or structured object
    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            // Standard decoding path - it's a proper BubbleImage object
            self.url = try container.decodeIfPresent(String.self, forKey: .url)
            self.width = try container.decodeIfPresent(Int.self, forKey: .width)
            self.height = try container.decodeIfPresent(Int.self, forKey: .height)
        } else {
            // Alternative path - it's just a string URL
            let container = try decoder.singleValueContainer()
            do {
                let urlString = try container.decode(String.self)
                self.url = urlString
                self.width = nil
                self.height = nil
                
            } catch {
                // Try to handle a null value
                if container.decodeNil() {
                    self.url = nil
                    self.width = nil
                    self.height = nil
                } else {
                    // If it's neither a string nor null, log the error but don't fail
                    self.url = nil
                    self.width = nil
                    self.height = nil
                }
            }
        }
    }
    
    // Standard initializer for creating instances in code
    init(url: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.width = width
        self.height = height
    }
}
