//
//  AnnotationFeedPolicy.swift
//  OPS
//
//  Pure rules for how photo annotations surface in the project Activity feed.
//  Kept free of SwiftData/SwiftUI so the inclusion + labelling logic is unit
//  testable in isolation (mirrors AnnotationClearPlanner / ProjectPhotoDisplayMapper).
//

import Foundation

enum AnnotationFeedPolicy {
    /// An annotation earns an Activity-feed card if it carries markup (an
    /// uploaded overlay) OR a text note. Drawing markup alone is now feed-worthy
    /// — it shows as "marked up a photo". Pure dimensioned captures (no overlay,
    /// no note) and empty rows stay out.
    static func belongsInFeed(annotationURL: String?, note: String) -> Bool {
        hasMarkup(annotationURL: annotationURL)
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Subtitle verb shown under the author's name on the feed card. Markup
    /// leads when present (that's the headline action); otherwise it's a comment.
    static func actionLabel(annotationURL: String?) -> String {
        hasMarkup(annotationURL: annotationURL) ? "marked up a photo" : "commented on a photo"
    }

    /// True when the annotation has a synced overlay PNG (i.e. real markup).
    static func hasMarkup(annotationURL: String?) -> Bool {
        guard let annotationURL else { return false }
        return !annotationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
