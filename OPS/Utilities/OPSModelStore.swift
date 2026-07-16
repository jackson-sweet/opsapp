//
//  OPSModelStore.swift
//  OPS
//
//  Single configuration contract for the app's persistent SwiftData store.
//

import SwiftData

enum OPSModelStore {
    static func appGroupIdentifier(isStoredInMemoryOnly: Bool) -> String? {
        isStoredInMemoryOnly ? nil : AppGroupConfig.identifier
    }

    static func configuration(
        schema: Schema,
        isStoredInMemoryOnly: Bool
    ) -> ModelConfiguration {
        let groupContainer: ModelConfiguration.GroupContainer
        if let identifier = appGroupIdentifier(isStoredInMemoryOnly: isStoredInMemoryOnly) {
            groupContainer = .identifier(identifier)
        } else {
            groupContainer = .none
        }

        return ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            allowsSave: true,
            groupContainer: groupContainer
        )
    }
}
