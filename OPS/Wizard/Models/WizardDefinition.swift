//
//  WizardDefinition.swift
//  OPS
//
//  Protocols and enums defining the wizard system's core types.
//

import SwiftUI

// MARK: - Wizard Status

/// Persistence status for a wizard
enum WizardStatus: String, Codable, CaseIterable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed = "completed"
    case dismissed = "dismissed"
}

// MARK: - Wizard Trigger Type

/// How a wizard is activated
enum WizardTriggerType: String, Codable {
    case sequenced    // Prompted proactively after prior wizard completes
    case contextual   // Triggered on first encounter with a feature area
}

// MARK: - Wizard Access Tier

/// Role-based access tiers for wizard visibility
enum WizardAccessTier: String, Codable {
    case field   // .crew
    case office  // .office, .operator
    case admin   // .admin, .owner

    /// Whether a given UserRole can access this tier
    static func tier(for role: UserRole) -> WizardAccessTier {
        switch role {
        case .admin, .owner:
            return .admin
        case .office, .operator:
            return .office
        case .crew, .unassigned:
            return .field
        }
    }

    /// Whether this tier can see wizards at the given minimum tier
    func canAccess(minimumTier: WizardAccessTier) -> Bool {
        let hierarchy: [WizardAccessTier] = [.field, .office, .admin]
        guard let selfIndex = hierarchy.firstIndex(of: self),
              let minIndex = hierarchy.firstIndex(of: minimumTier) else { return false }
        return selfIndex >= minIndex
    }
}

// MARK: - Wizard Step Definition

/// A single step within a wizard
struct WizardStepDefinition: Identifiable {
    let id: String                          // e.g., "create_client"
    let instruction: String                 // e.g., "CREATE A CLIENT"
    let description: String?                // Optional secondary text
    let targetScreen: String?               // Which screen this step occurs on (for navigation hints)
    let canSkip: Bool                       // Whether user can skip this step
    let completionNotification: String?     // NotificationCenter name to observe for auto-advance

    init(
        id: String,
        instruction: String,
        description: String? = nil,
        targetScreen: String? = nil,
        canSkip: Bool = true,
        completionNotification: String? = nil
    ) {
        self.id = id
        self.instruction = instruction
        self.description = description
        self.targetScreen = targetScreen
        self.canSkip = canSkip
        self.completionNotification = completionNotification
    }
}

// MARK: - Wizard Definition Protocol

/// Protocol that all wizard definitions conform to
protocol WizardDefinitionProtocol {
    /// Unique identifier for this wizard (e.g., "project_lifecycle")
    var wizardId: String { get }

    /// Display name shown in UI (e.g., "PROJECT LIFECYCLE")
    var displayName: String { get }

    /// Description shown in prompt overlay
    var displayDescription: String { get }

    /// Bullet points shown in prompt overlay
    var bulletPoints: [String] { get }

    /// SF Symbol icon name
    var iconName: String { get }

    /// How this wizard is triggered
    var triggerType: WizardTriggerType { get }

    /// Minimum access tier required to see this wizard
    var minimumTier: WizardAccessTier { get }

    /// Optional permission key required (e.g., "pipeline.view")
    var requiredPermission: String? { get }

    /// Banner text shown when triggered
    var bannerText: String { get }

    /// Estimated minutes to complete (shown in banner and prompt overlay)
    var estimatedMinutes: Int { get }

    /// Ordered list of steps
    var steps: [WizardStepDefinition] { get }
}

extension WizardDefinitionProtocol {
    var requiredPermission: String? { nil }
    var totalSteps: Int { steps.count }
}
