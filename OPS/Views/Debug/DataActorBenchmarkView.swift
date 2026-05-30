//
//  DataActorBenchmarkView.swift
//  OPS
//
//  Developer tool for benchmarking the Phase 1 DataActor refactor against
//  the legacy MainActor sync path. Toggle the feature flag, trigger a full
//  sync or cleanup pass, and observe wall-clock times + actor availability.
//
//  The feature flag is read at DataController.setModelContext time, so the
//  active path doesn't change mid-run — a flag flip requires an app relaunch.
//  This view surfaces that fact explicitly so results aren't misread.
//

import SwiftUI
import SwiftData

struct DataActorBenchmarkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var log: String = ""
    @State private var running = false
    @State private var flagOn: Bool = UserDefaults.standard.bool(forKey: "feature.useDataActor")

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        flagCard
                        actorStatusCard
                        actionsCard
                        logCard
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(OPSStyle.Icons.close)
                        .font(.system(size: 20))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                Spacer()
            }
            Text("DataActor Benchmark")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Flag Card

    private var flagCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("FEATURE FLAG")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Toggle(isOn: Binding(
                get: { flagOn },
                set: { newValue in
                    flagOn = newValue
                    UserDefaults.standard.set(newValue, forKey: "feature.useDataActor")
                    appendLog("[flag] useDataActor set to \(newValue) — requires app relaunch to take effect")
                }
            )) {
                Text("feature.useDataActor")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.primaryAccent)

            Text("Flag is read once in DataController.setModelContext. Flip + relaunch to swap sync paths.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
    }

    // MARK: - Actor Status Card

    private var actorStatusCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("CURRENT STATE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            statusRow(label: "DataActor", value: dataController.dataActor != nil ? "Active" : "Nil (legacy path)")
            statusRow(label: "RefreshBridge", value: dataController.refreshBridge != nil ? "Subscribed" : "Nil")
            statusRow(label: "Connectivity", value: dataController.isConnected ? "Online" : "Offline")
            statusRow(label: "Authenticated", value: dataController.isAuthenticated ? "Yes" : "No")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("BENCHMARKS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button {
                Task { await runFullSync() }
            } label: {
                benchmarkButtonLabel(icon: "arrow.down.circle", title: "Run Full Sync (timed)")
            }
            .disabled(running)
            .opacity(running ? 0.5 : 1.0)

            Button {
                Task { await runCleanup() }
            } label: {
                benchmarkButtonLabel(icon: "trash.circle", title: "Run Cleanup Pass (timed)")
            }
            .disabled(running)
            .opacity(running ? 0.5 : 1.0)

            Button {
                log = ""
            } label: {
                benchmarkButtonLabel(icon: "doc.text", title: "Clear Log")
            }
            .opacity(log.isEmpty ? 0.5 : 1.0)
            .disabled(log.isEmpty)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
    }

    private func benchmarkButtonLabel(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            Text(title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            if running {
                ProgressView().tint(OPSStyle.Colors.primaryAccent)
            } else {
                Image("ops.chevron-right")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Log Card

    private var logCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("LOG")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if log.isEmpty {
                Text("No output yet.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding()
            } else {
                Text(log)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .fill(OPSStyle.Colors.background)
                    )
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
    }

    // MARK: - Benchmarks

    private func runFullSync() async {
        running = true
        defer { running = false }

        let pathLabel = (dataController.dataActor != nil) ? "DataActor" : "legacy @MainActor"
        appendLog("[bench] Full sync starting — path: \(pathLabel)")

        let start = Date()
        await dataController.syncEngine.fullSync()
        let elapsed = Date().timeIntervalSince(start)

        appendLog("[bench] Full sync took \(String(format: "%.2f", elapsed))s")
    }

    private func runCleanup() async {
        running = true
        defer { running = false }

        let pathLabel = (dataController.dataActor != nil) ? "DataActor" : "legacy @MainActor"
        appendLog("[bench] Cleanup starting — path: \(pathLabel)")

        let start = Date()
        if let actor = dataController.dataActor {
            await actor.cleanupDuplicateUsers()
            await actor.cleanupDuplicateProjects()
            await actor.cleanupDuplicateTasks()
            await actor.cleanupDuplicateClients()
            await actor.cleanupDuplicateTaskTypes()
        } else {
            await dataController.cleanupDuplicateUsers()
            await dataController.cleanupDuplicateProjects()
            await dataController.cleanupDuplicateTasks()
            await dataController.cleanupDuplicateClients()
            await dataController.cleanupDuplicateTaskTypes()
        }
        let elapsed = Date().timeIntervalSince(start)

        appendLog("[bench] Cleanup took \(String(format: "%.2f", elapsed))s")
    }

    private func appendLog(_ line: String) {
        let timestamp = Self.logFormatter.string(from: Date())
        if log.isEmpty {
            log = "\(timestamp) \(line)"
        } else {
            log.append("\n\(timestamp) \(line)")
        }
    }

    private static let logFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}
