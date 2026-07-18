//
//  OPSConfirm.swift
//  OPS
//
//  The standardized confirmation popup (Leads redesign spec §6) — one
//  reusable modifier for every guarded exit going forward (ARCHIVE, the
//  repeat-run DISCARD leg, and any future confirm path). Generalizes
//  DeleteConfirmationModifier, which stays only for its legacy call sites.
//
//  Native `.alert` under the hood — matches the app's existing alert
//  confirms: dims the background, centers, and behaves exactly as iOS
//  users expect. Parameterized copy keeps the OPS register at every call
//  site: UPPERCASE title + verb, terse declarative message, no
//  exclamation points.
//
//      @State private var confirm: OPSConfirmConfig?
//      ...
//      .opsConfirm($confirm)
//      ...
//      confirm = OPSConfirmConfig(
//          title: "ARCHIVE LEAD?",
//          message: "It leaves the queue. Restore any time from the by-stage list.",
//          verb: "ARCHIVE",
//          isDestructive: false
//      ) { archive() }
//

import SwiftUI
import UIKit

/// One confirmation's full content. `Identifiable` so `.opsConfirm` can be
/// driven by optional state (nil = hidden), matching the app's sheet(item:)
/// idiom.
struct OPSConfirmConfig: Identifiable {
    let id = UUID()
    let title: String        // "ARCHIVE LEAD?"
    let message: String      // "It leaves the queue. Restore any time from the by-stage list."
    let verb: String         // "ARCHIVE"
    let isDestructive: Bool  // Button(role: .destructive)
    let onConfirm: () -> Void

    init(
        title: String,
        message: String,
        verb: String,
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.verb = verb
        self.isDestructive = isDestructive
        self.onConfirm = onConfirm
    }
}

private struct OPSConfirmModifier: ViewModifier {
    @Binding var config: OPSConfirmConfig?

    func body(content: Content) -> some View {
        content.alert(
            config?.title ?? "",
            isPresented: Binding(
                get: { config != nil },
                set: { if !$0 { config = nil } }
            ),
            presenting: config
        ) { cfg in
            Button("CANCEL", role: .cancel) {}
            Button(cfg.verb, role: cfg.isDestructive ? .destructive : nil) {
                // Medium impact — a guarded exit is a commit moment (spec §10).
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                cfg.onConfirm()
            }
        } message: { cfg in
            Text(cfg.message)
        }
    }
}

extension View {
    /// Present the standardized OPS confirmation. Set the binding to present;
    /// it clears itself on dismiss (cancel or confirm).
    func opsConfirm(_ config: Binding<OPSConfirmConfig?>) -> some View {
        modifier(OPSConfirmModifier(config: config))
    }
}
