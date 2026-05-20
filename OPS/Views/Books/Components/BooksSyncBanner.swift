//
//  BooksSyncBanner.swift
//  OPS
//
//  Books — Mission Deck Phase B.
//  Slim banner shown above the inline header when a sync request is in flight,
//  the network is unreachable, or the last fetch hard-failed.
//
//  Spec: docs/superpowers/specs/2026-05-19-books-tab-mission-deck-rebuild.md § 4.2
//

import Foundation
import SwiftUI

struct BooksSyncBanner: View {
    enum SyncState: Equatable {
        case syncing
        case offline
        case error
    }

    let lastSyncedAt: Date?
    let state: SyncState
    var onRetry: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var dotColor: Color {
        switch state {
        case .syncing: return OPSStyle.Colors.tertiaryText
        case .offline, .error: return OPSStyle.Colors.roseMobile
        }
    }

    private var labelText: String {
        let ts = lastSyncedAt.map { Self.timestampFormatter.string(from: $0) } ?? "—"
        switch state {
        case .syncing: return "SYS :: SYNC · \(ts)"
        case .offline: return "SYS :: OFFLINE · CACHED \(ts)"
        case .error:   return "SYS :: ERROR · LAST \(ts)"
        }
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .opacity(reduceMotion ? 1.0 : (pulse ? 0.3 : 1.0))

            Text(labelText)
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(1.6)  // 0.16em at 10pt
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            if state != .syncing, let onRetry {
                Button(action: onRetry) {
                    Text("RETRY")
                        .font(.custom("CakeMono-Light", size: 11))
                        .tracking(1.3)
                        .foregroundColor(OPSStyle.Colors.roseMobile)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry sync")
                .accessibilityHint("Double-tap to try again")
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("BooksSyncBanner — syncing") {
    BooksSyncBanner(lastSyncedAt: Date(timeIntervalSinceNow: -120), state: .syncing)
        .padding(OPSStyle.Layout.spacing3_5)
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
}

#Preview("BooksSyncBanner — offline") {
    BooksSyncBanner(
        lastSyncedAt: Date(timeIntervalSinceNow: -3600),
        state: .offline,
        onRetry: {}
    )
    .padding(OPSStyle.Layout.spacing3_5)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("BooksSyncBanner — error") {
    BooksSyncBanner(
        lastSyncedAt: Date(timeIntervalSinceNow: -900),
        state: .error,
        onRetry: {}
    )
    .padding(OPSStyle.Layout.spacing3_5)
    .background(OPSStyle.Colors.background)
    .preferredColorScheme(.dark)
}
#endif
