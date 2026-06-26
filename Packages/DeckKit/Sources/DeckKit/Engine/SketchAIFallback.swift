// OPS/OPS/DeckBuilder/Engine/SketchAIFallback.swift

import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct SketchAIFallback {

    /// JSON structure expected from Claude Vision API response
    public struct AISketchResponse: Codable {
        struct Vertex: Codable {
            let x: Double  // percentage 0-100 of image width
            let y: Double  // percentage 0-100 of image height
        }
        struct Edge: Codable {
            let startVertexIndex: Int
            let endVertexIndex: Int
            let dimensionInches: Double?
            let isHouseEdge: Bool?
            let isStairEdge: Bool?
            let treadCount: Int?
        }
        struct TextAnnotation: Codable {
            let text: String
            let type: String  // "dimension", "stair_count", "client_name", "label"
            let x: Double
            let y: Double
        }

        let vertices: [Vertex]
        let edges: [Edge]
        let annotations: [TextAnnotation]?
        let clientName: String?
    }

    /// Send the sketch image to Claude Vision API for analysis
    /// - Parameters:
    ///   - image: The captured sketch CGImage
    ///   - apiKey: The Anthropic API key (stored in app config or keychain)
    /// - Returns: A SketchScanResult parsed from the AI response
    public static func analyze(image: CGImage, apiKey: String) async throws -> SketchScanResult {
        let imageSize = CGSize(width: image.width, height: image.height)

        // Convert CGImage to base64 JPEG without binding DeckKit to app UI frameworks.
        guard let jpegData = makeJPEGData(from: image, compressionQuality: 0.8) else {
            throw AIFallbackError.imageConversionFailed
        }
        let base64Image = jpegData.base64EncodedString()

        // Build the API request
        let requestBody = buildRequest(base64Image: base64Image)

        // Call Claude Vision API
        let responseData = try await callAPI(requestBody: requestBody, apiKey: apiKey)

        // Parse response
        let aiResponse = try parseResponse(data: responseData)

        // Convert to SketchScanResult
        return buildScanResult(from: aiResponse, image: image, imageSize: imageSize)
    }

    // MARK: - API Request

    private static func buildRequest(base64Image: String) -> [String: Any] {
        [
            "model": "claude-sonnet-4-5-20250514",
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": """
                            Analyze this deck sketch. Return a JSON object with:
                            - "vertices": array of {x, y} positions as percentages (0-100) of image width/height
                            - "edges": array of {startVertexIndex, endVertexIndex, dimensionInches (nullable), isHouseEdge (bool), isStairEdge (bool), treadCount (nullable int)}
                            - "annotations": array of {text, type ("dimension"/"stair_count"/"client_name"/"label"), x, y} for text found in the image
                            - "clientName": string if a client name is detected, null otherwise

                            Return ONLY valid JSON, no markdown or explanation.
                            Vertices should trace the deck outline clockwise from the top-left.
                            Dimensions should be in inches (convert feet to inches: 24' = 288).
                            """
                        ]
                    ]
                ]
            ]
        ]
    }

    private static func makeJPEGData(from image: CGImage, compressionQuality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func callAPI(requestBody: [String: Any], apiKey: String) async throws -> Data {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIFallbackError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIFallbackError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        return data
    }

    // MARK: - Response Parsing

    private static func parseResponse(data: Data) throws -> AISketchResponse {
        // Claude API wraps content in a messages response
        struct APIResponse: Codable {
            struct Content: Codable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        guard let textContent = apiResponse.content.first(where: { $0.type == "text" }),
              let jsonText = textContent.text else {
            throw AIFallbackError.parseError("No text content in response")
        }

        // Strip any markdown code fence if present
        let cleaned = jsonText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw AIFallbackError.parseError("Failed to convert response to data")
        }

        return try JSONDecoder().decode(AISketchResponse.self, from: jsonData)
    }

    // MARK: - Conversion to SketchScanResult

    private static func buildScanResult(
        from response: AISketchResponse,
        image: CGImage,
        imageSize: CGSize
    ) -> SketchScanResult {
        // Convert percentage vertices to image-pixel coordinates
        let pixelVertices: [CGPoint] = response.vertices.map { v in
            CGPoint(
                x: v.x / 100.0 * imageSize.width,
                y: v.y / 100.0 * imageSize.height
            )
        }

        // Build DetectedVertex array
        var detectedVertices: [DetectedVertex] = []
        var vertexIds: [String] = []

        for (i, point) in pixelVertices.enumerated() {
            let id = "ai_v\(i)"
            vertexIds.append(id)
            detectedVertices.append(DetectedVertex(id: id, position: point))
        }

        // Build DetectedLineSegment array and wire up vertex connections
        var detectedSegments: [DetectedLineSegment] = []
        var stairDetections: [(segmentId: String, treadCount: Int)] = []
        var dimensionAssociations: [DimensionAssociation] = []

        for (i, edge) in response.edges.enumerated() {
            guard edge.startVertexIndex >= 0,
                  edge.startVertexIndex < pixelVertices.count,
                  edge.endVertexIndex >= 0,
                  edge.endVertexIndex < pixelVertices.count else { continue }

            let segId = "ai_s\(i)"
            let segment = DetectedLineSegment(
                id: segId,
                startPoint: pixelVertices[edge.startVertexIndex],
                endPoint: pixelVertices[edge.endVertexIndex]
            )
            detectedSegments.append(segment)

            // Wire vertex connections
            detectedVertices[edge.startVertexIndex].connectedSegmentIds.append(segId)
            detectedVertices[edge.endVertexIndex].connectedSegmentIds.append(segId)

            // Dimension association
            if let dim = edge.dimensionInches, dim > 0 {
                let textId = "ai_dim\(i)"
                dimensionAssociations.append(DimensionAssociation(
                    textId: textId,
                    segmentId: segId,
                    dimensionInches: dim,
                    score: 1.0
                ))
            }

            // Stair detection
            if edge.isStairEdge == true, let count = edge.treadCount, count > 0 {
                stairDetections.append((segmentId: segId, treadCount: count))
            }
        }

        // Check if closed polygon
        let isClosed = ContourExtractor.checkClosed(
            vertices: detectedVertices,
            segments: detectedSegments
        )

        // Build recognized texts from annotations
        var recognizedTexts: [RecognizedText] = []
        if let annotations = response.annotations {
            for (i, ann) in annotations.enumerated() {
                let bbox = CGRect(
                    x: ann.x / 100.0 * imageSize.width - 50,
                    y: ann.y / 100.0 * imageSize.height - 15,
                    width: 100,
                    height: 30
                )
                let classification: TextClassification
                switch ann.type {
                case "dimension":
                    let inches = DimensionEngine.parseToInches(ann.text, system: .imperial) ?? 0
                    classification = .dimension(inches: inches)
                case "stair_count":
                    let count = Int(ann.text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
                    classification = .stairCount(count: count)
                case "client_name":
                    classification = .clientName(name: ann.text)
                case "label":
                    classification = .label(text: ann.text.lowercased())
                default:
                    classification = .unknown
                }
                recognizedTexts.append(RecognizedText(
                    id: "ai_text\(i)",
                    text: ann.text,
                    boundingBox: bbox,
                    confidence: 0.9,
                    classification: classification
                ))
            }
        }

        // Calculate scale from dimensions if available
        let scaleResult: ScaleResult?
        if !dimensionAssociations.isEmpty {
            scaleResult = ScaleInference.inferFromAnnotations(
                associations: dimensionAssociations,
                segments: detectedSegments
            )
        } else {
            scaleResult = nil
        }

        // Build grid result (AI path has no grid detection)
        let gridResult = GridDetectionResult(
            hasGrid: false,
            gridSpacingPixels: nil,
            cleanedImage: image,
            originalImage: image,
            imageSize: imageSize
        )

        let contourResult = ContourExtractionResult(
            vertices: detectedVertices,
            segments: detectedSegments,
            isClosed: isClosed,
            stairPatterns: []
        )

        return SketchScanResult(
            sourceImage: image,
            gridResult: gridResult,
            contourResult: contourResult,
            recognizedTexts: recognizedTexts,
            dimensionAssociations: dimensionAssociations,
            scaleResult: scaleResult,
            clientNameCandidate: response.clientName,
            stairDetections: stairDetections
        )
    }

    // MARK: - Errors

    public enum AIFallbackError: LocalizedError {
        case imageConversionFailed
        case networkError(String)
        case apiError(statusCode: Int, message: String)
        case parseError(String)

        public var errorDescription: String? {
            switch self {
            case .imageConversionFailed: return "Failed to convert image for upload"
            case .networkError(let msg): return "Network error: \(msg)"
            case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
            case .parseError(let msg): return "Failed to parse AI response: \(msg)"
            }
        }
    }
}
