//
//  CallStateObserver.swift
//  OPS
//
//  Around-call lead capture (iOS feature 154cb8a3). Thin wrapper over CallKit's
//  CXCallObserver — the only call signal a third-party (non-VoIP) app gets.
//
//  Hard limits (verified in the feasibility spike):
//   • CXCallObserver exposes call STATE only — never the phone number.
//   • It fires reliably only while OPS is foregrounded; iOS suspends it in the
//     background, so a `tel:` call placed from OPS and ended while OPS was
//     backgrounded is NOT observed here. That common case is handled by the
//     pending-intent path in `CallLogStore` (read on foreground).
//   • Needs NO entitlement and NO special permission.
//
//  This observer adds the one extra trigger CXCallObserver CAN give us: a call
//  that ends while OPS stays foregrounded (operator on speaker, returned to the
//  app). When that happens with a pending outbound intent, we can prompt
//  immediately instead of waiting for the next foreground transition.
//

import Foundation
import CallKit
import Combine

@MainActor
final class CallStateObserver: NSObject, ObservableObject {
    static let shared = CallStateObserver()

    private let observer = CXCallObserver()
    private var onCallEnded: (() -> Void)?
    private var started = false

    /// Set true whenever an observed call transitions to ended while OPS is
    /// foregrounded. Best-effort corroboration only — see the file header.
    @Published private(set) var didObserveCallEnd = false

    private override init() {
        super.init()
    }

    /// Begin observing. Idempotent. Delivers callbacks on the main queue.
    func start() {
        guard !started else { return }
        started = true
        observer.setDelegate(self, queue: nil) // nil → main queue
    }

    /// Register a hook fired the instant a call ends while OPS is foregrounded.
    func onForegroundCallEnded(_ handler: @escaping () -> Void) {
        onCallEnded = handler
    }

    func reset() {
        didObserveCallEnd = false
    }
}

extension CallStateObserver: CXCallObserverDelegate {
    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        guard call.hasEnded else { return }
        Task { @MainActor in
            self.didObserveCallEnd = true
            self.onCallEnded?()
        }
    }
}
