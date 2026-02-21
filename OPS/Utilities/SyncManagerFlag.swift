//
//  SyncManagerFlag.swift
//  OPS
//
//  Runtime feature flag for switching between Bubble CentralizedSyncManager
//  and Supabase SupabaseSyncManager during migration testing.
//
//  Toggle at runtime via:
//    UserDefaults.standard.set(true, forKey: "ops_use_supabase_sync")
//
//  Remove this file after the migration is validated and CentralizedSyncManager is deleted.
//

import Foundation

enum SyncManagerFlag {
    /// Returns true if the app should use SupabaseSyncManager instead of CentralizedSyncManager.
    /// Reads from UserDefaults so it can be toggled at runtime during testing.
    static var useSupabase: Bool {
        UserDefaults.standard.bool(forKey: "ops_use_supabase_sync")
    }
}
