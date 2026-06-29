//
//  DimensionsData.swift
//  OPS
//
//  Codable mirror of the `project_photo_annotations.dimensions` jsonb shape.
//
//  Schema reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §4.1
//
//  Key encoding strategy: snake_case to match the Postgres column conventions.
//  worldPoints is authoritative; valueMeters and imagePoints are denormalized
//  caches re-derivable from worldPoints + camera intrinsics.
//

import Foundation

public struct DimensionsData: Codable, Equatable {
    public var schemaVersion: Int
    public var captureMode: CaptureMode
    public var calibration: Calibration
    public var intrinsics: Intrinsics
    public var depthAssetUrl: String?
    public var sidecarMetadataUrl: String?
    public var measurements: [Measurement]
    public var openings: [Opening]

    public init(
        schemaVersion: Int = 1,
        captureMode: CaptureMode,
        calibration: Calibration,
        intrinsics: Intrinsics,
        depthAssetUrl: String? = nil,
        sidecarMetadataUrl: String? = nil,
        measurements: [Measurement] = [],
        openings: [Opening] = []
    ) {
        self.schemaVersion = schemaVersion
        self.captureMode = captureMode
        self.calibration = calibration
        self.intrinsics = intrinsics
        self.depthAssetUrl = depthAssetUrl
        self.sidecarMetadataUrl = sidecarMetadataUrl
        self.measurements = measurements
        self.openings = openings
    }

    // MARK: - Capture mode

    public enum CaptureMode: String, Codable {
        case lidar
        case visual
        case manualScale = "manual_scale"
    }

    // MARK: - Calibration

    public struct Calibration: Codable, Equatable {
        public var method: Method
        public var referenceObject: ReferenceObject?
        public var scaleFactor: Double
        public var estimatedAccuracyMeters: Double
        public var planeNormal: Point3?
        public var planeOffset: Double?

        public init(
            method: Method,
            referenceObject: ReferenceObject? = nil,
            scaleFactor: Double = 1.0,
            estimatedAccuracyMeters: Double,
            planeNormal: Point3? = nil,
            planeOffset: Double? = nil
        ) {
            self.method = method
            self.referenceObject = referenceObject
            self.scaleFactor = scaleFactor
            self.estimatedAccuracyMeters = estimatedAccuracyMeters
            self.planeNormal = planeNormal
            self.planeOffset = planeOffset
        }

        public enum Method: String, Codable {
            case lidar
            case referenceObject = "reference_object"
            case none
        }
        public enum ReferenceObject: String, Codable {
            case creditCard = "credit_card"
            case opsMarker = "ops_marker"
        }
    }

    // MARK: - Camera intrinsics

    public struct Intrinsics: Codable, Equatable {
        public var fx: Double
        public var fy: Double
        public var cx: Double
        public var cy: Double
        public var imageWidth: Int
        public var imageHeight: Int

        public init(fx: Double, fy: Double, cx: Double, cy: Double, imageWidth: Int, imageHeight: Int) {
            self.fx = fx
            self.fy = fy
            self.cx = cx
            self.cy = cy
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
        }
    }

    // MARK: - Geometry primitives

    public struct Point3: Codable, Equatable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x; self.y = y; self.z = z
        }
    }

    public struct Point2: Codable, Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x; self.y = y
        }
    }

    // MARK: - Measurement

    public struct Measurement: Codable, Equatable, Identifiable {
        public var id: UUID
        public var type: MeasurementType
        public var label: String
        public var worldPoints: [Point3]
        public var imagePoints: [Point2]
        public var valueMeters: Double
        public var primaryDisplayUnit: DisplayUnit
        public var labelPlacement: LabelPlacement
        public var source: MeasurementSource

        public init(
            id: UUID = UUID(),
            type: MeasurementType,
            label: String,
            worldPoints: [Point3],
            imagePoints: [Point2],
            valueMeters: Double,
            primaryDisplayUnit: DisplayUnit = .imperialFraction,
            labelPlacement: LabelPlacement,
            source: MeasurementSource
        ) {
            self.id = id
            self.type = type
            self.label = label
            self.worldPoints = worldPoints
            self.imagePoints = imagePoints
            self.valueMeters = valueMeters
            self.primaryDisplayUnit = primaryDisplayUnit
            self.labelPlacement = labelPlacement
            self.source = source
        }

        public enum MeasurementType: String, Codable {
            case linear, angle, area
        }
        public enum DisplayUnit: String, Codable {
            case imperialFraction = "imperial_fraction"
            case decimalFeet = "decimal_feet"
            case metric
        }
        public enum MeasurementSource: String, Codable {
            case auto, manual, edited
        }
        public struct LabelPlacement: Codable, Equatable {
            public var side: Side
            public var leaderLengthPx: Double

            public init(side: Side, leaderLengthPx: Double) {
                self.side = side
                self.leaderLengthPx = leaderLengthPx
            }
            public enum Side: String, Codable { case north, east, south, west }
        }
    }

    // MARK: - Opening (window/door/wall section)

    public struct Opening: Codable, Equatable, Identifiable {
        public var id: UUID
        public var type: OpeningType
        public var boundingPolygon: [Point2]
        public var classificationConfidence: Double
        public var measurementIds: [UUID]

        public init(
            id: UUID = UUID(),
            type: OpeningType,
            boundingPolygon: [Point2],
            classificationConfidence: Double,
            measurementIds: [UUID] = []
        ) {
            self.id = id
            self.type = type
            self.boundingPolygon = boundingPolygon
            self.classificationConfidence = classificationConfidence
            self.measurementIds = measurementIds
        }

        public enum OpeningType: String, Codable {
            case window, door
            case wallSection = "wall_section"
        }
    }
}

// MARK: - JSON coding (snake_case to match Supabase jsonb)

extension DimensionsData {
    public static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
