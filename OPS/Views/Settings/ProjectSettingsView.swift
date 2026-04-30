//
//  ProjectSettingsView.swift
//  OPS
//
//  Project-related settings for office crews and admins
//

import SwiftUI
import SwiftData

struct ProjectSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss

    // Navigation states
    @State private var showTaskSettings = false
    @State private var showSchedulingType = false

    // Project review settings (bound to Company model)
    @State private var overdueThreshold: Int = 14
    @State private var reminderFrequency: Int = 7
    @State private var matchInvoiceTerms: Bool = false

    // Bug e33aa336 — anchor a section temporarily highlighted by a search
    // deep-link. nil = no highlight; sectionId matches the .id() values
    // tagged below. Self-clears after the spotlight animation completes.
    @State private var highlightedSection: String? = nil

    // Anchor IDs for ScrollViewReader. Centralized so the deep-link observer
    // and the spotlight overlay reference the same strings.
    private enum AnchorID {
        static let projectSettings = "project_settings"
        static let projectReview = "project_review"
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Project Settings",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        settingsSection(title: "PROJECT SETTINGS") {
                            settingsRow(
                                icon: "square.grid.2x2",
                                title: "Task Types",
                                action: { showTaskSettings = true }
                            )

                            sectionDivider

                            settingsRow(
                                icon: "calendar.badge.clock",
                                title: "Scheduling Type",
                                action: { showSchedulingType = true }
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .id(AnchorID.projectSettings)
                        .deepLinkSpotlight(highlightedSection == AnchorID.projectSettings)

                        // MARK: - Project Review Settings
                        settingsSection(title: "PROJECT REVIEW") {
                            // Overdue threshold stepper
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Overdue Threshold")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Text("Days after completion before flagging for review")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }

                                Spacer()

                                Stepper("\(overdueThreshold) days", value: $overdueThreshold, in: 7...90)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .labelsHidden()
                                    .onChange(of: overdueThreshold) { _, newValue in
                                        saveReviewSetting(\.overdueReviewThresholdDays, value: newValue)
                                    }

                                Text("\(overdueThreshold) days")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)

                            sectionDivider

                            // Reminder frequency stepper
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reminder Frequency")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Text("How often to re-notify about overdue projects")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }

                                Spacer()

                                Stepper("\(reminderFrequency) days", value: $reminderFrequency, in: 1...30)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .labelsHidden()
                                    .onChange(of: reminderFrequency) { _, newValue in
                                        saveReviewSetting(\.overdueReminderFrequencyDays, value: newValue)
                                    }

                                Text("\(reminderFrequency) days")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)

                            sectionDivider

                            // Match invoice payment terms toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Match Invoice Payment Terms")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(permissionStore.can("finances.view") ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                                    Text("Use invoice net terms instead of fixed threshold")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }

                                Spacer()

                                Toggle("", isOn: $matchInvoiceTerms)
                                    .labelsHidden()
                                    .tint(OPSStyle.Colors.primaryAccent)
                                    .disabled(!permissionStore.can("finances.view"))
                                    .onChange(of: matchInvoiceTerms) { _, newValue in
                                        saveReviewSetting(\.matchInvoicePaymentTerms, value: newValue)
                                    }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .opacity(permissionStore.can("finances.view") ? 1.0 : 0.5)
                        }
                        .padding(.horizontal, 20)
                        .id(AnchorID.projectReview)
                        .deepLinkSpotlight(highlightedSection == AnchorID.projectReview)
                    }
                    .padding(.bottom, 90)
                }
                // Bug e33aa336 — settings search deep-link target. When the
                // search query was scoped to project-review controls, scroll
                // the matching section into view and pulse it briefly so the
                // user's eye lands on the right cluster of controls.
                .onReceive(NotificationCenter.default.publisher(for: SettingsDeepLink.projectSettings)) { notification in
                    guard let section = notification.userInfo?[SettingsDeepLink.userInfoSectionKey] as? String else { return }
                    let anchor: String?
                    switch section {
                    case "project_review": anchor = AnchorID.projectReview
                    default: anchor = nil
                    }
                    if let anchor {
                        triggerDeepLinkScroll(to: anchor, proxy: proxy)
                    }
                }
                }
            }
        }
        .trackScreen("Settings.Projects")
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showTaskSettings) {
            NavigationStack {
                TaskSettingsView()
                    .environmentObject(dataController)
            }
        }
        .fullScreenCover(isPresented: $showSchedulingType) {
            NavigationStack {
                SchedulingTypeExplanationView()
                    .environmentObject(dataController)
            }
        }
        .onAppear {
            loadReviewSettings()
        }
    }

    /// Scroll to the deep-linked section, pulse-highlight it, then clear.
    /// Splitting the scroll-then-clear into a Task with a 1.6s sleep lets the
    /// user see WHERE the spotlight lands instead of seeing it land already
    /// faded — matching what the human eye expects after a navigation jump.
    private func triggerDeepLinkScroll(to anchor: String, proxy: ScrollViewProxy) {
        // Light haptic at the moment of arrival — the spotlight is the
        // "your search ended here" beat; pair it with a subtle .selection
        // tap so the touchpoint feels grounded.
        UISelectionFeedbackGenerator().selectionChanged()

        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
        withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
            highlightedSection = anchor
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    highlightedSection = nil
                }
            }
        }
    }

    // MARK: - Grouped Section Builder

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                content()
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Row Component

    private func settingsRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 28, alignment: .center)

                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Review Settings Helpers

    private func loadReviewSettings() {
        guard let companyId = dataController.currentUser?.companyId,
              let company = dataController.getCompany(id: companyId) else { return }
        overdueThreshold = company.overdueReviewThresholdDays
        reminderFrequency = company.overdueReminderFrequencyDays
        matchInvoiceTerms = company.matchInvoicePaymentTerms
    }

    private func saveReviewSetting<T>(_ keyPath: ReferenceWritableKeyPath<Company, T>, value: T) {
        guard let companyId = dataController.currentUser?.companyId,
              let company = dataController.getCompany(id: companyId) else { return }
        company[keyPath: keyPath] = value
        company.needsSync = true
        try? dataController.modelContext?.save()
    }

    // MARK: - Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
            .padding(.leading, 58)
    }
}
