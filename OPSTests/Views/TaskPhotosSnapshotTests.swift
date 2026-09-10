//
//  TaskPhotosSnapshotTests.swift
//  OPSTests
//
//  Bug a290934f — visual proof for the four surfaces a photo's task shows up on.
//
//  A rendering harness, not an assertion suite: every case writes a PNG and
//  passes. The behavioural assertions live in ProjectPhotoTaskIndexTests and
//  TaskScopedCaptureTests; these are the pictures a taste call needs.
//
//  PNGs land in `docs/artifacts/task-photos-20260908/` in the checkout this was
//  built from, so the proof sits with the branch instead of in a simulator's
//  temp directory. They are also attached to the result bundle.
//
//  Run:  xcodebuild test-without-building -scheme OPS \
//          -destination 'platform=iOS Simulator,id=<udid>' \
//          -only-testing:OPSTests/TaskPhotosSnapshotTests
//

#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class TaskPhotosSnapshotTests: XCTestCase {

    private let deckColor = Color(hex: "#59779F") ?? OPSStyle.Colors.primaryAccent
    private let railColor = Color(hex: "#9DB582") ?? OPSStyle.Colors.primaryAccent

    private func task(
        id: String,
        title: String,
        color: Color,
        status: TaskStatus = .active
    ) -> ProjectPhotoTask {
        ProjectPhotoTask(id: id, title: title, color: color, status: status)
    }

    // MARK: - Task Details › PHOTOS

    func testPhotosSectionEmpty() {
        snapshot("task-photos-section-empty", size: CGSize(width: 390, height: 160)) {
            card(count: nil) {
                Text("No photos yet")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func testPhotosSectionWithThreePhotos() {
        snapshot("task-photos-section-three", size: CGSize(width: 390, height: 200)) {
            card(count: 3) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(0..<3, id: \.self) { index in
                        self.tile(size: PhotoThumbnail.tileSize, index: index)
                    }
                }
            }
        }
    }

    // MARK: - Gallery tile carrying its task

    func testGalleryTilesCarryTheirTaskColour() {
        snapshot("task-photos-gallery-tiles", size: CGSize(width: 390, height: 140)) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("3 PHOTOS")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    galleryTile(index: 0, stripe: deckColor, faded: false)
                    galleryTile(index: 1, stripe: railColor, faded: true)
                    galleryTile(index: 2, stripe: nil, faded: false)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(OPSStyle.Colors.background)
        }
    }

    // MARK: - Pinned task note with its evidence

    func testPinnedTaskNoteCarriesACompactStrip() {
        snapshot("task-photos-pinned-note", size: CGSize(width: 390, height: 220)) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("PINNED")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: OPSStyle.Layout.Border.standard)
                    Text("TASK NOTES")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    TaskBadge(name: "Deck frame", color: deckColor, size: .small)
                    Spacer(minLength: 0)
                }

                Text("Watch the grade at the north corner — it drops two inches over the last span.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(0..<3, id: \.self) { index in
                        self.tile(size: OPSStyle.Layout.taskPhotoTileCompactSize, index: index)
                    }
                    self.overflowTile(count: 6, size: OPSStyle.Layout.taskPhotoTileCompactSize)
                    Spacer(minLength: 0)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface()
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(OPSStyle.Colors.background)
        }
    }

    // MARK: - Assign sheet

    func testAssignTaskSheet() {
        let tasks = [
            task(id: "task-1", title: "Deck frame", color: deckColor),
            task(id: "task-2", title: "Railing", color: railColor, status: .completed),
            task(id: "task-3", title: "Site cleanup", color: OPSStyle.Colors.primaryAccent)
        ]
        snapshot("task-photos-assign-sheet", size: CGSize(width: 390, height: 360)) {
            AssignTaskSheet(tasks: tasks, selectedTaskID: "task-1", onSelect: { _ in })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(OPSStyle.Colors.background)
        }
    }

    func testAssignTaskSheetWithNothingAssigned() {
        let tasks = [
            task(id: "task-1", title: "Deck frame", color: deckColor),
            task(id: "task-2", title: "Railing", color: railColor)
        ]
        snapshot("task-photos-assign-sheet-none", size: CGSize(width: 390, height: 300)) {
            AssignTaskSheet(tasks: tasks, selectedTaskID: nil, onSelect: { _ in })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(OPSStyle.Colors.background)
        }
    }

    // MARK: - Fixtures

    @ViewBuilder
    private func card<Content: View>(count: Int?, @ViewBuilder _ content: @escaping () -> Content) -> some View {
        SectionCard(
            icon: OPSStyle.Icons.photos,
            title: "Photos",
            count: count,
            actionIcon: OPSStyle.Icons.camera,
            actionLabel: "PHOTO",
            onAction: {}
        ) {
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OPSStyle.Colors.background)
    }

    /// A stand-in for a loaded photo. `PhotoThumbnail` fetches over the
    /// network, which a proof render must never depend on, so the shape and
    /// size are real and the pixels are a placeholder.
    private func tile(size: CGFloat, index: Int) -> some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .fill(OPSStyle.Colors.surfaceInput)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: OPSStyle.Icons.photo)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .accessibilityLabel("Photo \(index + 1)")
    }

    private func overflowTile(count: Int, size: CGFloat) -> some View {
        Text("+\(count)")
            .font(OPSStyle.Typography.captionBold)
            .monospacedDigit()
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func galleryTile(index: Int, stripe: Color?, faded: Bool) -> some View {
        tile(size: PhotoThumbnail.tileSize, index: index)
            .overlay(alignment: .bottom) {
                if let stripe {
                    Rectangle()
                        .fill(stripe)
                        .frame(height: OPSStyle.Layout.taskPhotoTileStripeHeight)
                        .opacity(faded ? OPSStyle.Layout.Opacity.faded : 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
    }

    // MARK: - Capture

    /// `docs/artifacts/task-photos-20260908/` in the checkout this test was
    /// built from — proof belongs with the branch, not in a simulator temp dir.
    private func outDir(from file: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: "\(file)")
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("OPS.xcodeproj").path) {
                let dir = url
                    .appendingPathComponent("docs", isDirectory: true)
                    .appendingPathComponent("artifacts", isDirectory: true)
                    .appendingPathComponent("task-photos-20260908", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            }
        }
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        do {
            let image = try FixedSizeSnapshot.render(content(), size: size)
            guard let data = image.pngData() else { return XCTFail("render \(name)") }
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "\(name).png"
            attachment.lifetime = .keepAlways
            add(attachment)
            let destination = outDir().appendingPathComponent("\(name).png")
            try data.write(to: destination)
            print("SNAPSHOT \(name) -> \(destination.path)")
        } catch {
            XCTFail("snapshot \(name) failed: \(error)")
        }
    }
}
#endif
