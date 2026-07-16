//
//  LeadAccessPolicy.swift
//  OPS
//
//  Pure, row-specific mirror of the canonical Supabase opportunity scope
//  contract. It intentionally knows only the current user, effective grants,
//  explicit grant/revoke keys, and the opportunity's assigned_to value.
//

import Foundation

enum LeadAction: String, CaseIterable {
    case create
    case view
    case edit
    case assign
    case convert

    var permissionKey: String { "pipeline.\(rawValue)" }
}

enum LeadAccessScope: String, Equatable {
    case all
    case assigned
}

struct LeadAccessPolicy {
    static let granularPermissionKeys = Set(
        LeadAction.allCases.map(\.permissionKey)
    )

    private let currentUserId: String?
    private let isAdmin: Bool
    private let permissions: [String: String]
    private let explicitPermissionKeys: Set<String>

    init(
        currentUserId: String?,
        isAdmin: Bool = false,
        permissions: [String: String],
        explicitPermissionKeys: Set<String>
    ) {
        self.currentUserId = currentUserId?.lowercased()
        self.isAdmin = isAdmin
        self.permissions = permissions
        self.explicitPermissionKeys = explicitPermissionKeys
    }

    var canCreate: Bool {
        scope(for: .create) == .all
    }

    func can(_ action: LeadAction, assignedTo: String?) -> Bool {
        if action == .create { return canCreate }
        guard let scope = scope(for: action) else { return false }
        switch scope {
        case .all:
            return true
        case .assigned:
            guard let currentUserId,
                  let assignedTo = assignedTo?.lowercased() else {
                return false
            }
            return assignedTo == currentUserId
        }
    }

    func scope(for action: LeadAction) -> LeadAccessScope? {
        if isAdmin { return .all }

        switch action {
        case .view:
            return rawScope(for: .view)

        case .create:
            guard rawScope(for: .create) == .all,
                  scope(for: .view) != nil else {
                return nil
            }
            return .all

        case .edit:
            return leastPermissive(
                rawScope(for: .edit),
                scope(for: .view)
            )

        case .assign:
            return leastPermissive(
                rawScope(for: .assign),
                scope(for: .edit)
            )

        case .convert:
            return leastPermissive(
                rawScope(for: .convert),
                scope(for: .edit)
            )
        }
    }

    private func rawScope(for action: LeadAction) -> LeadAccessScope? {
        let permissionKey = action.permissionKey

        if let rawScope = permissions[permissionKey] {
            return LeadAccessScope(rawValue: rawScope)
        }

        // An explicit granular row or override is authoritative even when its
        // effective grant is absent (an explicit revoke). Legacy manage cannot
        // widen it.
        if explicitPermissionKeys.contains(permissionKey) {
            return nil
        }

        // Compatibility exists only for roles that predate every granular row.
        // The legacy permission was all-scope management; malformed/assigned
        // legacy values fail closed.
        if permissions["pipeline.manage"] == LeadAccessScope.all.rawValue {
            return .all
        }

        return nil
    }

    private func leastPermissive(
        _ left: LeadAccessScope?,
        _ right: LeadAccessScope?
    ) -> LeadAccessScope? {
        guard let left, let right else { return nil }
        if left == .assigned || right == .assigned { return .assigned }
        return .all
    }
}
