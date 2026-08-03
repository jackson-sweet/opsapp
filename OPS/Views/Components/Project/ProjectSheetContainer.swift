//
//  ProjectSheetContainer.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//
//  The app-wide project sheet. Every "open this project" route in the app
//  lands here by ID — the won toast's VIEW, notifications, Spotlight, the map,
//  the vinyl board, deep links.
//
//  Bug 4cbf2efe: the sheet resolved its project from SwiftData and nothing
//  else. If the row had not been cached yet it rendered an untokened
//  "Loading project details…" stub, re-checked the SAME empty cache once, and
//  then dismissed itself after a second — so a route to a project the device
//  had not synced silently ate the operator's tap. Nothing re-rendered when
//  the row did arrive.
//
//  It now HYDRATES: local first, then an authoritative fetch, then a live
//  re-query when an inbound merge lands. When the project genuinely cannot be
//  reached the sheet says so and offers RETRY / CLOSE instead of vanishing.
//  The one-second auto-dismiss survives for exactly its original honest case:
//  a presentation with no project id at all.
//

import SwiftUI

struct ProjectSheetContainer: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Environment(\.wizardStateManager) private var wizardStateManager
    @State private var selectedTaskDetail: TaskDetailInfo? = nil

    var body: some View {
        // Using item presentation pattern instead of isPresented
        // This approach is more reliable for presenting sheets based on optional values
        ZStack {
            Color.clear // Empty view that doesn't affect layout
        }
        // Project details sheet - uses isPresented and item together for more reliable presentation
        .sheet(isPresented: $appState.showProjectDetails) {
            ProjectSheetResolver(projectID: appState.activeProjectID)
                .environmentObject(dataController)
                .environmentObject(appState)
                .interactiveDismissDisabled(true)
                .wizardBannerIfAvailable(stateManager: wizardStateManager)
                .wizardOverlayIfAvailable(stateManager: wizardStateManager)
        }
        // Task details sheet
        .sheet(item: $selectedTaskDetail) { taskDetail in
            // Fetch fresh models using IDs
            if let project = dataController.getProject(id: taskDetail.projectId),
               let task = project.tasks.first(where: { $0.id == taskDetail.taskId }) {
                NavigationView {
                    ProjectDetailsView(project: project, initialSelectedTask: task)
                        .environmentObject(dataController)
                        .environmentObject(appState)
                }
                .interactiveDismissDisabled(true)
                .wizardBannerIfAvailable(stateManager: wizardStateManager)
                .wizardOverlayIfAvailable(stateManager: wizardStateManager)
            } else {
                VStack {
                    Text("Task no longer available")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        // Listen for task details from home
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowTaskDetailsFromHome"))) { notification in
            if let userInfo = notification.userInfo,
               let taskID = userInfo["taskID"] as? String,
               let projectID = userInfo["projectID"] as? String {

                // Show task details with just IDs
                selectedTaskDetail = TaskDetailInfo(taskId: taskID, projectId: projectID)
            }
        }
    }
}

// MARK: - Resolver

/// Owns the project sheet's resolution lifecycle. Split out of the container
/// so it can hold `@State` — a `.sheet` closure body cannot, which is why the
/// old fallback had nowhere to record that it was still working.
private struct ProjectSheetResolver: View {
    let projectID: String?

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState

    enum Phase: Equatable {
        case resolving
        case ready(projectId: String)
        case unreachable
        /// No project id was supplied at all — nothing to resolve, nothing to
        /// explain. Closes itself, as it always has.
        case nothingRequested
    }

    @State private var phase: Phase = .resolving
    @State private var isRetrying = false

    var body: some View {
        Group {
            switch phase {
            case .ready(let projectId):
                if let project = dataController.getProject(id: projectId) {
                    NavigationView {
                        ProjectDetailsView(project: project)
                    }
                } else {
                    // The row vanished between resolution and render.
                    loadingState.onAppear { phase = .resolving }
                }
            case .resolving, .nothingRequested:
                loadingState
            case .unreachable:
                unreachableState
            }
        }
        .task(id: projectID) { await resolve() }
        .onReceive(NotificationCenter.default.publisher(for: .inboundDataMerged)) { note in
            // A project row can arrive from realtime or a delta pull at any
            // moment. The old stub had no way to notice; this does.
            let names = note.userInfo?[InboundChangeSignal.entityNamesKey] as? [String]
            guard names?.contains("Project") == true, let projectID else { return }
            if dataController.getProject(id: projectID) != nil {
                phase = .ready(projectId: projectID)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            ProgressView()
                .tint(OPSStyle.Colors.secondaryText)
            Text("OPENING PROJECT")
                .font(OPSStyle.Typography.captionBold)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background.ignoresSafeArea())
    }

    private var unreachableState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("PROJECT UNAVAILABLE")
                .font(OPSStyle.Typography.captionBold)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("It may still be syncing, or it may be outside your access.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)

            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await resolve(force: true) }
                } label: {
                    Text(isRetrying ? "RETRYING" : "RETRY")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(1.2)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing4)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isRetrying)

                Button {
                    appState.dismissProjectDetails()
                } label: {
                    Text("CLOSE")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(1.2)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing4)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background.ignoresSafeArea())
    }

    // MARK: - Resolution

    private func resolve(force: Bool = false) async {
        guard let projectID, !projectID.isEmpty else {
            phase = .nothingRequested
            // Preserved verbatim from the original: with no id there is
            // nothing to say, so the sheet closes itself.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if appState.activeProjectID == nil {
                appState.dismissProjectDetails()
            }
            return
        }

        if !force, dataController.getProject(id: projectID) != nil {
            phase = .ready(projectId: projectID)
            return
        }

        if force { isRetrying = true }
        phase = .resolving
        defer { isRetrying = false }

        do {
            _ = try await dataController.getProjectDetails(projectId: projectID)
            if dataController.getProject(id: projectID) != nil {
                phase = .ready(projectId: projectID)
            } else {
                phase = .unreachable
            }
        } catch {
            phase = dataController.getProject(id: projectID) != nil
                ? .ready(projectId: projectID)
                : .unreachable
        }
    }
}
