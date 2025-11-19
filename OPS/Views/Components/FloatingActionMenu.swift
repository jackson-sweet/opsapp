//
//  FloatingActionMenu.swift
//  OPS
//
//  Reusable floating action button menu for creating projects, tasks, clients, and task types
//  Only visible to Office Crew and Admin roles
//

import SwiftUI

struct FloatingActionMenu: View {
    @EnvironmentObject private var dataController: DataController
    @State private var showCreateMenu = false
    @State private var showingCreateProject = false
    @State private var showingCreateClient = false
    @State private var showingCreateTaskType = false
    @State private var showingCreateTask = false

    // Check if current user can see FAB
    private var canShowFAB: Bool {
        guard let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }

    var body: some View {
        ZStack {
            // Dimmed overlay when menu is open
            if showCreateMenu {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showCreateMenu = false
                        }
                    }
            }

            if canShowFAB {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        VStack(alignment: .trailing, spacing: 16) {
                            // Floating menu items (shown when expanded)
                            if showCreateMenu {
                                FloatingActionItem(
                                    icon: "checklist",
                                    label: "New Task Type",
                                    action: {
                                        showCreateMenu = false
                                        showingCreateTaskType = true
                                    }
                                )
                                .transition(.scale.combined(with: .opacity))

                                FloatingActionItem(
                                    icon: "checkmark.square.fill",
                                    label: "Create Task",
                                    action: {
                                        showCreateMenu = false
                                        showingCreateTask = true
                                    }
                                )
                                .transition(.scale.combined(with: .opacity))

                                FloatingActionItem(
                                    icon: "folder.badge.plus",
                                    label: "Create Project",
                                    action: {
                                        showCreateMenu = false
                                        showingCreateProject = true
                                    }
                                )
                                .transition(.scale.combined(with: .opacity))

                                FloatingActionItem(
                                    icon: "person.badge.plus",
                                    label: "Create Client",
                                    action: {
                                        showCreateMenu = false
                                        showingCreateClient = true
                                    }
                                )
                                .transition(.scale.combined(with: .opacity))
                            }

                            // Main plus button
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showCreateMenu.toggle()
                                }
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 30))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .rotationEffect(.degrees(showCreateMenu ? 225 : 0))
                                    .frame(width: 64, height: 64)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: OPSStyle.Colors.background.opacity(0.4), radius: 8, x: 0, y: 4)
                            }
                        }
                        .padding(.trailing, 36)
                        .padding(.bottom, 140) // Position above tab bar
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientFormSheet(mode: .create) { _ in }
        }
        .sheet(isPresented: $showingCreateProject) {
            ProjectFormSheet(mode: .create) { _ in }
        }
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeFormSheet { _ in }
        }
        .sheet(isPresented: $showingCreateTask) {
            TaskFormSheet(mode: .create) { _ in }
        }
    }
}
/*
struct FloatingActionItem: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 48, height: 48)
                    .background(.clear)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(OPSStyle.Colors.secondaryText.opacity(1), lineWidth: 1)
                    )
                    .shadow(color: OPSStyle.Colors.background.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
    }
}
*/
