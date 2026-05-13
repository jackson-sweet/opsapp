//
//  PhotoAnnotationDTOTests.swift
//  OPSTests
//
//  Verifies shared annotation DTO/read/merge paths preserve the
//  project_photo_annotations.dimensions jsonb payload used by LiDAR
//  dimensioned photo capture.
//

import SwiftData
import XCTest
@testable import OPS

final class PhotoAnnotationDTOTests: XCTestCase {

    func test_PhotoAnnotationDTO_decodesDimensionsJSON_intoModelDimensionsData() throws {
        let dto = try decodeDTO(dimensionsJSON: fixtureDimensionsJSONObject)

        let model = dto.toModel()

        let dimensionsData = try XCTUnwrap(model.dimensionsData)
        XCTAssertGreaterThan(dimensionsData.count, 0)

        let dimensions = try XCTUnwrap(model.dimensions)
        XCTAssertEqual(dimensions.schemaVersion, 1)
        XCTAssertEqual(dimensions.captureMode, .lidar)
        XCTAssertEqual(dimensions.calibration.method, .lidar)
        XCTAssertEqual(dimensions.calibration.estimatedAccuracyMeters, 0.025)
        XCTAssertEqual(dimensions.intrinsics.imageWidth, 4032)
        XCTAssertEqual(dimensions.measurements.count, 1)
        XCTAssertEqual(dimensions.measurements.first?.label, "Width")
        XCTAssertEqual(dimensions.measurements.first?.primaryDisplayUnit, .imperialFraction)
        XCTAssertEqual(dimensions.openings.count, 1)
        XCTAssertEqual(dimensions.openings.first?.type, .window)
        XCTAssertEqual(dimensions.openings.first?.measurementIds, [fixtureMeasurementID])
    }

    func test_PhotoAnnotationDTO_decodesNullDimensions_asNil() throws {
        let dto = try decodeDTO(dimensionsJSON: "null")

        XCTAssertNil(dto.toModel().dimensionsData)
        XCTAssertNil(dto.toModel().dimensions)
    }

    func test_PhotoAnnotationDTO_decodesMissingDimensions_asNil() throws {
        let dto = try decodeDTO(dimensionsJSON: nil)

        XCTAssertNil(dto.toModel().dimensionsData)
        XCTAssertNil(dto.toModel().dimensions)
    }

    func test_DataActorRealtimePhotoAnnotationMerge_updatesExistingLocalDimensions_whenRemoteIncludesDimensions() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let annotationID = "11111111-1111-1111-1111-111111111111"

        let existing = PhotoAnnotation(
            id: annotationID,
            projectId: "project-123",
            companyId: "company-abc",
            photoURL: "https://example.test/photo.heic",
            authorId: "user-xyz",
            createdAt: Date(timeIntervalSince1970: 1_747_166_400)
        )
        existing.annotationURL = nil
        existing.note = "local note"
        existing.dimensionsData = nil
        context.insert(existing)
        try context.save()

        let actor = DataActor(modelContainer: container)
        await actor.configure()
        let dto = try decodeDTO(
            id: annotationID,
            annotationURL: "https://example.test/overlay.png",
            note: "remote note",
            dimensionsJSON: fixtureDimensionsJSONObject
        )

        await actor.handleRealtimeUpdate(.photoAnnotation(dto))

        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.id == annotationID }
        )
        let merged = try XCTUnwrap(try verificationContext.fetch(descriptor).first)
        XCTAssertEqual(merged.annotationURL, "https://example.test/overlay.png")
        XCTAssertEqual(merged.note, "remote note")
        XCTAssertNotNil(merged.dimensionsData)
        XCTAssertEqual(merged.dimensions?.measurements.first?.id, fixtureMeasurementID)
        XCTAssertEqual(merged.dimensions?.openings.first?.type, .window)
        XCTAssertFalse(merged.needsSync)
    }

    // MARK: - Fixtures

    private let fixtureMeasurementID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    private var fixtureDimensionsJSONObject: String {
        """
        {
          "schema_version": 1,
          "capture_mode": "lidar",
          "calibration": {
            "method": "lidar",
            "reference_object": null,
            "scale_factor": 1.0,
            "estimated_accuracy_meters": 0.025
          },
          "intrinsics": {
            "fx": 1593.4,
            "fy": 1593.4,
            "cx": 1015.5,
            "cy": 762.0,
            "image_width": 4032,
            "image_height": 3024
          },
          "depth_asset_url": "https://cdn.example.test/depth.fp32",
          "sidecar_metadata_url": "https://cdn.example.test/metadata.json",
          "measurements": [
            {
              "id": "\(fixtureMeasurementID.uuidString)",
              "type": "linear",
              "label": "Width",
              "world_points": [
                { "x": 0.0, "y": 0.0, "z": 0.0 },
                { "x": 0.9144, "y": 0.0, "z": 0.0 }
              ],
              "image_points": [
                { "x": 100.0, "y": 500.0 },
                { "x": 800.0, "y": 500.0 }
              ],
              "value_meters": 0.9144,
              "primary_display_unit": "imperial_fraction",
              "label_placement": {
                "side": "north",
                "leader_length_px": 60.0
              },
              "source": "auto"
            }
          ],
          "openings": [
            {
              "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
              "type": "window",
              "bounding_polygon": [
                { "x": 0.0, "y": 0.0 },
                { "x": 1.0, "y": 0.0 },
                { "x": 1.0, "y": 1.0 },
                { "x": 0.0, "y": 1.0 }
              ],
              "classification_confidence": 0.95,
              "measurement_ids": ["\(fixtureMeasurementID.uuidString)"]
            }
          ]
        }
        """
    }

    private func decodeDTO(
        id: String = "11111111-1111-1111-1111-111111111111",
        annotationURL: String? = nil,
        note: String? = "remote note",
        dimensionsJSON: String?
    ) throws -> PhotoAnnotationDTO {
        var fields = [
            #""id": "\#(id)""#,
            #""project_id": "project-123""#,
            #""company_id": "company-abc""#,
            #""photo_url": "https://example.test/photo.heic""#,
            annotationURL.map { #""annotation_url": "\#($0)""# } ?? #""annotation_url": null"#,
            note.map { #""note": "\#($0)""# } ?? #""note": null"#,
            #""author_id": "user-xyz""#,
            #""created_at": "2026-05-12T12:00:00Z""#,
            #""updated_at": "2026-05-12T12:30:00Z""#,
            #""deleted_at": null"#
        ]

        if let dimensionsJSON {
            fields.append(#""dimensions": \#(dimensionsJSON)"#)
        }

        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder().decode(PhotoAnnotationDTO.self, from: Data(json.utf8))
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([PhotoAnnotation.self, SyncOperation.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
