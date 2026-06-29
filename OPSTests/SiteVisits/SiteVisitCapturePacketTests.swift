//
//  SiteVisitCapturePacketTests.swift
//  OPSTests
//
//  Site-visit capture packet rules. The packet exists before a project does;
//  project creation consumes the reviewed packet after the visit.
//

import XCTest
import SwiftData
@testable import OPS

final class SiteVisitCapturePacketTests: XCTestCase {

    func test_builtinSiteVisitTypesCreateChecklistAnswerSnapshots() throws {
        let templates = SiteVisitType.builtInTemplates(
            companyId: "company-1",
            deckBuilderEnabled: true
        )

        let generic = try XCTUnwrap(templates.first { $0.slug == "generic_site_visit" })
        XCTAssertEqual(generic.name, "Generic Site Visit")
        XCTAssertTrue(generic.isSystemTemplate)
        XCTAssertTrue(generic.isDefault)
        XCTAssertTrue(generic.fields.contains { $0.kind == .longText && $0.label == "Scope notes" })

        let deck = try XCTUnwrap(templates.first { $0.slug == "deck_estimate" })
        XCTAssertTrue(deck.fields.contains { field in
            field.kind == .deckDesign && field.required && field.label == "Deck design"
        })

        let answers = SiteVisitChecklistAnswer.makeAnswers(
            for: deck,
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: "lead-1",
            createdBy: "user-1"
        )

        XCTAssertEqual(answers.count, deck.fields.count)
        XCTAssertEqual(answers.map(\.label), deck.fields.sorted { $0.sortOrder < $1.sortOrder }.map(\.label))
        XCTAssertTrue(answers.allSatisfy { $0.siteVisitId == "visit-1" })
        XCTAssertTrue(answers.allSatisfy { $0.siteVisitTypeId == deck.id })
        XCTAssertTrue(answers.allSatisfy { $0.opportunityId == "lead-1" })
        XCTAssertTrue(answers.allSatisfy { $0.answerValue == .empty })
        XCTAssertTrue(answers.allSatisfy(\.needsSync))
    }

    func test_completionRequiresAtLeastOneCapturedArtifact() {
        XCTAssertFalse(SiteVisitCaptureCompletionPolicy.canComplete([]))

        let deletedNote = SiteVisitCaptureArtifact.fixture(
            kind: .note,
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        deletedNote.deletedAt = Date()
        XCTAssertFalse(SiteVisitCaptureCompletionPolicy.canComplete([deletedNote]))

        let activeNote = SiteVisitCaptureArtifact.fixture(
            kind: .note,
            capturedAt: Date(timeIntervalSince1970: 2)
        )
        XCTAssertTrue(SiteVisitCaptureCompletionPolicy.canComplete([deletedNote, activeNote]))
    }

    func test_reviewSummaryCountsIncludedEvidenceByProjectBucket() {
        let photo = SiteVisitCaptureArtifact.fixture(kind: .photo, capturedAt: Date(timeIntervalSince1970: 1))
        let dimensionedPhoto = SiteVisitCaptureArtifact.fixture(kind: .dimensionedPhoto, capturedAt: Date(timeIntervalSince1970: 2))
        let note = SiteVisitCaptureArtifact.fixture(kind: .note, capturedAt: Date(timeIntervalSince1970: 3))
        let excludedMeasurement = SiteVisitCaptureArtifact.fixture(kind: .measurement, capturedAt: Date(timeIntervalSince1970: 4))
        excludedMeasurement.includedInProjectReview = false
        let deck = SiteVisitCaptureArtifact.fixture(
            kind: .deckDesign,
            deckDesignId: "deck-1",
            capturedAt: Date(timeIntervalSince1970: 5)
        )

        let summary = SiteVisitCaptureReviewSummary.make(
            from: [excludedMeasurement, deck, dimensionedPhoto, note, photo]
        )

        XCTAssertEqual(summary.photoCount, 2, "Plain and dimensioned photos both pipe into project photos.")
        XCTAssertEqual(summary.noteCount, 1)
        XCTAssertEqual(summary.measurementCount, 1, "Dimensioned photos also pipe measurements into project scope.")
        XCTAssertEqual(summary.deckDesignCount, 1)
        XCTAssertTrue(summary.canCreateProject)
    }

    func test_projectPayloadUsesIncludedArtifactsInCaptureOrder() {
        let excludedPhoto = SiteVisitCaptureArtifact.fixture(kind: .photo, capturedAt: Date(timeIntervalSince1970: 1))
        excludedPhoto.includedInProjectReview = false

        let note = SiteVisitCaptureArtifact.fixture(
            id: "note-1",
            kind: .transcript,
            capturedAt: Date(timeIntervalSince1970: 4)
        )
        let dimensionedPhoto = SiteVisitCaptureArtifact.fixture(
            id: "lidar-1",
            kind: .dimensionedPhoto,
            capturedAt: Date(timeIntervalSince1970: 2)
        )
        let manualMeasurement = SiteVisitCaptureArtifact.fixture(
            id: "measure-1",
            kind: .measurement,
            capturedAt: Date(timeIntervalSince1970: 3)
        )
        let deck = SiteVisitCaptureArtifact.fixture(
            id: "deck-artifact-1",
            kind: .deckDesign,
            deckDesignId: "deck-1",
            capturedAt: Date(timeIntervalSince1970: 5)
        )
        let checklistMeasurement = SiteVisitChecklistAnswer(
            id: "answer-1",
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: "lead-1",
            siteVisitTypeId: "type-1",
            fieldId: "field-measurements",
            label: "Field measurements",
            kind: .measurement,
            required: true,
            sortOrder: 10,
            answerValue: .text("12 ft by 16 ft"),
            createdBy: "user-1"
        )
        let unanswered = SiteVisitChecklistAnswer(
            id: "answer-2",
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: "lead-1",
            siteVisitTypeId: "type-1",
            fieldId: "field-notes",
            label: "Open notes",
            kind: .longText,
            required: false,
            sortOrder: 20,
            createdBy: "user-1"
        )

        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            projectTitle: "Maple deck rebuild",
            address: "1100 Maple Ave",
            artifacts: [deck, note, excludedPhoto, manualMeasurement, dimensionedPhoto],
            checklistAnswers: [unanswered, checklistMeasurement]
        )

        XCTAssertEqual(payload.siteVisitId, "visit-1")
        XCTAssertEqual(payload.opportunityId, "lead-1")
        XCTAssertEqual(payload.projectTitle, "Maple deck rebuild")
        XCTAssertEqual(payload.address, "1100 Maple Ave")
        XCTAssertEqual(payload.photoArtifactIds, ["lidar-1"])
        XCTAssertEqual(payload.measurementArtifactIds, ["lidar-1", "measure-1"])
        XCTAssertEqual(payload.noteArtifactIds, ["note-1"])
        XCTAssertEqual(payload.deckDesignIds, ["deck-1"])
        XCTAssertEqual(payload.checklistAnswerIds, ["answer-1", "answer-2"])
        XCTAssertEqual(payload.checklistLines, ["CHECKLIST :: Field measurements: 12 ft by 16 ft"])
    }

    @MainActor
    func test_handoffAppliesReviewedPacketToCreatedProject() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let deck = DeckDesign(
            id: "deck-1",
            companyId: "company-1",
            projectId: nil,
            title: "Visit deck",
            createdBy: "user-1"
        )
        context.insert(deck)

        let photo = SiteVisitCaptureArtifact.fixture(
            id: "photo-1",
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        photo.localAssetURL = "local://project_images/site-photo.jpg"
        let note = SiteVisitCaptureArtifact.fixture(
            id: "note-1",
            kind: .note,
            capturedAt: Date(timeIntervalSince1970: 2)
        )
        note.body = "Client wants black rail."
        let measurement = SiteVisitCaptureArtifact.fixture(
            id: "measure-1",
            kind: .measurement,
            capturedAt: Date(timeIntervalSince1970: 3)
        )
        measurement.body = "Deck is 12 ft by 18 ft."
        let deckArtifact = SiteVisitCaptureArtifact.fixture(
            id: "deck-artifact-1",
            kind: .deckDesign,
            deckDesignId: "deck-1",
            capturedAt: Date(timeIntervalSince1970: 4)
        )
        let checklistAnswer = SiteVisitChecklistAnswer(
            id: "answer-1",
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: "lead-1",
            siteVisitTypeId: "type-1",
            fieldId: "access",
            label: "Access clear",
            kind: .yesNoNA,
            required: false,
            sortOrder: 10,
            answerValue: .choice("yes"),
            createdBy: "user-1"
        )

        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            projectTitle: "Maple deck",
            address: "1100 Maple Ave",
            artifacts: [photo, note, measurement, deckArtifact],
            checklistAnswers: [checklistAnswer]
        )

        SiteVisitProjectHandoff.apply(
            payload: payload,
            artifacts: [photo, note, measurement, deckArtifact],
            projectId: "project-1",
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )

        let photos = try context.fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos.first?.projectId, "project-1")
        XCTAssertEqual(photos.first?.source, "site_visit")
        XCTAssertEqual(photos.first?.siteVisitId, "visit-1")
        XCTAssertTrue(photos.first?.needsSync == true)

        let notes = try context.fetch(FetchDescriptor<ProjectNote>())
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes.first?.content.contains("Client wants black rail.") == true)
        XCTAssertTrue(notes.first?.content.contains("MEASURE :: Deck is 12 ft by 18 ft.") == true)
        XCTAssertTrue(notes.first?.content.contains("CHECKLIST :: Access clear: YES") == true)
        XCTAssertTrue(notes.first?.needsSync == true)

        let designs = try context.fetch(FetchDescriptor<DeckDesign>())
        XCTAssertEqual(designs.first?.projectId, "project-1")
        XCTAssertTrue(designs.first?.needsSync == true)
    }

    @MainActor
    func test_handoffCreatesDimensionedPhotoAnnotationForProject() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let dimensions = fixtureDimensions()
        var enriched = dimensions
        enriched.depthAssetUrl = "file:///tmp/site-visit.depth.fp32"
        enriched.sidecarMetadataUrl = "file:///tmp/site-visit.metadata.json"

        let dimensioned = SiteVisitCaptureArtifact.fixture(
            id: "dimensioned-1",
            kind: .dimensionedPhoto,
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        dimensioned.localAssetURL = "local://project_images/site-visit-dimensioned.heic"
        dimensioned.renderedAssetURL = "local://project_images/site-visit-dimensioned.rendered.png"
        dimensioned.dimensionsJSON = String(
            data: try DimensionsData.jsonEncoder.encode(enriched),
            encoding: .utf8
        )
        dimensioned.body = "1 MEASUREMENT :: WIDTH 12′"

        let payload = SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            projectTitle: "Maple deck",
            address: "1100 Maple Ave",
            artifacts: [dimensioned]
        )

        SiteVisitProjectHandoff.apply(
            payload: payload,
            artifacts: [dimensioned],
            projectId: "project-1",
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )

        let photos = try context.fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos.first?.url, "local://project_images/site-visit-dimensioned.heic")
        XCTAssertEqual(photos.first?.renderedURL, "local://project_images/site-visit-dimensioned.rendered.png")

        let annotations = try context.fetch(FetchDescriptor<PhotoAnnotation>())
        XCTAssertEqual(annotations.count, 1)
        let annotation = try XCTUnwrap(annotations.first)
        XCTAssertEqual(annotation.projectId, "project-1")
        XCTAssertEqual(annotation.companyId, "company-1")
        XCTAssertEqual(annotation.photoURL, "local://project_images/site-visit-dimensioned.heic")
        XCTAssertEqual(annotation.renderedPhotoURL, "local://project_images/site-visit-dimensioned.rendered.png")
        XCTAssertEqual(annotation.localDepthMapPath, "/tmp/site-visit.depth.fp32")
        XCTAssertEqual(annotation.localSidecarPath, "/tmp/site-visit.metadata.json")
        XCTAssertEqual(annotation.dimensions?.measurements.first?.label, "Width")
        XCTAssertTrue(annotation.needsSync)
    }

    @MainActor
    func test_dimensionedCapturePersistsPreProjectArtifactWithLocalEvidenceAndDimensions() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let captured = try fixtureCapturedAssets()
        let dimensions = fixtureDimensions()

        let artifact = try SiteVisitDimensionedCaptureStore.persist(
            captured: captured,
            dimensions: dimensions,
            siteVisitId: "visit-1",
            opportunityId: "lead-1",
            companyId: "company-1",
            createdBy: "user-1",
            modelContext: context,
            assetSaver: { assets in
                SiteVisitDimensionedCaptureStore.SavedAssets(
                    localPhotoURL: "local://project_images/site-visit-dimensioned.heic",
                    depthAssetURL: assets.depthURL?.absoluteString,
                    sidecarMetadataURL: assets.sidecarURL.absoluteString
                )
            }
        )

        XCTAssertEqual(artifact.siteVisitId, "visit-1")
        XCTAssertEqual(artifact.opportunityId, "lead-1")
        XCTAssertEqual(artifact.companyId, "company-1")
        XCTAssertEqual(artifact.kind, .dimensionedPhoto)
        XCTAssertEqual(artifact.source, .lidar)
        XCTAssertEqual(artifact.title, "LiDAR measurement")
        XCTAssertEqual(artifact.localAssetURL, "local://project_images/site-visit-dimensioned.heic")
        XCTAssertEqual(artifact.createdBy, "user-1")
        XCTAssertTrue(artifact.includedInProjectReview)
        XCTAssertTrue(artifact.needsSync)
        XCTAssertTrue(artifact.body?.contains("WIDTH") == true)
        XCTAssertTrue(artifact.body?.contains("1 MEASUREMENT") == true)

        let dimensionsJSON = try XCTUnwrap(artifact.dimensionsJSON)
        let decoded = try DimensionsData.jsonDecoder.decode(
            DimensionsData.self,
            from: try XCTUnwrap(dimensionsJSON.data(using: .utf8))
        )
        XCTAssertEqual(decoded.measurements.count, 1)
        XCTAssertEqual(decoded.measurements.first?.label, "Width")
        XCTAssertEqual(decoded.depthAssetUrl, captured.depthURL?.absoluteString)
        XCTAssertEqual(decoded.sidecarMetadataUrl, captured.sidecarURL.absoluteString)

        let stored = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
        XCTAssertEqual(stored.map(\.id), [artifact.id])
    }

    @MainActor
    func test_dimensionedCaptureDoesNotCreateArtifactWhenPrimaryPhotoCannotBeSaved() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let captured = try fixtureCapturedAssets()

        XCTAssertThrowsError(
            try SiteVisitDimensionedCaptureStore.persist(
                captured: captured,
                dimensions: fixtureDimensions(),
                siteVisitId: "visit-1",
                opportunityId: "lead-1",
                companyId: "company-1",
                createdBy: "user-1",
                modelContext: context,
                assetSaver: { _ in throw SiteVisitDimensionedCaptureStore.Error.primaryPhotoSaveFailed }
            )
        )

        let stored = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
        XCTAssertTrue(stored.isEmpty)
    }

    @MainActor
    func test_noteAutosaveKeepsOneLiveDraftAndDeletesItWhenCleared() throws {
        let container = try makeSiteVisitCaptureContainer()
        let context = container.mainContext
        let opportunity = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Helen Calloway"
        )
        opportunity.address = "1100 Maple Ave"
        context.insert(opportunity)
        try context.save()

        let viewModel = SiteVisitCaptureViewModel(
            opportunity: opportunity,
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )
        viewModel.loadOrCreateVisit()

        viewModel.noteDraft = "Client wants black rail."
        viewModel.autosaveNote()

        XCTAssertEqual(viewModel.activeArtifacts.count, 1)
        let first = try XCTUnwrap(viewModel.activeArtifacts.first)
        XCTAssertEqual(first.kind, .note)
        XCTAssertEqual(first.source, .keyboard)
        XCTAssertEqual(first.body, "Client wants black rail.")

        viewModel.noteDraft = "Client wants black rail. Gate code 4812."
        viewModel.autosaveNote()

        XCTAssertEqual(viewModel.activeArtifacts.count, 1)
        XCTAssertEqual(viewModel.activeArtifacts.first?.id, first.id)
        XCTAssertEqual(viewModel.activeArtifacts.first?.body, "Client wants black rail. Gate code 4812.")

        viewModel.noteDraft = "   "
        viewModel.autosaveNote()

        XCTAssertTrue(viewModel.activeArtifacts.isEmpty)
        let stored = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertNotNil(stored.first?.deletedAt)
    }

    @MainActor
    func test_selectSiteVisitTypeCreatesChecklistAnswersForActiveVisit() throws {
        let container = try makeSiteVisitCaptureContainer()
        let context = container.mainContext
        let opportunity = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Helen Calloway"
        )
        context.insert(opportunity)
        try context.save()

        let viewModel = SiteVisitCaptureViewModel(
            opportunity: opportunity,
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )
        // Deck templates only seed the required "Deck design" field when the
        // deck_builder feature is enabled; the test host's PermissionStore fails
        // closed, so enable it explicitly before the VM seeds its visit types.
        PermissionStore.shared.disabledFlags.remove("deck_builder")
        viewModel.loadOrCreateVisit()

        let deckType = try XCTUnwrap(
            viewModel.siteVisitTypes.first { $0.slug == "deck_estimate" }
        )

        viewModel.selectSiteVisitType(deckType)

        XCTAssertEqual(viewModel.selectedSiteVisitType?.id, deckType.id)
        XCTAssertEqual(viewModel.checklistAnswers.count, deckType.fields.count)
        XCTAssertTrue(viewModel.checklistAnswers.allSatisfy { $0.siteVisitId == viewModel.siteVisit?.id })
        XCTAssertEqual(
            viewModel.missingRequiredChecklistAnswers.map(\.label),
            ["Field measurements", "Deck design"]
        )

        let measurement = try XCTUnwrap(
            viewModel.checklistAnswers.first { $0.label == "Field measurements" }
        )
        viewModel.updateChecklistAnswer(measurement, value: .text("12 ft by 16 ft"))

        XCTAssertEqual(measurement.answerValue, .text("12 ft by 16 ft"))
        XCTAssertEqual(viewModel.missingRequiredChecklistAnswers.map(\.label), ["Deck design"])

        viewModel.addAdHocChecklistQuestion(label: "Gate code", kind: .shortText)

        XCTAssertTrue(viewModel.checklistAnswers.contains { answer in
            answer.label == "Gate code" && answer.kind == .shortText && answer.siteVisitTypeId == deckType.id
        })
    }

    @MainActor
    func test_answeredChecklistCanCompleteVisitAndBuildProjectPayloadWithoutArtifacts() throws {
        let container = try makeSiteVisitCaptureContainer()
        let context = container.mainContext
        let opportunity = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Helen Calloway"
        )
        context.insert(opportunity)
        try context.save()

        let viewModel = SiteVisitCaptureViewModel(
            opportunity: opportunity,
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )
        viewModel.loadOrCreateVisit()

        viewModel.addAdHocChecklistQuestion(label: "Gate code", kind: .shortText)
        let gateCode = try XCTUnwrap(
            viewModel.checklistAnswers.first { $0.label == "Gate code" }
        )
        viewModel.updateChecklistAnswer(gateCode, value: .text("4812"))

        XCTAssertTrue(viewModel.canComplete)
        XCTAssertTrue(viewModel.hasProjectEvidence)
        XCTAssertTrue(viewModel.completeVisit())

        let payload = try XCTUnwrap(viewModel.projectPayload(projectTitle: "Maple deck"))
        XCTAssertTrue(payload.photoArtifactIds.isEmpty)
        XCTAssertEqual(payload.checklistAnswerIds.last, gateCode.id)
        XCTAssertTrue(payload.checklistLines.contains("CHECKLIST :: Gate code: 4812"))
    }

    @MainActor
    func test_reassignVisitMovesVisitAndArtifactsToNewLead() throws {
        let container = try makeSiteVisitCaptureContainer()
        let context = container.mainContext
        let original = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Helen Calloway"
        )
        original.address = "1100 Maple Ave"
        let corrected = Opportunity(
            id: "lead-2",
            companyId: "company-1",
            contactName: "Arden Wilson"
        )
        corrected.address = "225 Dockside Rd"
        context.insert(original)
        context.insert(corrected)
        try context.save()

        let viewModel = SiteVisitCaptureViewModel(
            opportunity: original,
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )
        viewModel.loadOrCreateVisit()
        viewModel.noteDraft = "Rail height is low."
        viewModel.autosaveNote()

        viewModel.reassignVisit(to: corrected)

        XCTAssertEqual(viewModel.currentOpportunity?.id, "lead-2")
        XCTAssertEqual(viewModel.captureAddress, "225 Dockside Rd")

        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits.first?.opportunityId, "lead-2")
        XCTAssertEqual(visits.first?.address, "225 Dockside Rd")

        let artifacts = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.opportunityId, "lead-2")
        XCTAssertTrue(artifacts.first?.needsSync == true)

        let checklistAnswers = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
        XCTAssertFalse(checklistAnswers.isEmpty)
        XCTAssertTrue(checklistAnswers.allSatisfy { $0.opportunityId == "lead-2" })
    }

    @MainActor
    func test_updateVisitAddressCanStayVisitOnly() async throws {
        let container = try makeSiteVisitCaptureContainer()
        let context = container.mainContext
        let opportunity = Opportunity(
            id: "lead-1",
            companyId: "company-1",
            contactName: "Helen Calloway"
        )
        opportunity.address = "1100 Maple Ave"
        context.insert(opportunity)
        try context.save()

        let viewModel = SiteVisitCaptureViewModel(
            opportunity: opportunity,
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )
        viewModel.loadOrCreateVisit()

        await viewModel.updateVisitAddress(
            "225 Dockside Rd",
            persistToLead: false
        )

        XCTAssertEqual(viewModel.captureAddress, "225 Dockside Rd")
        XCTAssertEqual(opportunity.address, "1100 Maple Ave")

        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits.first?.address, "225 Dockside Rd")
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisitCaptureArtifact.self,
            ProjectPhoto.self,
            ProjectNote.self,
            PhotoAnnotation.self,
            DeckDesign.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSiteVisitCaptureContainer() throws -> ModelContainer {
        let schema = Schema([
            Opportunity.self,
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitType.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func fixtureDimensions() -> DimensionsData {
        DimensionsData(
            captureMode: .lidar,
            calibration: .init(method: .lidar, estimatedAccuracyMeters: 0.025),
            intrinsics: .init(
                fx: 1000,
                fy: 1000,
                cx: 500,
                cy: 500,
                imageWidth: 1000,
                imageHeight: 1000
            ),
            measurements: [
                .init(
                    type: .linear,
                    label: "Width",
                    worldPoints: [.init(x: 0, y: 0, z: 0), .init(x: 3.6576, y: 0, z: 0)],
                    imagePoints: [.init(x: 20, y: 30), .init(x: 240, y: 30)],
                    valueMeters: 3.6576,
                    labelPlacement: .init(side: .north, leaderLengthPx: 60),
                    source: .manual
                )
            ]
        )
    }

    private func fixtureCapturedAssets() throws -> CapturedAssets {
        let captureID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("site-visit-dimensioned-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let urls = CapturedAssets.in(directory: directory, captureID: captureID)
        try Data([0x48, 0x45, 0x49, 0x43]).write(to: urls.heicURL)
        try Data([0x00, 0x00, 0x80, 0x3F]).write(to: try XCTUnwrap(urls.depthURL))
        try Data("{\"meshAnchors\":[]}".utf8).write(to: urls.sidecarURL)

        let intrinsics = DimensionsData.Intrinsics(
            fx: 1000,
            fy: 1000,
            cx: 500,
            cy: 500,
            imageWidth: 1000,
            imageHeight: 1000
        )

        return CapturedAssets(
            heicURL: urls.heicURL,
            depthURL: urls.depthURL,
            sidecarURL: urls.sidecarURL,
            intrinsics: intrinsics,
            arkitSnapshot: .init(
                meshAnchors: [],
                cameraIntrinsics: intrinsics,
                devicePose: Array(repeating: 0, count: 16),
                timestamp: Date(timeIntervalSince1970: 1_747_166_400)
            ),
            captureID: captureID,
            captureFinishedAt: Date(timeIntervalSince1970: 1_747_166_400)
        )
    }
}

private extension SiteVisitCaptureArtifact {
    static func fixture(
        id: String = UUID().uuidString,
        kind: SiteVisitCaptureArtifactKind,
        deckDesignId: String? = nil,
        capturedAt: Date
    ) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: id,
            siteVisitId: "visit-1",
            companyId: "company-1",
            opportunityId: "lead-1",
            kind: kind,
            source: kind == .dimensionedPhoto ? .lidar : .manual,
            title: kind.rawValue,
            deckDesignId: deckDesignId,
            capturedAt: capturedAt,
            createdBy: "user-1"
        )
    }
}
