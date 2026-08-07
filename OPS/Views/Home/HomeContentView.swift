//
//  HomeContentView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import MapKit
import Combine
import CoreLocation

/// A container for the main content of the HomeView
/// Used to reduce expression complexity in HomeView
struct HomeContentView: View {
    // Bindings - mapRegion removed, now handled internally by ProjectMapView
    let todaysScheduledTasks: [ProjectTask]
    let todaysProjects: [Project] // Keep for carousel
    let allProjects: [Project] // All projects for map "All" filter
    @Binding var selectedEventIndex: Int
    @Binding var showStartConfirmation: Bool
    @Binding var selectedProject: Project? // Not used anymore but keeping for backward compatibility
    @Binding var showFullDirectionsView: Bool
    let isLoading: Bool
    @Binding var showLocationPermissionView: Bool
    let billableRollup: HomeBillableThisWeekRollup
    let projectsNeedingTasksCount: Int

    // Environment objects
    @ObservedObject var appState: AppState
    @ObservedObject var inProgressManager: InProgressManager
    
    // Location manager to track authorization status
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    // Tutorial environment
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase

    // Callbacks
    let startProject: (Project) -> Void
    let stopProject: (Project) -> Void
    let getActiveProject: () -> Project?
    let openBillableItem: (HomeBillableProjectCandidate) -> Void
    let openProjectsNeedingTasks: () -> Void

    // State for project editing
    @State private var showingEditProject = false
    @State private var projectToEdit: Project?

    // Map filter mode — defaults based on user role (crew = today, others = active)
    // Can be overridden by user preference in Map Settings
    @AppStorage("mapDefaultFilter") private var mapDefaultFilterRaw = ""
    @State private var mapFilterMode: MapFilterMode = .today

    // State for random quote - only set once on view creation
    @State private var randomQuote: String = AppConfiguration.UX.noProjectQuotes.randomElement() ?? "No projects found"
    
    var body: some View {
        ZStack {
            // 1. Map layer
            mapLayer

            // 2. Gradient overlay — suppressed in project mode so the top
            //    project overlay (rendered inside OPSMapContainer) is not
            //    washed out by the dark fade.
            if !appState.isInProjectMode {
                gradientOverlay
                    .transition(.opacity)
            }

            // 3. UI content overlay (header, action bar - NOT carousel in tutorial mode)
            contentOverlay

            // 4. Tutorial dark overlay - sits BEHIND carousel but IN FRONT of everything else
            if tutorialMode && tutorialPhase == .tapProject {
                OPSStyle.Colors.overlayMedium
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(OPSStyle.Animation.standard, value: tutorialPhase)
            }

            // 5. Carousel layer - on TOP of tutorial overlay when in tutorial mode
            if tutorialMode && tutorialPhase == .tapProject {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 100) // Approximate header height
                    projectCarouselView
                        .padding(.top, -8)
                    Spacer()
                }
            }

            // 6. Loading overlay
            if isLoading {
                loadingOverlay
                    .transition(.opacity)
                    .zIndex(999)
            }

            // 7. Initial sync loading screen - shows on first login
            if dataController.isPerformingInitialSync {
                TacticalInitialLoadingView(dataController: dataController)
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .onAppear {
            // Set initial map filter from saved preference or role-based default
            if !mapDefaultFilterRaw.isEmpty,
               let saved = MapFilterMode(rawValue: mapDefaultFilterRaw) {
                mapFilterMode = saved
            } else if permissionStore.hasFullAccess("projects.view") {
                // Users with full project access default to showing all active projects
                mapFilterMode = .active
            }
        }
        // Sheet for editing projects (admin/office crew only)
        .sheet(isPresented: $showingEditProject) {
            if let projectToEdit = projectToEdit {
                ProjectFormSheet(mode: .edit(projectToEdit)) { _ in
                    showingEditProject = false
                    self.projectToEdit = nil
                }
            }
        }
    }
    
    // MARK: - View Components
    
    // Always use new map implementation
    private let useNewMap = true
    
    private var mapLayer: some View {
        ZStack {
            // New map implementation with safety wrapper
            OPSMapContainer(
                projects: allProjects,
                selectedIndex: allProjects.isEmpty ? 0 :
                    (todaysScheduledTasks.indices.contains(selectedEventIndex) ?
                        allProjects.firstIndex(where: { $0.id == todaysScheduledTasks[selectedEventIndex].projectId }) ?? 0 : 0),
                selectedTask: todaysScheduledTasks.indices.contains(selectedEventIndex) ? todaysScheduledTasks[selectedEventIndex] : nil,
                onProjectSelected: { project in
                    // Find event index for this project
                    if let index = todaysScheduledTasks.firstIndex(where: { $0.projectId == project.id }) {
                        selectedEventIndex = index
                        // Reset confirmation when selecting via map
                        showStartConfirmation = false
                    }
                },
                onNavigationStarted: { project in
                    
                    // Don't immediately enter project mode - let navigation start first
                    // Just update the project status and prepare for navigation
                    showStartConfirmation = false
                    
                    // Update project status to 'in progress' without entering project mode yet
                    if project.status != .inProgress {
                        Task {
                            do {
                                try await dataController.updateProjectStatus(
                                    project: project,
                                    to: .inProgress
                                )

                                // Update local status immediately for UI consistency
                                await MainActor.run {
                                    project.status = .inProgress
                                    project.needsSync = false
                                    project.lastSyncedAt = Date()

                                    // Save to model context
                                    if let modelContext = dataController.modelContext {
                                        try? modelContext.save()
                                    }
                                }
                            } catch {
                                print("[START_PROJECT] Failed to update project status: \(error)")
                            }
                        }
                    }
                    
                    // Delay entering project mode to allow navigation to start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Now enter project mode after navigation has started
                        appState.enterProjectMode(projectID: project.id)
                        
                        // For the old system, we also need to start routing
                        if let coordinate = project.coordinate,
                           let userLocation = locationManager.userLocation {
                            inProgressManager.startRouting(to: coordinate, from: userLocation)
                        }
                    }
                },
                filterMode: $mapFilterMode,
                appState: appState,
                locationManager: locationManager
            )
            
            // Semi-transparent dark overlay - using clear since we have gradient overlay
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .overlay(locationDisabledOverlay)
    }
    
    private var gradientOverlay: some View {
        VStack(spacing: 0) {
            // Top gradient — map bleeds through with increasing opacity toward the top
            LinearGradient(
                stops: [
                    .init(color: OPSStyle.Colors.background.opacity(0.95), location: 0),
                    .init(color: OPSStyle.Colors.background.opacity(0.85), location: 0.15),
                    .init(color: OPSStyle.Colors.background.opacity(0.5), location: 0.45),
                    .init(color: OPSStyle.Colors.background.opacity(0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)

            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
    
    /// Whether carousel should be shown in a separate layer (for tutorial overlay effect)
    private var showCarouselInSeparateLayer: Bool {
        tutorialMode && tutorialPhase == .tapProject
    }

    /// Whether the supporting cards (billable rollup, needs-tasks strip) may
    /// hold their slice of the map. They live in a layer ABOVE the map, so any
    /// presented project surface — pin card, stacked-group sheet, details —
    /// would otherwise show them floating over it. They yield, and come back
    /// the moment the surface is dismissed. Only these two: the filter chips
    /// and the carousel are the map's own controls and stay put.
    static func supportingCardsVisible(isInProjectMode: Bool, isProjectSurfacePresented: Bool) -> Bool {
        !isInProjectMode && !isProjectSurfacePresented
    }

    /// Instance-side reading of the above, off the observed AppState.
    private var supportingCardsVisible: Bool {
        Self.supportingCardsVisible(
            isInProjectMode: appState.isInProjectMode,
            isProjectSurfacePresented: appState.isProjectSurfacePresented
        )
    }

    private var contentOverlay: some View {
        VStack(spacing: 0) {
            // Header — hidden in project mode so the top project overlay
            // (rendered inside OPSMapContainer) has the top of the screen
            // to itself.
            if !appState.isInProjectMode {
                headerView
            }

            // Project carousel or empty state (hide when shown in separate layer for tutorial)
            if !showCarouselInSeparateLayer {
                projectCarouselView
                    .padding(.top, -8) // Bring carousel closer to header
            } else {
                // Placeholder space when carousel is in separate layer
                Spacer()
                    .frame(height: 120)
            }

            // Map filter chips — below carousel
            if !appState.isInProjectMode {
                MapFilterChips(filterMode: $mapFilterMode)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }

            // Billable-this-week rollup — sits below the TODAY / ACTIVE / ALL
            // filter chips; collapsible so it can tuck out of the way. Steps
            // aside for any presented project surface (see
            // supportingCardsVisible) rather than floating above it.
            if supportingCardsVisible,
               billableRollup.hasItems,
               permissionStore.can("finances.view") {
                HomeBillableThisWeekCard(
                    rollup: billableRollup,
                    onSelect: openBillableItem
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing1)
                .transition(.opacity)
            }

            // Committed jobs nobody has broken into tasks — invisible until
            // true, gone the moment the work is planned. Tap opens the
            // needs-tasks review flow (same surface the rail notification
            // routes to). Data self-scopes to operators who can see task-less
            // projects, so crew never meet this strip.
            if supportingCardsVisible, projectsNeedingTasksCount > 0 {
                HomeNeedsTasksStrip(
                    count: projectsNeedingTasksCount,
                    onOpen: openProjectsNeedingTasks
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing1)
                .transition(.opacity)
            }

            Spacer()

            // Show project action bar when in project mode
            if appState.isInProjectMode, let project = getActiveProject() {
                ProjectActionBar(project: project)
                    //.padding(.horizontal, OPSStyle.Layout.spacing4)
                    .padding(.bottom, 120) // Add padding for tab bar
            }
        }
        // Drive a synchronized animation on project-mode transitions so the
        // AppHeader's insertion/removal runs on the same timeline as the
        // OPSMapContainer top project overlay's animation. Previously the
        // header toggled instantly (no animation driver on the parent),
        // so when exiting project mode the AppHeader appeared immediately
        // while the map overlay was still animating out — the two headers
        // visually stacked for the duration of the overlay animation.
        .animation(OPSStyle.Animation.standard, value: appState.isInProjectMode)
        // The supporting cards cross-fade on the same curve the pin card
        // slides in on, so the two read as one movement rather than a card
        // blinking out under a sheet.
        .animation(OPSStyle.Animation.standard, value: appState.isProjectSurfacePresented)
    }

    private var headerView: some View {
        AppHeader(headerType: .home)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
    }
    
    private var projectCarouselView: some View {
        Group {
            if !appState.isInProjectMode && mapFilterMode == .today {
                if !todaysScheduledTasks.isEmpty {
                    EventCarousel(
                        tasks: todaysScheduledTasks,
                        selectedIndex: $selectedEventIndex,
                        showStartConfirmation: $showStartConfirmation,
                        isInProjectMode: appState.isInProjectMode,
                        activeProjectID: appState.activeProjectID,
                        onStart: startProject,
                        onStop: stopProject,
                        onLongPress: { project in

                            // EXPLICITLY ensure we don't start the project by turning off confirmation
                            showStartConfirmation = false

                            // Check permission - if user can edit projects, open edit mode, otherwise show details
                            if permissionStore.can("projects.edit") {
                                projectToEdit = project
                                showingEditProject = true
                            } else {
                                // Show project details (sheet) for field crew
                                showProjectDetails(project)
                            }
                        }
                    )
                } else if !isLoading {
                    emptyProjectsView
                        .padding(.top, OPSStyle.Layout.spacing3_5)
                }
            }
        }
    }
    
    // Helper method to show project details
    private func showProjectDetails(_ project: Project) {
        
        // Make sure confirmation is turned off to avoid state conflicts
        showStartConfirmation = false
        
        // Call AppState's viewProjectDetails method
        appState.viewProjectDetails(project)
        
        // Log completion
    }
    
    private var emptyProjectsView: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Project title
            Text("NO PROJECTS SCHEDULED FOR TODAY.")
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            // Client name - uses the state variable that was set once on view creation
            Text(randomQuote)
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true) // Allow text to expand vertically

        }
        .frame(maxWidth: .infinity, alignment: .leading) // Full width
        .padding(OPSStyle.Layout.spacing3) // Use standard spacing
        .background(
            // Custom background with blur effect
            BlurView(style: .dark)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5) // Match carousel horizontal padding
        .contentShape(Rectangle()) // Make entire card tappable
    }
    
    private var loadingOverlay: some View {
        ZStack {
            // Full-screen dimming scrim — canvas black over the map
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: OPSStyle.Layout.spacing3) {
                // Tactical loading bar
                TacticalLoadingBarAnimated(
                    barCount: 8,
                    barWidth: 2,
                    barHeight: 6,
                    spacing: OPSStyle.Layout.spacing1,
                    emptyColor: OPSStyle.Colors.pinDotNeutral,
                    fillColor: OPSStyle.Colors.pinDotActive
                )

                // Loading text
                Text("LOADING PROJECTS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1.2)
            }
        }
    }
    
    // MARK: - Helper Methods
    // All map zoom/region logic has been moved to ProjectMapView for centralized state management
    
    // MARK: - Navigation Info View
    private var navigationInfoView: some View {
        VStack(spacing: 0) {
            // Progress and arrival info
            HStack {
                // Time remaining
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("TIME")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    if let travelTime = inProgressManager.activeRoute?.expectedTravelTime {
                        Text(formatTime(travelTime))
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("--")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                
                Spacer()
                
                // Distance remaining
                VStack(alignment: .center, spacing: OPSStyle.Layout.spacing1) {
                    Text("DISTANCE")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    if let distance = inProgressManager.activeRoute?.distance {
                        Text(formatDistance(distance))
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("--")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                
                Spacer()
                
                // Arrival time
                VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing1) {
                    Text("ARRIVAL")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    if let arrival = inProgressManager.estimatedArrival {
                        Text(arrival.components(separatedBy: " ").first ?? arrival)
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("--:--")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helper Methods for Navigation Info
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 100 {
            return String(format: "%.0f m", distance)
        } else if distance < 1000 {
            return String(format: "%.0f m", (distance / 10).rounded() * 10)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    // MARK: - Location Disabled Overlay
    private var locationDisabledOverlay: some View {
        Group {
            // Show overlay only when location is denied/restricted and in project mode with routing active
            if (locationManager.authorizationStatus == .denied || 
                locationManager.authorizationStatus == .restricted) &&
                appState.isInProjectMode &&
                inProgressManager.isRouting {
                
                ZStack {
                    // Semi-transparent background
                    OPSStyle.Colors.modalOverlay
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    
                    // Message card
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // Icon
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                        
                        // Title
                        Text("LOCATION SERVICES DISABLED")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .multilineTextAlignment(.center)
                        
                        // Message
                        Text("Enable location services in Settings to see routing and navigation.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // Open Settings button
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "gear")
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                
                                Text("OPEN SETTINGS")
                                    .font(OPSStyle.Typography.button)
                            }
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .padding(.horizontal, OPSStyle.Layout.spacing4)
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        .padding(.top, OPSStyle.Layout.spacing2)
                    }
                    .padding(OPSStyle.Layout.spacing5)
                    .glassDense()
                    .padding(.horizontal, 40)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(OPSStyle.Animation.standard, value: locationManager.authorizationStatus)
            }
        }
    }
}

// Internal (not private) so the snapshot harness can render it in isolation.
struct HomeBillableThisWeekCard: View {
    let rollup: HomeBillableThisWeekRollup
    let onSelect: (HomeBillableProjectCandidate) -> Void

    // Collapsed by default — the header (total + job count) carries the
    // at-a-glance value; the detail is opt-in. The choice persists per operator.
    //
    // NOTE: @AppStorage mutations do NOT participate in `withAnimation`
    // transactions, so animating `isExpanded` directly off AppStorage makes the
    // collapse snap with no motion. We drive the animation off a plain @State
    // and mirror it into AppStorage on every toggle (and read it back on appear).
    @AppStorage("homeBillableThisWeekExpanded") private var persistedExpanded = false
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            header

            if isExpanded {
                // Every job is listed — no row cap. The card sits on the map
                // (no outer scroll), so once the list outgrows its slice of
                // the screen the detail scrolls internally instead of pushing
                // the layout off the bottom edge.
                Group {
                    if rollup.projectCount <= Self.rowsBeforeInternalScroll {
                        detailSections
                    } else {
                        ScrollView {
                            detailSections
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: Self.expandedDetailMaxHeight)
                    }
                }
                .transition(.opacity)
            }
        }
        .opsCardStyle(
            padding: isExpanded
                ? OPSStyle.Layout.spacing3
                : OPSStyle.Layout.spacing2
        )
        // Restore the persisted state without animation so the card simply
        // appears in its last state rather than animating open on every launch.
        .onAppear { isExpanded = persistedExpanded }
    }

    // MARK: - Money display (one rule for the hero and the rows)

    /// The hero total. A week where no job carries a value renders the
    /// empty-money token rather than a fabricated `$0` — an unvalued job is
    /// "no amount recorded", not "zero dollars billable".
    static func totalText(for rollup: HomeBillableThisWeekRollup) -> String {
        rollup.hasKnownAmounts ? BooksFormat.currency(rollup.totalKnownAmount) : BooksFormat.emptyCurrency
    }

    /// A row's amount slot, on the same rule as the hero so the amount column
    /// reads as money the whole way down whether or not a job is valued.
    static func amountText(for candidate: HomeBillableProjectCandidate) -> String {
        candidate.amount.map(BooksFormat.currency) ?? BooksFormat.emptyCurrency
    }

    static func jobCountText(for rollup: HomeBillableThisWeekRollup) -> String {
        "\(rollup.projectCount) \(rollup.projectCount == 1 ? "JOB" : "JOBS")"
    }

    /// Up to this many jobs the detail renders inline and the card hugs its
    /// content; beyond it, the detail pins to `expandedDetailMaxHeight` and
    /// scrolls internally so the open card never collides with the tab bar
    /// on the smallest supported devices.
    private static let rowsBeforeInternalScroll = 4

    /// Roughly six rows plus section headers.
    private static let expandedDetailMaxHeight: CGFloat = 264

    private var detailSections: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if !rollup.closingThisWeek.isEmpty {
                section("CLOSING", items: rollup.closingThisWeek)
            }

            if !rollup.readyToBill.isEmpty {
                section("READY TO BILL", items: rollup.readyToBill)
            }
        }
    }

    // MARK: - Header (tap anywhere to collapse / expand)

    private var header: some View {
        Button(action: toggle) {
            Group {
                if isExpanded {
                    expandedHeader
                } else {
                    collapsedHeader
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            Text("// BILLABLE THIS WEEK")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.textMute)
                .lineLimit(1)

            Spacer(minLength: OPSStyle.Layout.spacing1)

            Text(Self.totalText(for: rollup))
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(rollup.hasKnownAmounts ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                .monospacedDigit()
                .lineLimit(1)

            Text(Self.jobCountText(for: rollup))
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.finRevenue)
                .monospacedDigit()
                .lineLimit(1)

            Image(systemName: OPSStyle.Icons.chevronDown)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private var expandedHeader: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("// BILLABLE THIS WEEK")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.textMute)

                    // No project this week carries a value → the empty-money
                    // token, never a lying "$0". A project with no
                    // invoice/estimate is "no data", not zero dollars billable.
                    Text(Self.totalText(for: rollup))
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(rollup.hasKnownAmounts ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                        .monospacedDigit()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing1) {
                    Text("\(rollup.projectCount)")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.finRevenue)
                        .monospacedDigit()
                    Text(rollup.projectCount == 1 ? "JOB" : "JOBS")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.text3)
            }

            Image(systemName: OPSStyle.Icons.chevronDown)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.textMute)
                .rotationEffect(.degrees(180))
                .padding(.leading, OPSStyle.Layout.spacing1)
        }
    }

    private func toggle() {
        // Single easing curve, no spring. Reduced motion falls back to a
        // 150ms opacity-only change per the OPS motion identity. Animate the
        // @State (which participates in the transaction); persist alongside.
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : OPSStyle.Animation.standard) {
            isExpanded.toggle()
        }
        persistedExpanded = isExpanded
        // Light impact — one earned tick on a deliberate user toggle.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func section(_ title: String, items: [HomeBillableProjectCandidate]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text3)

            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            Text(item.title.uppercased())
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.text)
                                .lineLimit(1)

                            Text("\(item.taskCount) \(item.taskCount == 1 ? "TASK" : "TASKS")")
                                .font(OPSStyle.Typography.microLabel)
                                .foregroundColor(OPSStyle.Colors.text3)
                        }

                        Spacer()

                        // Valued jobs show their dollar figure; unvalued jobs
                        // show the empty-money token — the amount slot never
                        // silently disappears, so the column scans cleanly as
                        // one column of money either way.
                        Text(Self.amountText(for: item))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(item.amount == nil ? OPSStyle.Colors.text3 : OPSStyle.Colors.finRevenue)
                            .monospacedDigit()

                        Image(systemName: OPSStyle.Icons.arrowRight)
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.textMute)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                }
                .buttonStyle(.plain)
            }
        }
    }

}

// MARK: - Needs-Tasks Strip

/// One-line attention strip for accepted / in-progress projects with zero
/// tasks — work the business committed to that the crew literally cannot
/// see. Appears only while the condition is true; tapping opens the
/// needs-tasks review flow (the same surface the rail notification routes
/// to), and the strip clears itself once every job has tasks.
///
/// Internal (not private) so the snapshot harness can render it in isolation.
struct HomeNeedsTasksStrip: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("// NEEDS TASKS")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.textMute)

                    Text("Accepted, no tasks yet.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.text)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing1) {
                    Text("\(count)")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.tanTextM)
                        .monospacedDigit()
                    Text(count == 1 ? "JOB" : "JOBS")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.text3)
                }

                Image(systemName: OPSStyle.Icons.arrowRight)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .padding(.leading, OPSStyle.Layout.spacing1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opsCardStyle(padding: OPSStyle.Layout.spacing3)
        .accessibilityLabel("\(count) accepted \(count == 1 ? "job" : "jobs") without tasks. Opens task planning.")
    }
}
