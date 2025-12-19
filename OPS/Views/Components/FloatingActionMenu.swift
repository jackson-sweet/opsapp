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
    @Environment(\.tutorialMode) private var tutorialMode
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
                LinearGradient(
                    colors: [Color(OPSStyle.Colors.background).opacity(0.85), .clear],
                    startPoint: .trailing,
                    endPoint: .leading
                )
                .ignoresSafeArea()
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: showCreateMenu)
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

                        VStack(alignment: .trailing, spacing: 24) {
                            // Floating menu items (shown when expanded)
                            if showCreateMenu {
                                // New Task Type - disabled in tutorial mode
                                FloatingActionItem(
                                    icon: OPSStyle.Icons.taskType,
                                    label: "New Task Type",
                                    action: {
                                        showCreateMenu = false
                                        showingCreateTaskType = true
                                    }
                                )
                                .offset(x: -10) // Center 48pt icon over 64pt main button
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3).delay(0.8), value: showCreateMenu)
                                .opacity(tutorialMode ? 0.4 : 1.0)
                                .allowsHitTesting(!tutorialMode)

                                // Create Task - disabled in tutorial mode
                                FloatingActionItem(
                                    icon: OPSStyle.Icons.task,
                                    label: "Create Task",
                                    action: {
                                        showCreateMenu = false
                                        showingCreateTask = true
                                    }
                                )
                                .offset(x: -10) // Center 48pt icon over 64pt main button
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3).delay(0.6), value: showCreateMenu)
                                .opacity(tutorialMode ? 0.4 : 1.0)
                                .allowsHitTesting(!tutorialMode)

                                // Create Project - always enabled
                                FloatingActionItem(
                                    icon: OPSStyle.Icons.project,
                                    label: "Create Project",
                                    action: {
                                        showCreateMenu = false
                                        showingCreateProject = true
                                    }
                                )
                                .offset(x: -10) // Center 48pt icon over 64pt main button
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3).delay(0.4), value: showCreateMenu)

                                // Create Client - disabled in tutorial mode
                                FloatingActionItem(
                                    icon: OPSStyle.Icons.client,
                                    label: "Create Client",
                                    action: {
                                        showCreateMenu = false
                                        showingCreateClient = true
                                    }
                                )
                                .offset(x: -10) // Center 48pt icon over 64pt main button
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3).delay(0.2), value: showCreateMenu)
                                .opacity(tutorialMode ? 0.4 : 1.0)
                                .allowsHitTesting(!tutorialMode)
                            }

                            // Main plus button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showCreateMenu.toggle()
                                }
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 30))
                                    .foregroundColor(OPSStyle.Colors.buttonText)
                                    .rotationEffect(.degrees(showCreateMenu ? 225 : 0))
                                    .frame(width: 64, height: 64)
                                    .background(.ultraThinMaterial.opacity(0.8))
                                    .clipShape(Circle())
                                    .shadow(color: OPSStyle.Colors.background.opacity(0.4), radius: 8, x: 0, y: 4)
                                    .overlay {
                                        Circle()
                                            .stroke(OPSStyle.Colors.buttonText, lineWidth: 2)
                                    }
                            }
                        }
                        .padding(.trailing, 36)
                        .padding(.bottom, 140) // Position above tab bar
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientSheet(mode: .create) { _ in }
        }
        .sheet(isPresented: $showingCreateProject) {
            ProjectFormSheet(mode: .create) { _ in }
        }
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeSheet(mode: .create { _ in })
        }
        .sheet(isPresented: $showingCreateTask) {
            TaskFormSheet(mode: .create) { _ in }
        }
    }
}

