//
//  ProjectPhotoDisplayMapper.swift
//  OPS
//

import Foundation

enum ProjectPhotoDeleteTarget: Equatable {
    case projectImage(sourceURL: String)
    case annotation(sourceURL: String, renderedURL: String)

    var sourceURL: String {
        switch self {
        case .projectImage(let sourceURL),
             .annotation(let sourceURL, _):
            return sourceURL
        }
    }

    var renderedURL: String? {
        switch self {
        case .projectImage:
            return nil
        case .annotation(_, let renderedURL):
            return renderedURL
        }
    }
}

struct ProjectPhotoDisplayItem: Equatable, Identifiable {
    let displayURL: String
    let sourceURL: String
    let deleteTarget: ProjectPhotoDeleteTarget

    init(
        displayURL: String,
        sourceURL: String,
        deleteTarget: ProjectPhotoDeleteTarget? = nil
    ) {
        self.displayURL = displayURL
        self.sourceURL = sourceURL
        self.deleteTarget = deleteTarget ?? .projectImage(sourceURL: sourceURL)
    }

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
        let sourceURLSet = Set(sourceURLs)

        func append(displayURL: String, sourceURL: String, deleteTarget: ProjectPhotoDeleteTarget) {
            guard !displayURL.isEmpty, seenDisplayURLs.insert(displayURL).inserted else {
                return
            }
            result.append(
                ProjectPhotoDisplayItem(
                    displayURL: displayURL,
                    sourceURL: sourceURL,
                    deleteTarget: deleteTarget
                )
            )
        }

        for sourceURL in sourceURLs {
            if let renderedURL = renderedURLsBySource[sourceURL], !renderedURL.isEmpty {
                append(
                    displayURL: renderedURL,
                    sourceURL: sourceURL,
                    deleteTarget: .projectImage(sourceURL: sourceURL)
                )
            } else {
                append(
                    displayURL: sourceURL,
                    sourceURL: sourceURL,
                    deleteTarget: .projectImage(sourceURL: sourceURL)
                )
            }
        }

        for renderedURL in renderedDeliverableURLs {
            let sourceURL = sourceByRenderedURL[renderedURL] ?? renderedURL
            let deleteTarget: ProjectPhotoDeleteTarget = sourceURLSet.contains(sourceURL)
                ? .projectImage(sourceURL: sourceURL)
                : .annotation(sourceURL: sourceURL, renderedURL: renderedURL)
            append(
                displayURL: renderedURL,
                sourceURL: sourceURL,
                deleteTarget: deleteTarget
            )
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
