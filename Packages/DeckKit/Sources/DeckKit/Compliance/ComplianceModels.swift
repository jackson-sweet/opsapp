import Foundation

public enum ComplianceStrings {
    public static let noFailures = "no code failures detected"
    public static let disclaimer = "This is not a guarantee of full code adherence. Have plans reviewed by a licensed engineer in your jurisdiction."
}

public struct ComplianceReport: Codable, Equatable {
    public var mode: ComplianceEngine.Mode
    public var packageEdition: String
    public var generatedAt: Date
    public var findings: [ComplianceFinding]
    public var summaryStatement: String
    public var disclaimer: String

    public init(
        mode: ComplianceEngine.Mode,
        packageEdition: String,
        generatedAt: Date,
        findings: [ComplianceFinding],
        summaryStatement: String,
        disclaimer: String
    ) {
        self.mode = mode
        self.packageEdition = packageEdition
        self.generatedAt = generatedAt
        self.findings = findings
        self.summaryStatement = summaryStatement
        self.disclaimer = disclaimer
    }
}

public struct ComplianceFinding: Codable, Equatable, Identifiable {
    public let id: String
    public var item: String
    public var severity: Severity
    public var currentValue: String?
    public var targetValue: String?
    public var codeSection: String
    public var fix: String?
    public var confidence: Confidence
    public var evidence: Evidence?
    public var source: FindingSource

    public init(
        id: String,
        item: String,
        severity: Severity,
        currentValue: String?,
        targetValue: String?,
        codeSection: String,
        fix: String?,
        confidence: Confidence,
        evidence: Evidence?,
        source: FindingSource
    ) {
        self.id = id
        self.item = item
        self.severity = severity
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.codeSection = codeSection
        self.fix = fix
        self.confidence = confidence
        self.evidence = evidence
        self.source = source
    }
}

public enum Severity: String, Codable {
    case safetyHazard
    case marginal
    case minor
    case notAssessable
}

public enum Confidence: String, Codable {
    case high
    case medium
    case low
}

public enum FindingSource: String, Codable {
    case measured
    case userEntered
    case notAssessable
}

public struct Evidence: Codable, Equatable {
    public var photoURL: URL?
    public var sceneRef: String?

    public init(photoURL: URL? = nil, sceneRef: String? = nil) {
        self.photoURL = photoURL
        self.sceneRef = sceneRef
    }
}
