//
//  ProjectPhotoDisplayMapper.swift
//  OPS
//

import Foundation

struct ProjectPhotoDisplayItem: Equatable, Identifiable {
    let displayURL: String
    let sourceURL: String

    var id: String { displayURL }
    var syncStatusURL: String { sourceURL }
}

enum ProjectPhotoDisplayMapper {

    static func items(
        sourceURLs: [String],
        renderedURLsBySource: [String: String],
        renderedDeliverableURLs: [String]
    ) -> [ProjectPhotoDisplayItem] {
        var result: [ProjectPhotoDisplayItem] = []
        var seenDisplayURLs = Set<String>()
        let sourceByRenderedURL = Dictionary(
            renderedURLsBySource.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )

        func append(displayURL: String, sourceURL: String) {
            guard !displayURL.isEmpty, seenDisplayURLs.insert(displayURL).inserted else {
                return
            }
            result.append(ProjectPhotoDisplayItem(displayURL: displayURL, sourceURL: sourceURL))
        }

        for sourceURL in sourceURLs {
            if let renderedURL = renderedURLsBySource[sourceURL], !renderedURL.isEmpty {
                append(displayURL: renderedURL, sourceURL: sourceURL)
            } else {
                append(displayURL: sourceURL, sourceURL: sourceURL)
            }
        }

        for renderedURL in renderedDeliverableURLs {
            append(displayURL: renderedURL,
                   sourceURL: sourceByRenderedURL[renderedURL] ?? renderedURL)
        }

        return result
    }

    static func sourceURL(
        forDisplayURL displayURL: String,
        sourceURLs: [String],
        renderedURLsBySource: [String: String],
        renderedDeliverableURLs: [String]
    ) -> String {
        items(
            sourceURLs: sourceURLs,
            renderedURLsBySource: renderedURLsBySource,
            renderedDeliverableURLs: renderedDeliverableURLs
        )
        .first { $0.displayURL == displayURL }?
        .sourceURL ?? displayURL
    }
}
