//
//  ImageDownsampler.swift
//  OPS
//
//  Tile-size image decoding for photo thumbnails. Decoding a full 12 MP
//  original to draw a 72 pt tile costs tens of ms of main-thread time per
//  photo and one image fills the entire 50 MB ImageCache; downsampling at
//  decode time makes tiles cheap to decode, cheap to cache, and cheap to draw.
//

import UIKit
import ImageIO

enum ImageDownsampler {

    /// Decode a downsampled UIImage straight from encoded image data via
    /// ImageIO, without ever materializing the full-resolution bitmap.
    static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Downscale an already-decoded UIImage (disk originals, annotation
    /// composites). Returns the input untouched when it is already within
    /// the cap, so small images pay nothing.
    static func downsample(image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxPixelSize, longest > 0 else { return image }
        let ratio = maxPixelSize / longest
        let targetSize = CGSize(
            width: (pixelWidth * ratio).rounded(),
            height: (pixelHeight * ratio).rounded()
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
