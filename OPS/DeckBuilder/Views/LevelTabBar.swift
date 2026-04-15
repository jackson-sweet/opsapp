// OPS/OPS/DeckBuilder/Views/LevelTabBar.swift

import SwiftUI

struct LevelTabBar: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @State private var renamingIndex: Int?
    @State private var renameText: String = ""
    @State private var showDeleteError: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Level tabs
                ForEach(Array(viewModel.drawingData.levels.enumerated()), id: \.element.id) { index, level in
                    levelTab(level: level, index: index)
                }

                // Connect levels button (Add Level moved to toolbar)
                if viewModel.canConnectLevels {
                    Button {
                        viewModel.showingLevelConnectionSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(OPSStyle.Typography.smallCaption)
                            Text("Connect")
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(LevelColor.amber.swiftUIColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(LevelColor.amber.swiftUIColor.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: OPSStyle.Layout.touchTargetMin)
        .background(OPSStyle.Colors.cardBackground)
        .alert("Cannot Delete Level", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Remove stair connections to this level first.")
        }
        .alert("Rename Level", isPresented: Binding(
            get: { renamingIndex != nil },
            set: { if !$0 { renamingIndex = nil } }
        )) {
            TextField("Level name", text: $renameText)
            Button("Save") {
                if let index = renamingIndex {
                    viewModel.renameLevel(at: index, to: renameText)
                }
                renamingIndex = nil
            }
            Button("Cancel", role: .cancel) {
                renamingIndex = nil
            }
        }
    }

    // MARK: - Level Tab

    private func levelTab(level: DeckLevel, index: Int) -> some View {
        let isActive = index == viewModel.activeLevelIndex

        return Button {
            viewModel.switchToLevel(index)
        } label: {
            HStack(spacing: 6) {
                // Color dot
                Circle()
                    .fill(level.displayColor.swiftUIColor)
                    .frame(width: 8, height: 8)

                // Name
                Text(level.name)
                    .font(isActive ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.caption)
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)

                // Elevation badge
                if let elev = level.elevation {
                    Text(formatElevation(elev))
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing1)
                        .padding(.vertical, 2)
                        .background(OPSStyle.Colors.background.opacity(0.5))
                        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isActive ? OPSStyle.Colors.primaryAccent.opacity(0.15) : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                Rectangle()
                    .frame(height: 2)
                    .foregroundColor(isActive ? level.displayColor.swiftUIColor : .clear),
                alignment: .bottom
            )
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .contextMenu {
            Button {
                renameText = level.name
                renamingIndex = index
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                let success = viewModel.deleteLevel(at: index)
                if !success {
                    showDeleteError = true
                }
            } label: {
                Label("Delete Level", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func formatElevation(_ feet: Double) -> String {
        let wholeFeet = Int(feet)
        let inches = Int((feet - Double(wholeFeet)) * 12)
        if inches == 0 {
            return "\(wholeFeet)'"
        }
        return "\(wholeFeet)' \(inches)\""
    }
}
