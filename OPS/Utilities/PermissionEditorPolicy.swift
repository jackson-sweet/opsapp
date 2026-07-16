//
//  PermissionEditorPolicy.swift
//  OPS
//
//  Canonical, network-independent contract for editing role permissions.
//  Keep this registry aligned with private.lead_permission_editor_registry.
//

import Foundation

enum PermissionLevel: String, CaseIterable, Codable, Identifiable {
    case off
    case own
    case assigned
    case all

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }

    fileprivate var rank: Int {
        switch self {
        case .off: 0
        case .own, .assigned: 1
        case .all: 2
        }
    }
}

struct PermissionDefinition: Identifiable, Equatable {
    let id: String
    let label: String
    let category: String
    let scopes: Set<PermissionLevel>
    let hiddenFromEditor: Bool

    var allowedLevels: [PermissionLevel] {
        PermissionLevel.allCases.filter { $0 == .off || scopes.contains($0) }
    }
}

enum PermissionRegistry {
    private static func permission(
        _ id: String,
        _ label: String,
        _ category: String,
        _ scopes: Set<PermissionLevel>,
        hidden: Bool = false
    ) -> PermissionDefinition {
        PermissionDefinition(
            id: id,
            label: label,
            category: category,
            scopes: scopes,
            hiddenFromEditor: hidden
        )
    }

    // This is the product registry. The two hidden compatibility bits remain
    // readable in snapshots but are excluded from every canonical mutation.
    static let all: [PermissionDefinition] = [
        permission("projects.view", "View projects", "Projects", [.all, .assigned]),
        permission("projects.create", "Create projects", "Projects", [.all]),
        permission("projects.edit", "Edit projects", "Projects", [.all, .assigned]),
        permission("projects.delete", "Delete projects", "Projects", [.all]),
        permission("projects.archive", "Archive projects", "Projects", [.all]),
        permission("projects.assign_team", "Assign team members", "Projects", [.all]),
        permission("projects.manage_views", "Manage shared project views", "Projects", [.all]),
        permission("projects.view_financials", "View project financials", "Projects", [.all]),

        permission("tasks.view", "View tasks", "Tasks", [.all, .assigned]),
        permission("tasks.create", "Create tasks", "Tasks", [.all]),
        permission("tasks.edit", "Edit tasks", "Tasks", [.all, .assigned]),
        permission("tasks.delete", "Delete tasks", "Tasks", [.all]),
        permission("tasks.assign", "Assign tasks", "Tasks", [.all]),
        permission("tasks.change_status", "Change task status", "Tasks", [.all, .assigned]),

        permission("clients.view", "View clients", "Clients", [.all, .assigned]),
        permission("clients.create", "Create clients", "Clients", [.all]),
        permission("clients.edit", "Edit clients", "Clients", [.all]),
        permission("clients.delete", "Delete clients", "Clients", [.all]),

        permission("calendar.view", "View calendar", "Calendar", [.all, .own]),
        permission("calendar.create", "Create events", "Calendar", [.all]),
        permission("calendar.edit", "Edit events", "Calendar", [.all, .own]),
        permission("calendar.delete", "Delete events", "Calendar", [.all]),

        permission("job_board.view", "View job board", "Job Board", [.all, .assigned]),
        permission("job_board.manage_sections", "Manage board sections", "Job Board", [.all]),

        permission("deck_builder.view", "View deck designs", "Deck Builder", [.all, .assigned]),
        permission("deck_builder.create", "Create deck designs", "Deck Builder", [.all, .assigned]),
        permission("deck_builder.edit", "Edit deck designs", "Deck Builder", [.all, .assigned]),

        permission("estimates.view", "View estimates", "Estimates", [.all, .assigned]),
        permission("estimates.create", "Create estimates", "Estimates", [.all]),
        permission("estimates.edit", "Edit estimates", "Estimates", [.all, .own]),
        permission("estimates.delete", "Delete estimates", "Estimates", [.all]),
        permission("estimates.send", "Send estimates", "Estimates", [.all]),
        permission("estimates.convert", "Convert to invoice", "Estimates", [.all]),

        permission("invoices.view", "View invoices", "Invoices", [.all, .assigned]),
        permission("invoices.create", "Create invoices", "Invoices", [.all]),
        permission("invoices.edit", "Edit invoices", "Invoices", [.all]),
        permission("invoices.delete", "Delete invoices", "Invoices", [.all]),
        permission("invoices.send", "Send invoices", "Invoices", [.all]),
        permission("invoices.record_payment", "Record payments", "Invoices", [.all]),
        permission("invoices.void", "Void invoices", "Invoices", [.all]),

        permission("pipeline.create", "Create leads", "Pipeline", [.all]),
        permission("pipeline.view", "View leads", "Pipeline", [.all, .assigned]),
        permission("pipeline.edit", "Edit leads", "Pipeline", [.all, .assigned]),
        permission("pipeline.assign", "Assign leads", "Pipeline", [.all, .assigned]),
        permission("pipeline.convert", "Convert leads", "Pipeline", [.all, .assigned]),
        permission("pipeline.manage", "Manage opportunities", "Pipeline", [.all, .own], hidden: true),
        permission("pipeline.configure_stages", "Configure stages", "Pipeline", [.all]),
        permission("pipeline.manage_views", "Manage shared pipeline views", "Pipeline", [.all]),

        permission("products.view", "View products", "Products", [.all]),
        permission("products.manage", "Manage products", "Products", [.all]),

        permission("catalog.view", "View catalog", "Catalog", [.all]),
        permission("catalog.manage", "Manage catalog", "Catalog", [.all]),
        permission("catalog.import", "Import catalog", "Catalog", [.all]),
        permission("catalog.stock.adjust", "Adjust stock", "Catalog", [.all]),
        permission("catalog.products.view", "View catalog products", "Catalog", [.all]),
        permission("catalog.products.manage", "Manage catalog products", "Catalog", [.all]),
        permission("catalog.orders.view", "View purchase orders", "Catalog", [.all]),
        permission("catalog.orders.manage", "Manage purchase orders", "Catalog", [.all]),
        permission("catalog.run_setup", "Run catalog setup", "Catalog", [.all]),
        permission("inventory.manage", "Manage inventory", "Catalog", [.all]),

        permission("expenses.view", "View expenses", "Expenses", [.all, .own]),
        permission("expenses.create", "Create expenses", "Expenses", [.all]),
        permission("expenses.edit", "Edit expenses", "Expenses", [.all, .own]),
        permission("expenses.delete", "Delete expenses", "Expenses", [.all, .own]),
        permission("expenses.approve", "Approve expenses", "Expenses", [.all, .assigned]),
        permission("expenses.configure", "Configure expense settings", "Expenses", [.all]),

        permission("accounting.view", "View accounting", "Accounting", [.all]),
        permission("accounting.manage_connections", "Manage integrations", "Accounting", [.all]),
        permission("finances.view", "View financial summaries", "Financial Summaries", [.all]),

        permission("photos.view", "View photos", "Photos", [.all, .assigned]),
        permission("photos.upload", "Upload photos", "Photos", [.all]),
        permission("photos.annotate", "Annotate photos", "Photos", [.all]),
        permission("photos.delete", "Delete photos", "Photos", [.all, .own]),

        permission("documents.view", "View documents", "Documents", [.all]),
        permission("documents.manage_templates", "Manage templates", "Documents", [.all]),

        permission("team.view", "View team", "Team", [.all]),
        permission("team.manage", "Manage team members", "Team", [.all]),
        permission("team.assign_roles", "Assign roles", "Team", [.all]),
        permission("time_off.approve", "Approve time off", "Time Off", [.all, .assigned]),
        permission("profile.edit", "Edit own profile", "Profile", [.own]),

        permission("map.view", "View map", "Map", [.all]),
        permission("map.view_crew_locations", "View crew locations", "Map", [.all]),
        permission("notifications.view", "View notifications", "Notifications", [.own]),
        permission("notifications.manage_preferences", "Manage preferences", "Notifications", [.own]),

        permission("settings.company", "Company settings", "Settings", [.all]),
        permission("settings.billing", "Billing settings", "Settings", [.all]),
        permission("settings.integrations", "Integration settings", "Settings", [.all]),
        permission("settings.preferences", "Personal preferences", "Settings", [.all]),

        permission("email.connect", "Connect email accounts", "Email", [.all]),
        permission("email.view", "View email activity", "Email", [.all, .own]),
        permission("email.manage", "Manage email integration", "Email", [.all]),
        permission("email.configure_ai", "Configure intelligent features", "Email", [.all]),

        permission("inbox.view", "View inbox", "Inbox", [.all, .assigned, .own]),
        permission("inbox.view_company", "View all company mail", "Inbox", [.all], hidden: true),
        permission("inbox.archive", "Archive threads", "Inbox", [.all]),
        permission("inbox.snooze", "Snooze threads", "Inbox", [.all]),
        permission("inbox.categorize", "Recategorize threads", "Inbox", [.all]),
        permission("inbox.send", "Send and reply", "Inbox", [.all, .assigned]),
        permission("inbox.configure_phase_c", "Configure email automation", "Inbox", [.all]),

        permission("portal.view", "View portal", "Portal", [.all]),
        permission("portal.manage_branding", "Manage branding", "Portal", [.all]),
        permission("reports.view", "View reports", "Reports", [.all]),
    ]

    static let editable = all.filter { !$0.hiddenFromEditor }

    static var categories: [String] {
        var seen: Set<String> = []
        return editable.compactMap { definition in
            seen.insert(definition.category).inserted ? definition.category : nil
        }
    }

    static func permissions(for category: String) -> [PermissionDefinition] {
        editable.filter { $0.category == category }
    }

    static func definition(for permission: String) -> PermissionDefinition? {
        all.first { $0.id == permission }
    }

    static func displayName(for roleName: String) -> String {
        switch roleName.lowercased() {
        case "admin": "Admin"
        case "owner": "Owner"
        case "office": "Office"
        case "operator": "Operator"
        case "crew": "Crew"
        case "unassigned": "Unassigned"
        default: roleName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func iconForRole(_ roleName: String) -> String {
        switch roleName.lowercased() {
        case "admin": "shield"
        case "owner": "star"
        case "office": "building.2"
        case "operator": "wrench.adjustable"
        case "crew": "hammer"
        case "unassigned": "questionmark.circle"
        default: "person"
        }
    }

    static let categoryFeatureFlag: [String: String] = [
        "Pipeline": "pipeline",
        "Estimates": "estimates",
        "Invoices": "pipeline",
        "Deck Builder": "deck_builder",
    ]

    static func featureFlag(for category: String) -> String? {
        categoryFeatureFlag[category]
    }

    static func iconForCategory(_ category: String) -> String {
        switch category {
        case "Projects": OPSStyle.Icons.project
        case "Tasks": OPSStyle.Icons.task
        case "Clients": OPSStyle.Icons.subClient
        case "Estimates": OPSStyle.Icons.estimateDoc
        case "Invoices": OPSStyle.Icons.invoiceReceipt
        case "Expenses": OPSStyle.Icons.expense
        case "Pipeline": OPSStyle.Icons.accountingChart
        case "Calendar": OPSStyle.Icons.calendar
        case "Catalog", "Products": "shippingbox.fill"
        case "Team", "Time Off", "Profile": OPSStyle.Icons.crew
        case "Settings": "gearshape.fill"
        case "Job Board": "rectangle.stack.fill"
        case "Deck Builder": "ruler.fill"
        case "Email", "Inbox": "envelope.fill"
        case "Map": "map.fill"
        case "Notifications": "bell.fill"
        case "Photos": "photo.fill"
        case "Documents": "doc.fill"
        default: "lock.fill"
        }
    }
}

enum PermissionEditorPolicy {
    private static let pipelineKeys = [
        "pipeline.create",
        "pipeline.view",
        "pipeline.edit",
        "pipeline.assign",
        "pipeline.convert",
    ]

    static func normalized(_ desired: [String: PermissionLevel]) -> [String: PermissionLevel] {
        var result = desired

        for definition in PermissionRegistry.editable {
            guard let level = result[definition.id], level != .off else { continue }
            if !definition.scopes.contains(level) {
                result[definition.id] = .off
            }
        }

        let view = pipelineScope(result["pipeline.view"])
        if result["pipeline.create"] != nil,
           result["pipeline.create"] != .off,
           view == .off {
            result["pipeline.create"] = .off
        }

        cap("pipeline.edit", to: view, in: &result)
        let edit = pipelineScope(result["pipeline.edit"])
        cap("pipeline.assign", to: edit, in: &result)
        cap("pipeline.convert", to: edit, in: &result)

        return result
    }

    static func applying(
        _ level: PermissionLevel,
        to permission: String,
        in desired: [String: PermissionLevel]
    ) -> [String: PermissionLevel] {
        guard let definition = PermissionRegistry.definition(for: permission),
              !definition.hiddenFromEditor,
              definition.allowedLevels.contains(level) else {
            return desired
        }
        var updated = desired
        updated[permission] = level
        return normalized(updated)
    }

    static func commonLevels(for definitions: [PermissionDefinition]) -> [PermissionLevel] {
        guard var common = definitions.first.map({ Set($0.allowedLevels) }) else { return [] }
        for definition in definitions.dropFirst() {
            common.formIntersection(definition.allowedLevels)
        }
        return PermissionLevel.allCases.filter(common.contains)
    }

    static func desiredLevels(from snapshot: [CanonicalRolePermission]) -> [String: PermissionLevel] {
        var result = Dictionary(
            uniqueKeysWithValues: PermissionRegistry.editable.map { ($0.id, PermissionLevel.off) }
        )
        for row in snapshot {
            guard let definition = PermissionRegistry.definition(for: row.permission),
                  !definition.hiddenFromEditor,
                  let level = PermissionLevel(rawValue: row.scope),
                  definition.scopes.contains(level) else { continue }
            result[row.permission] = level
        }
        return normalized(result)
    }

    private static func pipelineScope(_ level: PermissionLevel?) -> PermissionLevel {
        guard level == .all || level == .assigned else { return .off }
        return level ?? .off
    }

    private static func cap(
        _ permission: String,
        to maximum: PermissionLevel,
        in desired: inout [String: PermissionLevel]
    ) {
        let current = pipelineScope(desired[permission])
        guard current != .off else { return }
        if maximum == .off {
            desired[permission] = .off
        } else if current.rank > maximum.rank {
            desired[permission] = maximum
        }
    }
}

struct CanonicalRolePermission: Codable, Equatable {
    let permission: String
    let scope: String
}

struct DesiredRolePermission: Encodable, Equatable {
    let permission: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case permission, scope
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permission, forKey: .permission)
        if let scope {
            try container.encode(scope, forKey: .scope)
        } else {
            try container.encodeNil(forKey: .scope)
        }
    }
}

struct RolePermissionAssignmentResolution: Codable, Equatable {
    let opportunityId: String
    let expectedAssignedTo: String
    let expectedAssignmentVersion: Int64
    let newAssignedTo: String?

    enum CodingKeys: String, CodingKey {
        case opportunityId = "opportunity_id"
        case expectedAssignedTo = "expected_assigned_to"
        case expectedAssignmentVersion = "expected_assignment_version"
        case newAssignedTo = "new_assigned_to"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opportunityId, forKey: .opportunityId)
        try container.encode(expectedAssignedTo, forKey: .expectedAssignedTo)
        try container.encode(expectedAssignmentVersion, forKey: .expectedAssignmentVersion)
        if let newAssignedTo {
            try container.encode(newAssignedTo, forKey: .newAssignedTo)
        } else {
            try container.encodeNil(forKey: .newAssignedTo)
        }
    }
}

struct RolePermissionMutationRequest: Encodable, Equatable {
    let expectedPermissions: [CanonicalRolePermission]
    let newPermissions: [DesiredRolePermission]
    let assignmentResolutions: [RolePermissionAssignmentResolution]

    init(
        expectedPermissions: [CanonicalRolePermission],
        desiredLevels: [String: PermissionLevel],
        assignmentResolutions: [RolePermissionAssignmentResolution]
    ) throws {
        let expected = expectedPermissions.sorted { $0.permission < $1.permission }
        guard Set(expected.map(\.permission)).count == expected.count,
              expected.allSatisfy({ !$0.permission.isEmpty && !$0.scope.isEmpty }) else {
            throw PermissionMutationContractError.invalidExpectedSnapshot
        }

        let normalized = PermissionEditorPolicy.normalized(desiredLevels)
        let desired = PermissionRegistry.editable
            .map { definition -> DesiredRolePermission in
                let level = normalized[definition.id] ?? .off
                let scope = level == .off ? nil : level.rawValue
                return DesiredRolePermission(permission: definition.id, scope: scope)
            }
            .sorted { $0.permission < $1.permission }

        guard desired.count == PermissionRegistry.editable.count,
              Set(desired.map(\.permission)).count == desired.count else {
            throw PermissionMutationContractError.incompleteEditorRegistry
        }
        guard assignmentResolutions.allSatisfy({ $0.expectedAssignmentVersion >= 0 }) else {
            throw PermissionMutationContractError.invalidAssignmentVersion
        }
        guard Set(assignmentResolutions.map(\.opportunityId)).count == assignmentResolutions.count,
              assignmentResolutions.allSatisfy({
                  !$0.opportunityId.isEmpty
                      && !$0.expectedAssignedTo.isEmpty
                      && $0.newAssignedTo != $0.expectedAssignedTo
              }) else {
            throw PermissionMutationContractError.invalidAssignmentResolution
        }

        self.expectedPermissions = expected
        self.newPermissions = desired
        self.assignmentResolutions = assignmentResolutions.sorted {
            $0.opportunityId < $1.opportunityId
        }
    }
}

enum PermissionMutationContractError: LocalizedError {
    case invalidExpectedSnapshot
    case incompleteEditorRegistry
    case invalidAssignmentVersion
    case invalidAssignmentResolution

    var errorDescription: String? {
        switch self {
        case .invalidExpectedSnapshot: "Permission snapshot is invalid. Refresh and try again."
        case .incompleteEditorRegistry: "Permission options are out of date. Update OPS and try again."
        case .invalidAssignmentVersion: "Lead assignment changed. Refresh and try again."
        case .invalidAssignmentResolution: "Lead responsibility choices are invalid. Review and try again."
        }
    }
}

struct RolePermissionMutationSuccess: Decodable, Equatable {
    let ok: Bool
    let roleId: String
    let permissions: [CanonicalRolePermission]
    let resolvedAssignments: Int

    enum CodingKeys: String, CodingKey {
        case ok, roleId, permissions, resolvedAssignments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        guard ok else {
            throw DecodingError.dataCorruptedError(
                forKey: .ok,
                in: container,
                debugDescription: "Permission mutation did not commit"
            )
        }
        roleId = try container.decode(String.self, forKey: .roleId)
        permissions = try container.decode([CanonicalRolePermission].self, forKey: .permissions)
        resolvedAssignments = try container.decode(Int.self, forKey: .resolvedAssignments)
    }
}

struct RolePermissionStrandedLead: Decodable, Identifiable, Equatable {
    let opportunityId: String
    let title: String
    let assignedTo: String
    let assignmentVersion: Int64

    var id: String { opportunityId }

    enum CodingKeys: String, CodingKey {
        case opportunityId = "opportunity_id"
        case title
        case assignedTo = "assigned_to"
        case assignmentVersion = "assignment_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opportunityId = try container.decode(String.self, forKey: .opportunityId)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        assignedTo = try container.decode(String.self, forKey: .assignedTo)
        assignmentVersion = try container.decode(Int64.self, forKey: .assignmentVersion)
    }
}

struct RolePermissionEligibleAssignee: Decodable, Identifiable, Equatable {
    let id: String
    let firstName: String
    let lastName: String
    let profileImageURL: String?
    let userColor: String?
    let role: String

    var displayName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImageURL = "profile_image_url"
        case userColor = "user_color"
        case role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
        userColor = try container.decodeIfPresent(String.self, forKey: .userColor)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
    }
}

struct RolePermissionMutationConflict: Decodable, Identifiable, Equatable {
    let code: String
    let strandedCount: Int
    let stranded: [RolePermissionStrandedLead]
    let eligibleAssignees: [RolePermissionEligibleAssignee]

    var id: String {
        stranded.map(\.opportunityId).joined(separator: ":")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        strandedCount = try container.decode(Int.self, forKey: .strandedCount)
        stranded = try container.decode([RolePermissionStrandedLead].self, forKey: .stranded)
        eligibleAssignees = try container.decode(
            [RolePermissionEligibleAssignee].self,
            forKey: .eligibleAssignees
        )
        guard code == "assignment_resolution_required",
              strandedCount > 0,
              stranded.count == strandedCount,
              stranded.allSatisfy({
                  !$0.opportunityId.isEmpty
                      && !$0.assignedTo.isEmpty
                      && $0.assignmentVersion >= 0
              }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stranded,
                in: container,
                debugDescription: "Assignment resolution conflict is incomplete"
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case code, strandedCount, stranded, eligibleAssignees
    }
}

struct RolePermissionSnapshotConflict: Decodable, Equatable {
    let code: String
    let currentPermissions: [CanonicalRolePermission]
}

struct PermissionAssignmentResolutionConflict: Decodable, Equatable {
    let code: String
    let opportunityId: String?
    let assignedTo: String?
    let assignmentVersion: Int64?

    enum CodingKeys: String, CodingKey {
        case code
        case opportunityId = "opportunity_id"
        case assignedTo = "assigned_to"
        case assignmentVersion = "assignment_version"
    }
}

struct CanonicalUserPermissionOverride: Codable, Equatable {
    let permission: String
    let scope: String?
    let granted: Bool

    enum CodingKeys: String, CodingKey {
        case permission, scope, granted
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(permission, forKey: .permission)
        if let scope {
            try container.encode(scope, forKey: .scope)
        } else {
            try container.encodeNil(forKey: .scope)
        }
        try container.encode(granted, forKey: .granted)
    }
}

struct UserPermissionOverrideMutationRequest: Encodable, Equatable {
    let expectedOverrides: [CanonicalUserPermissionOverride]
    let set: [CanonicalUserPermissionOverride]
    let clear: [String]
    let assignmentResolutions: [RolePermissionAssignmentResolution]

    init(
        expectedOverrides: [CanonicalUserPermissionOverride],
        roleBaseline: [String: PermissionLevel],
        desiredLevels: [String: PermissionLevel],
        assignmentResolutions: [RolePermissionAssignmentResolution]
    ) throws {
        let expected = expectedOverrides.sorted { $0.permission < $1.permission }
        guard Set(expected.map(\.permission)).count == expected.count,
              expected.allSatisfy({ !$0.permission.isEmpty }) else {
            throw PermissionMutationContractError.invalidExpectedSnapshot
        }

        let normalized = PermissionEditorPolicy.normalized(desiredLevels)
        let expectedByPermission = Dictionary(
            uniqueKeysWithValues: expected.map { ($0.permission, $0) }
        )
        var rowsToSet: [CanonicalUserPermissionOverride] = []
        var rowsToClear: [String] = []

        for definition in PermissionRegistry.editable {
            let baseline = roleBaseline[definition.id] ?? .off
            let desired = normalized[definition.id] ?? .off
            if desired == baseline {
                if expectedByPermission[definition.id] != nil {
                    rowsToClear.append(definition.id)
                }
                continue
            }

            let row = CanonicalUserPermissionOverride(
                permission: definition.id,
                scope: desired == .off ? nil : desired.rawValue,
                granted: desired != .off
            )
            if expectedByPermission[definition.id] != row {
                rowsToSet.append(row)
            }
        }

        guard Set(assignmentResolutions.map(\.opportunityId)).count == assignmentResolutions.count,
              assignmentResolutions.allSatisfy({
                  !$0.opportunityId.isEmpty
                      && !$0.expectedAssignedTo.isEmpty
                      && $0.expectedAssignmentVersion >= 0
                      && $0.newAssignedTo != $0.expectedAssignedTo
              }) else {
            throw PermissionMutationContractError.invalidAssignmentResolution
        }

        self.expectedOverrides = expected
        self.set = rowsToSet.sorted { $0.permission < $1.permission }
        self.clear = rowsToClear.sorted()
        self.assignmentResolutions = assignmentResolutions.sorted {
            $0.opportunityId < $1.opportunityId
        }
    }
}

struct UserPermissionOverrideMutationSuccess: Decodable, Equatable {
    let ok: Bool
    let userId: String
    let overrides: [CanonicalUserPermissionOverride]
    let resolvedAssignments: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        guard ok else {
            throw DecodingError.dataCorruptedError(
                forKey: .ok,
                in: container,
                debugDescription: "Override mutation did not commit"
            )
        }
        userId = try container.decode(String.self, forKey: .userId)
        overrides = try container.decode(
            [CanonicalUserPermissionOverride].self,
            forKey: .overrides
        )
        resolvedAssignments = try container.decode(Int.self, forKey: .resolvedAssignments)
    }

    enum CodingKeys: String, CodingKey {
        case ok, userId, overrides, resolvedAssignments
    }
}

struct UserPermissionOverrideSnapshotConflict: Decodable, Equatable {
    let code: String
    let currentOverrides: [CanonicalUserPermissionOverride]
}

struct UserRoleMutationRequest: Encodable, Equatable {
    let expectedRoleId: String?
    let newRoleId: String?
    let assignmentResolutions: [RolePermissionAssignmentResolution]

    enum CodingKeys: String, CodingKey {
        case expectedRoleId, newRoleId, assignmentResolutions
    }

    init(
        expectedRoleId: String?,
        newRoleId: String?,
        assignmentResolutions: [RolePermissionAssignmentResolution]
    ) throws {
        guard Set(assignmentResolutions.map(\.opportunityId)).count == assignmentResolutions.count,
              assignmentResolutions.allSatisfy({
                  !$0.opportunityId.isEmpty
                      && !$0.expectedAssignedTo.isEmpty
                      && $0.expectedAssignmentVersion >= 0
                      && $0.newAssignedTo != $0.expectedAssignedTo
              }) else {
            throw PermissionMutationContractError.invalidAssignmentResolution
        }
        self.expectedRoleId = expectedRoleId
        self.newRoleId = newRoleId
        self.assignmentResolutions = assignmentResolutions.sorted {
            $0.opportunityId < $1.opportunityId
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let expectedRoleId {
            try container.encode(expectedRoleId, forKey: .expectedRoleId)
        } else {
            try container.encodeNil(forKey: .expectedRoleId)
        }
        if let newRoleId {
            try container.encode(newRoleId, forKey: .newRoleId)
        } else {
            try container.encodeNil(forKey: .newRoleId)
        }
        try container.encode(assignmentResolutions, forKey: .assignmentResolutions)
    }
}

struct UserRoleMutationSuccess: Decodable, Equatable {
    let ok: Bool
    let userId: String
    let roleId: String?
    let legacyRole: String
    let resolvedAssignments: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        guard ok, container.contains(.roleId) else {
            throw DecodingError.dataCorruptedError(
                forKey: .ok,
                in: container,
                debugDescription: "Role mutation did not return an authoritative snapshot"
            )
        }
        userId = try container.decode(String.self, forKey: .userId)
        roleId = try container.decodeIfPresent(String.self, forKey: .roleId)
        legacyRole = try container.decode(String.self, forKey: .legacyRole)
        resolvedAssignments = try container.decode(Int.self, forKey: .resolvedAssignments)
    }

    enum CodingKeys: String, CodingKey {
        case ok, userId, roleId, legacyRole, resolvedAssignments
    }
}

struct UserRoleSnapshotConflict: Decodable, Equatable {
    let code: String
    let currentRoleId: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        guard container.contains(.currentRoleId) else {
            throw DecodingError.keyNotFound(
                CodingKeys.currentRoleId,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing current role snapshot")
            )
        }
        currentRoleId = try container.decodeIfPresent(String.self, forKey: .currentRoleId)
    }

    enum CodingKeys: String, CodingKey {
        case code, currentRoleId
    }
}
