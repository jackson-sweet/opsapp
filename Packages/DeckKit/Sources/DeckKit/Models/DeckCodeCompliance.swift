import CoreGraphics
import Foundation

public enum DeckCodeCheckSettings: String, Codable, Equatable {
    case enabled
    case disabled
}

public struct DeckCodeProfile: Codable, Equatable, Identifiable {
    public let id: String
    public var jurisdiction: DeckJurisdiction
    public var source: DeckCodeProfileSource?
    public var rules: [DeckCodeRule]

    public init(
        id: String,
        jurisdiction: DeckJurisdiction,
        source: DeckCodeProfileSource? = nil,
        rules: [DeckCodeRule]
    ) {
        self.id = id
        self.jurisdiction = jurisdiction
        self.source = source
        self.rules = rules
    }
}

public struct DeckJurisdiction: Codable, Equatable, Identifiable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct DeckCodeRule: Codable, Equatable, Identifiable {
    public let id: String
    public var token: String
    public var scope: DeckCodeRuleScope
    public var metric: DeckCodeMetric
    public var limit: DeckCodeLimit
    public var severity: DeckCodeSeverity
    public var citation: DeckCodeCitation?
    public var annotationToken: DeckCodeAnnotationToken
    public var messageToken: DeckCodeMessageToken

    public init(
        id: String,
        token: String,
        scope: DeckCodeRuleScope,
        metric: DeckCodeMetric,
        limit: DeckCodeLimit,
        severity: DeckCodeSeverity,
        citation: DeckCodeCitation? = nil,
        annotationToken: DeckCodeAnnotationToken,
        messageToken: DeckCodeMessageToken
    ) {
        self.id = id
        self.token = token
        self.scope = scope
        self.metric = metric
        self.limit = limit
        self.severity = severity
        self.citation = citation
        self.annotationToken = annotationToken
        self.messageToken = messageToken
    }
}

public struct DeckCodeRuleScope: Codable, Equatable {
    public var memberRole: FramingRole?

    public init(memberRole: FramingRole? = nil) {
        self.memberRole = memberRole
    }

    public func matches(_ member: FramingMember) -> Bool {
        if let memberRole, member.role != memberRole { return false }
        return true
    }
}

public enum DeckCodeMetric: String, Codable, Equatable {
    case memberSpan
}

public struct DeckCodeLimit: Codable, Equatable {
    public enum Kind: String, Codable, Equatable {
        case maximumInches
    }

    public var kind: Kind
    public var inches: Double

    public static func maximumInches(_ inches: Double) -> DeckCodeLimit {
        DeckCodeLimit(kind: .maximumInches, inches: inches)
    }

    public init(kind: Kind, inches: Double) {
        self.kind = kind
        self.inches = inches
    }
}

public enum DeckCodeSeverity: String, Codable, Equatable {
    case advisory
    case warning
    case violation
}

public struct DeckCodeProfileSource: Codable, Equatable {
    public var profileSourceToken: String

    public init(profileSourceToken: String) {
        self.profileSourceToken = profileSourceToken
    }
}

public struct DeckCodeCitation: Codable, Equatable {
    public var authorityToken: String
    public var sectionToken: String

    public init(authorityToken: String, sectionToken: String) {
        self.authorityToken = authorityToken
        self.sectionToken = sectionToken
    }
}

public struct DeckCodeReport: Codable, Equatable {
    public var profileId: String
    public var jurisdictionId: String
    public var settings: DeckCodeCheckSettings
    public var evaluated: Bool
    public var findings: [DeckCodeFinding]

    public init(
        profileId: String,
        jurisdictionId: String,
        settings: DeckCodeCheckSettings,
        evaluated: Bool,
        findings: [DeckCodeFinding]
    ) {
        self.profileId = profileId
        self.jurisdictionId = jurisdictionId
        self.settings = settings
        self.evaluated = evaluated
        self.findings = findings
    }
}

public struct DeckCodeFinding: Codable, Equatable, Identifiable {
    public let id: String
    public var element: DeckCodeElementReference
    public var jurisdictionId: String
    public var ruleId: String
    public var ruleToken: String
    public var severity: DeckCodeSeverity
    public var citation: DeckCodeCitation?
    public var source: DeckCodeProfileSource?
    public var measurement: DeckCodeMeasurement
    public var annotationToken: DeckCodeAnnotationToken
    public var messageToken: DeckCodeMessageToken
    public var lineAnchor: DeckCodeLineAnchor?

    public init(
        id: String,
        element: DeckCodeElementReference,
        jurisdictionId: String,
        ruleId: String,
        ruleToken: String,
        severity: DeckCodeSeverity,
        citation: DeckCodeCitation? = nil,
        source: DeckCodeProfileSource? = nil,
        measurement: DeckCodeMeasurement,
        annotationToken: DeckCodeAnnotationToken,
        messageToken: DeckCodeMessageToken,
        lineAnchor: DeckCodeLineAnchor? = nil
    ) {
        self.id = id
        self.element = element
        self.jurisdictionId = jurisdictionId
        self.ruleId = ruleId
        self.ruleToken = ruleToken
        self.severity = severity
        self.citation = citation
        self.source = source
        self.measurement = measurement
        self.annotationToken = annotationToken
        self.messageToken = messageToken
        self.lineAnchor = lineAnchor
    }
}

public enum DeckCodeElementKind: String, Codable, Equatable {
    case framingMember
}

public struct DeckCodeElementReference: Codable, Equatable {
    public var kind: DeckCodeElementKind
    public var memberId: String
    public var levelId: String
    public var role: FramingRole

    public init(
        kind: DeckCodeElementKind = .framingMember,
        memberId: String,
        levelId: String,
        role: FramingRole
    ) {
        self.kind = kind
        self.memberId = memberId
        self.levelId = levelId
        self.role = role
    }
}

public struct DeckCodeMeasurement: Codable, Equatable {
    public var metric: DeckCodeMetric
    public var measuredInches: Double
    public var allowedInches: Double

    public init(metric: DeckCodeMetric, measuredInches: Double, allowedInches: Double) {
        self.metric = metric
        self.measuredInches = measuredInches
        self.allowedInches = allowedInches
    }
}

public struct DeckCodeAnnotationToken: RawRepresentable, Codable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct DeckCodeMessageToken: RawRepresentable, Codable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct DeckCodeLineAnchor: Codable, Equatable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}
