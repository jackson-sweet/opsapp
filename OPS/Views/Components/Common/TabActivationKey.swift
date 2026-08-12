//
//  TabActivationKey.swift
//  OPS
//

import Combine
import SwiftUI

/// Whether this view sits inside the tab the operator is currently looking at.
///
/// `MainTabView` keeps every visited tab mounted so a switch never rebuilds the
/// map, refetches a list, or drops scroll position. That trade only holds if
/// hidden tabs stay quiet: work that used to ride `onAppear` — screen-view
/// analytics, freshness refreshes, wizard visit triggers — has to key off this
/// flag instead, and signal-driven recomputes have to defer while it is false
/// and consume a pending flag when it flips true.
///
/// Defaults to `true` so anything mounted outside the tab container — sheets,
/// pushed screens, previews, tests — behaves exactly as it always has.
private struct IsActiveTabKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var isActiveTab: Bool {
        get { self[IsActiveTabKey.self] }
        set { self[IsActiveTabKey.self] = newValue }
    }
}

/// `onReceive` that only fires while its tab is on screen.
///
/// Some broadcasts are answered by more than one tab — `ShowCalendarTaskDetails`
/// is posted by both Home's event carousel and the calendar's day/month grids,
/// and answered by both Home and Schedule. That used to be safe because exactly
/// one tab existed at a time. With every visited tab mounted, an ungated handler
/// would run twice and present the same sheet twice.
private struct ActiveTabReceiveModifier<P: Publisher>: ViewModifier where P.Failure == Never {
    @Environment(\.isActiveTab) private var isActiveTab
    let publisher: P
    let action: (P.Output) -> Void

    func body(content: Content) -> some View {
        content.onReceive(publisher) { output in
            guard isActiveTab else { return }
            action(output)
        }
    }
}

extension View {
    /// Handle `publisher` only while this view's tab is the one on screen.
    func onReceiveWhileActive<P: Publisher>(
        _ publisher: P,
        perform action: @escaping (P.Output) -> Void
    ) -> some View where P.Failure == Never {
        modifier(ActiveTabReceiveModifier(publisher: publisher, action: action))
    }
}

// MARK: - Deliberately ungated
//
// Two classes of listener were audited and left alone on purpose:
//
//   • `AppHeader`'s unread-count refresh. Six mounted headers now answer the
//     same push, but each does one idempotent recount onto shared AppState.
//     Gating it would buy nothing and risk a stale badge. Noted at the site.
//
//   • Wizard listeners on PUSHED screens (ManageTeamView, RoleListView,
//     UserPermissionsListView, PermissionsManagementView, the JobBoard form
//     sheets). Keep-alive means a navigation stack the operator pushed and
//     then tabbed away from stays alive, so those can now hear a wizard step
//     while parked. The reachable case is narrow — a wizard active at the
//     same time as a parked pushed stack — and wizards drive the tab
//     themselves, so gating them risks breaking a live flow for an edge that
//     may not occur. The two wizard listeners that sit in TAB BODIES and
//     genuinely collide (JobBoardProjectListView and ScheduleView, both
//     answering `WizardEvaluatePrerequisites` with different count sets) ARE
//     gated.
