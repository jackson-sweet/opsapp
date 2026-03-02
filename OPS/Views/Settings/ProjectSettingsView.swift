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
    @Environment(\.dismiss) private var dismiss

    // Navigation states
    @State private var showTaskSettings = false
    @State private var showSchedulingType = false

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
                    }
                    .padding(.bottom, 90)
                }
            }
        }
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

    // MARK: - Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
            .padding(.leading, 58)
    }
}
