// OPS/OPS/DeckBuilder/Views/LevelTabBar.swift

import SwiftUI

struct LevelTabBar: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @State private var renamingIndex: Int?
    @State private var renameText: String = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                // Level tabs
                ForEach(Array(viewModel.drawingData.levels.enumerated()), id: \.element.id) { index, level in
                    levelTab(level: level, index: index)
                }

                // No CONNECT button. It opened the stair sheet with no edge
                // chosen — a second door into the same flow that dropped the
                // operator on a picker instead of the stairs they asked for,
                // and that nothing on the canvas explained. Stairs are added
                // where they exist: tap the edge (bug 2f717747).

                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        }
        .frame(height: OPSStyle.Layout.touchTargetMin)
        // No solid background — the bar lives inside the title overlay's
        // shared card so the parent's translucent fill shows through.
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
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(isActive ? OPSStyle.Colors.surfaceActive : Color.clear)
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
                    ToastCenter.shared.present(Toast(label: Feedback.Err.connectionsPreventDelete, tone: .error))
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
