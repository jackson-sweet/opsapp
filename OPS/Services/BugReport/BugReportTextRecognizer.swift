//
//  BugReportTextRecognizer.swift
//  OPS
//
//  Reads the text off the pick-time capture of the app window (bug 14e5a792).
//
//  This is how a picked element gets a human name when its component did not
//  supply one — a house button's label is a view, not a string — and how a
//  pick on plain text, with no component under it, is named at all. SwiftUI
//  offers no in-process way to read its own rendered strings (it publishes no
//  accessibility nodes unless an assistive technology is running), so the
//  pixels are the source.
//
//  Runs once per pick session, off the main thread, on the capture taken
//  when the pick layer arms. Language correction is off: the app's strings
//  are labels, codes and names, not prose, and "correcting" `INV-00284` or a
//  client's surname would make the report lie.
//

import UIKit
import Vision

enum BugReportTextRecognizer {

    /// Every line of text in `image`, in the image's point space (which, for
    /// a capture of the app window, is app-window points). Empty on any
    /// failure — a pick without text still resolves to a component or region.
    static func recognize(_ image: UIImage) async -> [BugReportTextLine] {
        guard let cgImage = image.cgImage else { return [] }
        let size = image.size
        return await Task.detached(priority: .userInitiated) {
            lines(in: cgImage, size: size)
        }.value
    }

    private static func lines(in cgImage: CGImage, size: CGSize) -> [BugReportTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            DebugLogger.shared.log(
                "Bug report text recognition failed: \(error.localizedDescription)",
                level: .warning,
                category: "BugReport"
            )
            return []
        }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return BugReportTextLine(
                text: candidate.string,
                frame: frame(of: observation.boundingBox, in: size)
            )
        }
    }

    /// Vision boxes are normalized with a bottom-left origin; the app works
    /// top-left in points.
    static func frame(of normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: (1 - normalized.maxY) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}
