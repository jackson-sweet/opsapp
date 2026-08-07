//
//  BugReportTriggerCoordinator.swift
//  OPS
//
//  One guarded boundary for every user-initiated bug-report trigger.
//

import Foundation

@MainActor
final class BugReportTriggerCoordinator {
    static let shared = BugReportTriggerCoordinator()

    enum Source: String, Equatable {
        case shake
        case settings
    }

    struct GuardState: Equatable {
        let isAuthenticated: Bool
        let isTutorialActive: Bool
        let isPresenterActive: Bool
    }

    enum Rejection: Equatable {
        case debounced
        case tutorialActive
        case presenterActive
        case unauthenticated
    }

    enum Outcome: Equatable {
        case accepted(Source)
        case rejected(Rejection)
    }

    private let debounceInterval: TimeInterval
    private let now: () -> Date
    private var lastAcceptedTriggerAt: Date?

    init(
        debounceInterval: TimeInterval = 1.5,
        now: @escaping () -> Date = Date.init
    ) {
        self.debounceInterval = debounceInterval
        self.now = now
    }

    /// Production entry point. Both shake and the visible Settings action use
    /// this method so their eligibility and capture ordering cannot drift.
    @discardableResult
    func trigger(
        source: Source,
        appState: AppState,
        dataController: DataController
    ) -> Outcome {
        let outcome = trigger(
            source: source,
            state: GuardState(
                isAuthenticated: dataController.isAuthenticated,
                isTutorialActive: appState.shouldRestartTutorial,
                isPresenterActive: BugReportPresenter.shared.isPresenting
            ),
            captureScreenshot: {
                BugReportCaptureService.shared.captureScreenshot()
            },
            presentOverlay: { screenshot in
                BugReportPresenter.shared.present(
                    screenshot: screenshot,
                    appState: appState,
                    dataController: dataController
                )
            }
        )

        if case let .accepted(acceptedSource) = outcome {
            DebugLogger.shared.log(
                "Bug report triggered via \(acceptedSource.rawValue)",
                level: .info,
                category: "BugReport"
            )
        }

        return outcome
    }

    /// Deterministic core used by production and focused tests.
    ///
    /// The coordinator intentionally never dismisses a sheet or resigns the
    /// keyboard. `BugReportPresenter` owns a dedicated overlay window, so the
    /// live interface remains untouched while it is captured and covered.
    @discardableResult
    func trigger<Snapshot>(
        source: Source,
        state: GuardState,
        captureScreenshot: () -> Snapshot?,
        presentOverlay: (Snapshot?) -> Void
    ) -> Outcome {
        let triggerTime = now()
        if let lastAcceptedTriggerAt,
           triggerTime.timeIntervalSince(lastAcceptedTriggerAt) <= debounceInterval {
            return .rejected(.debounced)
        }

        guard !state.isTutorialActive else {
            return .rejected(.tutorialActive)
        }

        guard !state.isPresenterActive else {
            return .rejected(.presenterActive)
        }

        guard state.isAuthenticated else {
            return .rejected(.unauthenticated)
        }

        // Match the established shake behavior: consume the debounce window
        // once a trigger is accepted, then capture the live screen before the
        // overlay window becomes key.
        lastAcceptedTriggerAt = triggerTime
        let screenshot = captureScreenshot()
        presentOverlay(screenshot)

        return .accepted(source)
    }
}
