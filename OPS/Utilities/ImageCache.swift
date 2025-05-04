import UIKit

/// Simple in-memory cache for images
class ImageCache {
    static let shared = ImageCache()
    
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        // Setup cache constraints
        cache.countLimit = 100 // Maximum number of images in memory
        cache.totalCostLimit = 1024 * 1024 * 50 // 50 MB limit
    }
    
    func set(_ image: UIImage, forKey key: String) {
        let cacheKey = NSString(string: key)
        // Calculate estimated memory cost based on image size
        let bytesPerPixel = 4
        let cost = Int(image.size.width * image.size.height) * bytesPerPixel
        cache.setObject(image, forKey: cacheKey, cost: cost)
    }
    
    func get(forKey key: String) -> UIImage? {
        return cache.object(forKey: NSString(string: key))
    }
    
    func remove(forKey key: String) {
        cache.removeObject(forKey: NSString(string: key))
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}