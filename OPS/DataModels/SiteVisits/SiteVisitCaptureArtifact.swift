//
//  SiteVisitCaptureArtifact.swift
//  OPS
//
//  Pre-project capture packet artifacts for site visits.
//

import Foundation
import SwiftData

enum SiteVisitCaptureArtifactKind: String, Codable, CaseIterable {
    case photo = "photo"
    case annotatedPhoto = "annotated_photo"
    case dimensionedPhoto = "dimensioned_photo"
    case note = "note"
    case transcript = "transcript"
    case measurement = "measurement"
    case deckDesign = "deck_design"
}

enum SiteVisitCaptureSource: String, Codable, CaseIterable {
    case camera = "camera"
    case gallery = "gallery"
    case microphone = "microphone"
    case keyboard = "keyboard"
    case laser = "laser"
    case lidar = "lidar"
    case deckBuilder = "deck_builder"
    case manual = "manual"
}

@Model
final class SiteVisitCaptureArtifact: Identifiable {
    @Attribute(.unique) var id: String
    var siteVisitId: String
    var companyId: String
    var opportunityId: String?
    var kind: SiteVisitCaptureArtifactKind
    var source: SiteVisitCaptureSource

    var title: String?
    var body: String?
    var localAssetURL: String?
    var renderedAssetURL: String?
    var thumbnailURL: String?
    var dimensionsJSON: String?
    var deckDesignId: String?

    var includedInProjectReview: Bool
    var capturedAt: Date
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    var needsSync: Bool
    var lastSyncedAt: Date?

    init(
        id: String = UUID().uuidString,
        siteVisitId: String,
        companyId: String,
        opportunityId: String? = nil,
        kind: SiteVisitCaptureArtifactKind,
        source: SiteVisitCaptureSource,
        title: String? = nil,
        body: String? = nil,
        localAssetURL: String? = nil,
        renderedAssetURL: String? = nil,
        thumbnailURL: String? = nil,
        dimensionsJSON: String? = nil,
        deckDesignId: String? = nil,
        includedInProjectReview: Bool = true,
        capturedAt: Date = Date(),
        createdBy: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.siteVisitId = siteVisitId
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.kind = kind
        self.source = source
        self.title = title
        self.body = body
        self.localAssetURL = localAssetURL
        self.renderedAssetURL = renderedAssetURL
        self.thumbnailURL = thumbnailURL
        self.dimensionsJSON = dimensionsJSON
        self.deckDesignId = deckDesignId
        self.includedInProjectReview = includedInProjectReview
        self.capturedAt = capturedAt
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.needsSync = true
    }

    var isActive: Bool {
        deletedAt == nil
    }

    var pipesToProjectPhotos: Bool {
        switch kind {
        case .photo, .annotatedPhoto, .dimensionedPhoto:
            return true
        case .note, .transcript, .measurement, .deckDesign:
            return false
        }
    }

    var pipesToProjectNotes: Bool {
        switch kind {
        case .note, .transcript:
            return true
        case .photo, .annotatedPhoto, .dimensionedPhoto, .measurement, .deckDesign:
            return false
        }
    }

    var pipesToProjectMeasurements: Bool {
        switch kind {
        case .measurement, .dimensionedPhoto:
            return true
        case .photo, .annotatedPhoto, .note, .transcript, .deckDesign:
            return false
        }
    }

    var pipesToProjectDeckDesign: Bool {
        kind == .deckDesign && deckDesignId != nil
    }

    var previewAssetURL: String? {
        renderedAssetURL ?? thumbnailURL ?? localAssetURL
    }
}

enum SiteVisitCaptureCompletionPolicy {
    static func canComplete(_ artifacts: [SiteVisitCaptureArtifact]) -> Bool {
        artifacts.contains { $0.isActive }
    }
}

struct SiteVisitCaptureReviewSummary: Equatable {
    let photoCount: Int
    let noteCount: Int
    let measurementCount: Int
    let deckDesignCount: Int

    var includedArtifactCount: Int {
        photoCount + noteCount + measurementCount + deckDesignCount
    }

    var canCreateProject: Bool {
        includedArtifactCount > 0
    }

    static func make(from artifacts: [SiteVisitCaptureArtifact]) -> SiteVisitCaptureReviewSummary {
        let included = artifacts.filter { $0.isActive && $0.includedInProjectReview }
        return SiteVisitCaptureReviewSummary(
            photoCount: included.filter(\.pipesToProjectPhotos).count,
            noteCount: included.filter(\.pipesToProjectNotes).count,
            measurementCount: included.filter(\.pipesToProjectMeasurements).count,
            deckDesignCount: included.filter(\.pipesToProjectDeckDesign).count
        )
    }
}

struct SiteVisitProjectPayload: Equatable {
    let siteVisitId: String
    let opportunityId: String
    let projectTitle: String
    let address: String?
    let photoArtifactIds: [String]
    let measurementArtifactIds: [String]
    let noteArtifactIds: [String]
    let deckDesignIds: [String]
    let checklistAnswerIds: [String]
    let checklistLines: [String]
}

enum SiteVisitProjectPayloadBuilder {
    static func payload(
        siteVisitId: String,
        opportunityId: String,
        projectTitle: String,
        address: String?,
        artifacts: [SiteVisitCaptureArtifact],
        checklistAnswers: [SiteVisitChecklistAnswer] = []
    ) -> SiteVisitProjectPayload {
        let included = artifacts
            .filter { $0.isActive && $0.includedInProjectReview }
            .sorted { $0.capturedAt < $1.capturedAt }
        let includedAnswers = checklistAnswers
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }

        return SiteVisitProjectPayload(
            siteVisitId: siteVisitId,
            opportunityId: opportunityId,
            projectTitle: projectTitle,
            address: address,
            photoArtifactIds: included.filter(\.pipesToProjectPhotos).map(\.id),
            measurementArtifactIds: included.filter(\.pipesToProjectMeasurements).map(\.id),
            noteArtifactIds: included.filter(\.pipesToProjectNotes).map(\.id),
            deckDesignIds: included.compactMap { artifact in
                artifact.pipesToProjectDeckDesign ? artifact.deckDesignId : nil
            },
            checklistAnswerIds: includedAnswers.map(\.id),
            checklistLines: includedAnswers.compactMap(Self.checklistLine)
        )
    }

    private static func checklistLine(from answer: SiteVisitChecklistAnswer) -> String? {
        let value = answer.answerValue
        let renderedValue: String
        switch answer.kind {
        case .checkbox:
            guard let boolValue = value.boolValue else { return nil }
            renderedValue = boolValue ? "YES" : "NO"
        case .yesNoNA:
            guard let choice = value.choice?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !choice.isEmpty else { return nil }
            renderedValue = choice.uppercased()
        case .shortText, .longText, .measurement:
            guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            renderedValue = text
        case .photo, .photoMarkup:
            guard !value.artifactIds.isEmpty else { return nil }
            renderedValue = "\(value.artifactIds.count) CAPTURED"
        case .deckDesign:
            guard let deckDesignId = value.deckDesignId,
                  !deckDesignId.isEmpty else { return nil }
            renderedValue = "DECK DESIGN \(deckDesignId)"
        }
        return "CHECKLIST :: \(answer.label): \(renderedValue)"
    }
}
