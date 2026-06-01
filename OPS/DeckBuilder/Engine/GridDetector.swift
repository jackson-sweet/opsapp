// OPS/OPS/DeckBuilder/Engine/GridDetector.swift

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Accelerate
import UIKit

struct GridDetector {

    // MARK: - Axis

    private enum Axis {
        case horizontal
        case vertical
    }

    // MARK: - Public Entry Point

    /// Detect graph paper grid in the image and produce a cleaned binary image with grid lines removed.
    /// - Parameter image: The source photograph (perspective-corrected)
    /// - Returns: A `GridDetectionResult` with the cleaned image and grid metadata
    static func detect(image: CGImage) -> GridDetectionResult {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let imageSize = CGSize(width: image.width, height: image.height)

        // Step 1: Grayscale conversion
        let ciImage = CIImage(cgImage: image)
        guard let grayscale = applyGrayscale(ciImage) else {
            return GridDetectionResult(
                hasGrid: false,
                gridSpacingPixels: nil,
                cleanedImage: image,
                originalImage: image,
                imageSize: imageSize
            )
        }

        // Step 2: Adaptive threshold — convert to binary
        guard let binary = applyThreshold(grayscale),
              let binaryCG = context.createCGImage(binary, from: binary.extent) else {
            return GridDetectionResult(
                hasGrid: false,
                gridSpacingPixels: nil,
                cleanedImage: image,
                originalImage: image,
                imageSize: imageSize
            )
        }

        // Step 3: Extract horizontal and vertical grid lines via morphological operations
        let (horizontalLines, verticalLines) = extractGridLines(binary, imageSize: imageSize, context: context)

        // Step 4: Measure line spacing for each axis to determine if a regular grid exists
        let horizontalSpacing = horizontalLines.flatMap { measureLineSpacing($0, axis: .horizontal, imageSize: imageSize) }
        let verticalSpacing = verticalLines.flatMap { measureLineSpacing($0, axis: .vertical, imageSize: imageSize) }

        let hasGrid = horizontalSpacing != nil && verticalSpacing != nil
        let gridSpacing: Double? = {
            guard let h = horizontalSpacing, let v = verticalSpacing else { return nil }
            return (h + v) / 2.0
        }()

        // Step 5: Remove grid lines from binary image (or return binary as-is)
        let cleanedCG: CGImage
        if hasGrid {
            cleanedCG = removeGrid(
                from: binary,
                horizontalLines: horizontalLines,
                verticalLines: verticalLines,
                imageSize: imageSize,
                context: context
            ) ?? binaryCG
        } else {
            cleanedCG = binaryCG
        }

        return GridDetectionResult(
            hasGrid: hasGrid,
            gridSpacingPixels: gridSpacing,
            cleanedImage: cleanedCG,
            originalImage: image,
            imageSize: imageSize
        )
    }

    // MARK: - Step 1: Grayscale Conversion

    /// Convert the image to grayscale using CIPhotoEffectMono.
    private static func applyGrayscale(_ input: CIImage) -> CIImage? {
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        return filter.outputImage
    }

    // MARK: - Step 2: Adaptive Threshold (Binary)

    /// Apply CIColorThreshold at 0.5 to produce a binary image (dark ink = black, paper = white).
    private static func applyThreshold(_ input: CIImage) -> CIImage? {
        guard let filter = CIFilter(name: "CIColorThreshold") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0.5, forKey: "inputThreshold")
        return filter.outputImage
    }

    // MARK: - Step 3: Extract Grid Lines

    /// Use morphological open (erode then dilate) to isolate horizontal and vertical grid lines.
    /// A wide horizontal kernel preserves only long horizontal structures (grid lines).
    /// A tall vertical kernel preserves only long vertical structures.
    /// - Returns: Tuple of optional CGImages for (horizontal, vertical) detected line masks
    private static func extractGridLines(
        _ binaryImage: CIImage,
        imageSize: CGSize,
        context: CIContext
    ) -> (horizontal: CGImage?, vertical: CGImage?) {
        // Kernel dimensions: image dimension / 30, minimum 20 pixels
        let horizontalKernelWidth = max(20.0, imageSize.width / 30.0)
        let verticalKernelHeight = max(20.0, imageSize.height / 30.0)

        // Horizontal lines: wide kernel — keeps only structures wider than kernelWidth
        let horizontalCI = applyMorphology(
            binaryImage,
            kernelWidth: horizontalKernelWidth,
            kernelHeight: 1.0,
            context: context
        )

        // Vertical lines: tall kernel — keeps only structures taller than kernelHeight
        let verticalCI = applyMorphology(
            binaryImage,
            kernelWidth: 1.0,
            kernelHeight: verticalKernelHeight,
            context: context
        )

        let horizontalCG = horizontalCI.flatMap { context.createCGImage($0, from: $0.extent) }
        let verticalCG = verticalCI.flatMap { context.createCGImage($0, from: $0.extent) }

        return (horizontalCG, verticalCG)
    }

    // MARK: - Morphological Open (Erode + Dilate)

    /// Apply a morphological open with a *rectangular* structuring element:
    /// erode (`CIMorphologyRectangleMinimum`) then dilate (`CIMorphologyRectangleMaximum`).
    ///
    /// A rectangular kernel is required to isolate a single axis. Callers pass an
    /// asymmetric kernel — wide-and-short `(horizontalKernelWidth, 1)` to keep only
    /// long horizontal structures, or tall-and-narrow `(1, verticalKernelHeight)` to
    /// keep only long vertical structures. A circular disk kernel (the previous
    /// `CIMorphologyMinimum`/`Maximum`) erodes and dilates the same disk in both
    /// passes, so it cannot isolate an axis and corrupts grid-line separation.
    ///
    /// `CIMorphologyRectangle*` exposes `inputWidth`/`inputHeight` (each rounded to the
    /// nearest odd integer by the filter). We round explicitly to odd integers first so
    /// the opening is deterministic and the kernel never collapses below 1 pixel.
    /// - Parameters:
    ///   - input: The binary CIImage to process
    ///   - kernelWidth: Width of the structuring element in pixels
    ///   - kernelHeight: Height of the structuring element in pixels
    ///   - context: CIContext for rendering
    /// - Returns: The morphologically opened CIImage, or nil on failure
    private static func applyMorphology(
        _ input: CIImage,
        kernelWidth: Double,
        kernelHeight: Double,
        context: CIContext
    ) -> CIImage? {
        let widthOdd = oddKernelDimension(kernelWidth)
        let heightOdd = oddKernelDimension(kernelHeight)

        // Erode: shrink bright regions → removes structures that don't span the kernel
        guard let erodeFilter = CIFilter(name: "CIMorphologyRectangleMinimum") else { return nil }
        erodeFilter.setValue(input, forKey: kCIInputImageKey)
        erodeFilter.setValue(widthOdd, forKey: "inputWidth")
        erodeFilter.setValue(heightOdd, forKey: "inputHeight")
        guard let eroded = erodeFilter.outputImage else { return nil }

        // Dilate: expand bright regions back → restores structures that survived erosion
        guard let dilateFilter = CIFilter(name: "CIMorphologyRectangleMaximum") else { return nil }
        dilateFilter.setValue(eroded, forKey: kCIInputImageKey)
        dilateFilter.setValue(widthOdd, forKey: "inputWidth")
        dilateFilter.setValue(heightOdd, forKey: "inputHeight")
        return dilateFilter.outputImage
    }

    /// Round a kernel dimension to the nearest positive odd integer (minimum 1).
    /// `CIMorphologyRectangle*` requires odd integer dimensions; rounding here keeps
    /// the structuring element symmetric about its center and never below 1 pixel.
    private static func oddKernelDimension(_ value: Double) -> Int {
        let rounded = max(1, Int(value.rounded()))
        return rounded % 2 == 0 ? rounded + 1 : rounded
    }

    // MARK: - Step 4: Measure Line Spacing

    /// Analyze a grid-line mask to measure the average spacing between detected lines.
    /// Projects the mask to a 1D profile (sum of dark pixels per row or column), finds
    /// peaks, and checks regularity.
    /// - Parameters:
    ///   - lineImage: CGImage mask of detected lines (horizontal or vertical)
    ///   - axis: Which axis to project along
    ///   - imageSize: The full image dimensions for validation
    /// - Returns: Average spacing in pixels if a regular grid is detected (≥5 lines,
    ///   coefficient of variation < 0.2), or nil if no regular grid found
    private static func measureLineSpacing(
        _ lineImage: CGImage,
        axis: Axis,
        imageSize: CGSize
    ) -> Double? {
        // Get raw pixel data from the CGImage
        guard let dataProvider = lineImage.dataProvider,
              let pixelData = dataProvider.data else {
            return nil
        }

        let ptr = CFDataGetBytePtr(pixelData)
        let width = lineImage.width
        let height = lineImage.height
        let bytesPerRow = lineImage.bytesPerRow
        let bitsPerPixel = lineImage.bitsPerPixel
        let bytesPerPixel = bitsPerPixel / 8

        // Build a 1D profile: for horizontal grid lines, project along columns (sum dark
        // pixels in each row → peaks are rows where a horizontal line lives).
        // For vertical grid lines, project along rows (sum dark pixels in each column).
        let profileLength: Int
        let sampleCount: Int

        switch axis {
        case .horizontal:
            // Each row is one entry in the profile; we sum dark pixels across columns
            profileLength = height
            sampleCount = width
        case .vertical:
            // Each column is one entry in the profile; we sum dark pixels across rows
            profileLength = width
            sampleCount = height
        }

        guard profileLength > 0, sampleCount > 0, let basePtr = ptr else { return nil }

        // Build the 1D projection profile
        var profile = [Double](repeating: 0.0, count: profileLength)

        switch axis {
        case .horizontal:
            // Sum dark pixels per row
            for row in 0..<height {
                var rowSum = 0.0
                let rowBase = row * bytesPerRow
                for col in 0..<width {
                    let offset = rowBase + col * bytesPerPixel
                    // In a binary image after threshold, dark pixels (ink/lines) have low
                    // luminance values. A pixel is "dark" if its first channel value is < 128.
                    let pixelValue = basePtr[offset]
                    if pixelValue < 128 {
                        rowSum += 1.0
                    }
                }
                profile[row] = rowSum
            }
        case .vertical:
            // Sum dark pixels per column
            for col in 0..<width {
                var colSum = 0.0
                for row in 0..<height {
                    let offset = row * bytesPerRow + col * bytesPerPixel
                    let pixelValue = basePtr[offset]
                    if pixelValue < 128 {
                        colSum += 1.0
                    }
                }
                profile[col] = colSum
            }
        }

        // Find the peak threshold: any profile value above (max / 3) is considered a line
        guard let maxValue = profile.max(), maxValue > 0 else { return nil }
        let peakThreshold = maxValue / 3.0

        // Identify peak positions — scan for contiguous runs above threshold and record
        // the center of each run as the peak position
        var peaks: [Double] = []
        var inPeak = false
        var peakStart = 0

        for i in 0..<profileLength {
            if profile[i] > peakThreshold {
                if !inPeak {
                    inPeak = true
                    peakStart = i
                }
            } else {
                if inPeak {
                    // Record center of the peak run
                    let peakCenter = Double(peakStart + i - 1) / 2.0
                    peaks.append(peakCenter)
                    inPeak = false
                }
            }
        }
        // Handle peak that extends to the end
        if inPeak {
            let peakCenter = Double(peakStart + profileLength - 1) / 2.0
            peaks.append(peakCenter)
        }

        // Need at least 5 lines per axis for a valid grid
        guard peaks.count >= 5 else { return nil }

        // Calculate spacings between consecutive peaks
        var spacings: [Double] = []
        for i in 1..<peaks.count {
            spacings.append(peaks[i] - peaks[i - 1])
        }

        guard !spacings.isEmpty else { return nil }

        // Calculate mean spacing
        let meanSpacing = spacings.reduce(0.0, +) / Double(spacings.count)

        guard meanSpacing > 0 else { return nil }

        // Calculate coefficient of variation (stddev / mean)
        // A regular grid will have very consistent spacing → low CV
        let variance = spacings.reduce(0.0) { sum, s in
            let diff = s - meanSpacing
            return sum + diff * diff
        } / Double(spacings.count)
        let stddev = sqrt(variance)
        let coefficientOfVariation = stddev / meanSpacing

        // Regular grid: CV < 0.2
        guard coefficientOfVariation < 0.2 else { return nil }

        return meanSpacing
    }

    // MARK: - Step 5: Remove Grid Lines

    /// Subtract the detected horizontal and vertical grid line masks from the binary image
    /// using CISubtractBlendMode, leaving only the user's drawn lines.
    /// - Parameters:
    ///   - binaryImage: The thresholded binary CIImage (ink + grid)
    ///   - horizontalLines: Optional CGImage mask of horizontal grid lines
    ///   - verticalLines: Optional CGImage mask of vertical grid lines
    ///   - imageSize: The full image dimensions
    ///   - context: CIContext for rendering
    /// - Returns: A CGImage with grid lines subtracted, or nil on failure
    private static func removeGrid(
        from binaryImage: CIImage,
        horizontalLines: CGImage?,
        verticalLines: CGImage?,
        imageSize: CGSize,
        context: CIContext
    ) -> CGImage? {
        var result = binaryImage

        // Subtract horizontal grid lines
        if let hLines = horizontalLines {
            let hCI = CIImage(cgImage: hLines)
            guard let subtractFilter = CIFilter(name: "CISubtractBlendMode") else { return nil }
            subtractFilter.setValue(result, forKey: kCIInputImageKey)
            subtractFilter.setValue(hCI, forKey: kCIInputBackgroundImageKey)
            guard let subtracted = subtractFilter.outputImage else { return nil }
            result = subtracted
        }

        // Subtract vertical grid lines
        if let vLines = verticalLines {
            let vCI = CIImage(cgImage: vLines)
            guard let subtractFilter = CIFilter(name: "CISubtractBlendMode") else { return nil }
            subtractFilter.setValue(result, forKey: kCIInputImageKey)
            subtractFilter.setValue(vCI, forKey: kCIInputBackgroundImageKey)
            guard let subtracted = subtractFilter.outputImage else { return nil }
            result = subtracted
        }

        return context.createCGImage(result, from: result.extent)
    }
}
