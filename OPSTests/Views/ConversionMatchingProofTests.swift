//
//  ConversionMatchingProofTests.swift
//  OPSTests
//
//  Visual proof pack for the WS-B conversion + matching cluster:
//  4cbf2efe (won toast → blank project sheet), a7df1f37 (convert form ignores
//  the linked client), 5468b3c6 / ced5b3cb (matching dead ends and the badge
//  that navigated instead of linking), a3c4e216 (no project-side lead match).
//
//  Renders every state the fixes introduce. A rendering harness, not an
//  assertion suite — the behavioural contracts are pinned by
//  ProjectCacheMergeTests, ConvertSheetPrefillTests, ConvertSheetMatchingTests
//  and ProjectLeadRowTests.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/ConversionMatchingProofTests
//  Shots land in NSTemporaryDirectory()/ops-conversion-matching-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class ConversionMatchingProofTests: XCTestCase {

    private let frameSize = CGSize(width: 393, height: 300)

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-conversion-matching-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, view: V, size: CGSize? = nil) {
        let renderSize = size ?? frameSize
        let image: UIImage
        do {
            image = try FixedSizeSnapshot.render(
                view.background(OPSStyle.Colors.background),
                size: renderSize
            )
        } catch {
            XCTFail("Could not acquire the app host window for \(name): \(error)")
            return
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))px)")
    }

    // MARK: - a3c4e216 — project-side LEAD row

    // The row in isolation. In production it is a row of the project-info card,
    // which draws the hairline above it — see DetailsTabSnapshotTests for the
    // in-card renders. These three capture the row's own states.

    /// The project knows its lead: name + chevron, opens the lead.
    func testRenderProjectLeadRowLinked() {
        snapshot(
            "project_lead_row_linked",
            view: ProjectLeadSection(
                presentation: .linked(label: "Holland Ave rear deck"),
                onOpenLead: {},
                onMatchLead: {}
            ),
            size: CGSize(width: 393, height: 90)
        )
    }

    /// Unlinked with candidates: the once-ever action, sized like the fact it
    /// is — not a glass card.
    func testRenderProjectLeadRowMatch() {
        snapshot(
            "project_lead_row_match",
            view: ProjectLeadSection(
                presentation: .match(candidateCount: 2),
                onOpenLead: {},
                onMatchLead: {}
            ),
            size: CGSize(width: 393, height: 90)
        )
    }

    /// Nothing to match — the row is absent, not an em dash and not a disabled
    /// button. Captured to prove the surface stays clean; in the card,
    /// `shows(.lead)` drops the hairline with it.
    func testRenderProjectLeadRowHidden() {
        snapshot(
            "project_lead_row_hidden",
            view: VStack(spacing: 0) {
                ProjectLeadSection(
                    presentation: .hidden,
                    onOpenLead: {},
                    onMatchLead: {}
                )
                Text("[ ADDRESS ]")
                    .font(OPSStyle.Typography.smallCaption)
                    .tracking(1)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            },
            size: CGSize(width: 393, height: 90)
        )
    }

    // MARK: - 4cbf2efe — the project sheet's honest states

    /// The tokened loading state that replaced the untokened system-font
    /// "Loading project details..." stub.
    func testRenderProjectSheetResolving() {
        snapshot(
            "project_sheet_resolving",
            view: ProjectSheetStateProof.resolving,
            size: CGSize(width: 393, height: 320)
        )
    }

    /// The failure state the old stub never had: it dismissed itself after a
    /// second and ate the operator's tap.
    func testRenderProjectSheetUnreachable() {
        snapshot(
            "project_sheet_unreachable",
            view: ProjectSheetStateProof.unreachable,
            size: CGSize(width: 393, height: 320)
        )
    }

    // MARK: - ced5b3cb — the peek that replaced dismiss-and-navigate

    /// Peeking at a same-address project that already belongs to another lead.
    /// Layered over the convert sheet; the conversion is untouched behind it.
    func testRenderProjectPeekLinkedElsewhere() {
        snapshot(
            "project_peek_linked_elsewhere",
            view: ProjectPeekSheet(
                projectId: "project-a",
                fallbackTitle: "1240 Maple Ave",
                fallbackAddress: "1240 Maple Ave, Victoria BC",
                linkNote: "Same address as this lead, but already linked to a different lead. It cannot be matched until that link is resolved.",
                companyId: "company-1",
                onOpenProject: { _ in }
            ),
            size: CGSize(width: 393, height: 560)
        )
    }

    /// Peeking at a matchable candidate — the QUICK VIEW control on a chip the
    /// operator is about to select.
    func testRenderProjectPeekMatchable() {
        snapshot(
            "project_peek_matchable",
            view: ProjectPeekSheet(
                projectId: "project-b",
                fallbackTitle: "3998 Holland Ave",
                fallbackAddress: "3998 Holland Ave, Victoria BC",
                linkNote: "Same address as this lead. Selecting it links the lead to this project instead of creating a new one.",
                companyId: "company-1",
                onOpenProject: { _ in }
            ),
            size: CGSize(width: 393, height: 560)
        )
    }
}

/// Standalone copies of the project sheet's two non-content states. The real
/// states live inside a private resolver whose phase is driven by
/// DataController; reproducing the markup here keeps the proof honest about
/// what renders without dragging a live container into the harness.
private enum ProjectSheetStateProof {

    static var resolving: some View {
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
        .background(OPSStyle.Colors.background)
    }

    static var unreachable: some View {
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
                Text("RETRY")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(1.2)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                Text("CLOSE")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(1.2)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background)
    }
}
#endif
