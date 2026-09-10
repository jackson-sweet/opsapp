//
//  BugReportSheet.swift
//  OPS
//
//  Minimal bug report sheet presented on device shake.
//  Screenshot preview, description, category, submit.
//
//  POINT AT IT (bug 14e5a792, rebuilt from 5aabcc3a): one optional step that
//  says WHAT. The sheet steps aside, the operator picks the problem on the
//  live app, and the sheet comes back with the element named and outlined on
//  a fresh screenshot. Everything typed survives the round trip because it
//  lives in `BugReportDraft`, which the presenter owns.
//

import SwiftUI
import UIKit

struct BugReportSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var dataController: DataController

    /// Description, category, screenshot and mark — owned by the presenter so
    /// they outlive the sheet stepping aside for POINT AT IT.
    @ObservedObject var draft: BugReportDraft
    /// Closes the report. Supplied by BugReportPresenter, which owns the
    /// dedicated overlay window — SwiftUI's `\.dismiss` does not drive a
    /// UIKit-presented hosting controller, so we close explicitly.
    let onClose: () -> Void
    /// Steps the sheet aside for a pick on the live app.
    let onPointAtIt: () -> Void

    @State private var isSubmitting: Bool = false
    @State private var submitError: String?
    @State private var showFullScreenshot: Bool = false
    @State private var submitSuccess: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        // Screenshot preview
                        if let screenshot = draft.screenshot {
                            screenshotPreview(screenshot)
                        }

                        // Description
                        descriptionField

                        // Category picker
                        categoryPicker

                        // Error message
                        if let error = submitError {
                            errorBanner(error)
                        }

                        // Submit button
                        submitButton
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Report a Bug")
                        .font(OPSStyle.Typography.pageTitle)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") {
                        onClose()
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .fullScreenCover(isPresented: $showFullScreenshot) {
                fullScreenScreenshotView
            }
            .overlay {
                if submitSuccess {
                    successOverlay
                }
            }
        }
    }

    // MARK: - Screenshot Preview

    /// Evidence card: the shot, what it shows, and the one optional step that
    /// makes it precise. The thumbnail enlarges; POINT AT IT steps the sheet
    /// aside so the operator can pick the problem on the live app.
    private func screenshotPreview(_ image: UIImage) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                showFullScreenshot = true
            } label: {
                thumbnail(image)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                draft.element == nil
                    ? "Enlarge the captured screenshot"
                    : "Enlarge the screenshot with the marked element"
            )

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(draft.element == nil ? "SCREENSHOT CAPTURED" : "SPOT MARKED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                if let element = draft.element {
                    Text(element.resolution.cardText)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                pointerControl
            }

            Spacer(minLength: 0)
        }
        .padding(OPSStyle.Layout.spacing2)
        .glassSurface()
    }

    private func thumbnail(_ image: UIImage) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Fit, not fill: a cropped thumbnail would put the outline on
                // the wrong feature, and "which thing" is the whole point.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)

                if let element = draft.element {
                    BugReportMarkOutline(
                        element: element,
                        imageSize: image.size,
                        container: geo.size
                    )
                }
            }
        }
        .frame(width: 80, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    /// One control, two states: pick on the live app, or clear the pick and
    /// go back to the shot the report was triggered with. White, not accent —
    /// SUBMIT REPORT is this sheet's call to action; this is an optional step.
    private var pointerControl: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if draft.element == nil {
                onPointAtIt()
            } else {
                withAnimation(OPSStyle.Animation.fast) { draft.clearMark() }
            }
        } label: {
            Text(draft.element == nil ? "POINT AT IT" : "CLEAR")
                .font(OPSStyle.Typography.captionBold)
                .tracking(OPSStyle.Typography.trackingCompact)
                .foregroundColor(
                    draft.element == nil
                        ? OPSStyle.Colors.text
                        : OPSStyle.Colors.secondaryText
                )
                .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting || submitSuccess)
        .accessibilityLabel(
            draft.element == nil
                ? "Point at it. Pick the problem on the screen"
                : "Clear the marked element"
        )
    }

    // MARK: - Description Field

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("DESCRIPTION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextEditor(text: $draft.description)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.surfaceInput)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .overlay(alignment: .topLeading) {
                    if draft.description.isEmpty {
                        Text("What went wrong?")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.placeholderText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .padding(.vertical, OPSStyle.Layout.spacing2 + 8) // TextEditor internal padding
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("CATEGORY")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack(spacing: OPSStyle.Layout.spacing1) {
                ForEach(BugCategory.allCases, id: \.self) { category in
                    categoryButton(category)
                }
            }
        }
    }

    private func categoryButton(_ category: BugCategory) -> some View {
        Button {
            withAnimation(OPSStyle.Animation.fast) {
                draft.category = category
            }
        } label: {
            Text(category.displayName.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(draft.category == category ? OPSStyle.Colors.buttonText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                .frame(maxWidth: .infinity)
                .background(
                    draft.category == category
                        ? OPSStyle.Colors.primaryAccent
                        : OPSStyle.Colors.surfaceInput
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            draft.category == category
                                ? Color.clear
                                : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(OPSStyle.Colors.errorStatus)
            Text(message)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.errorStatus)
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.errorStatus.opacity(OPSStyle.Layout.Opacity.subtle))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            submitReport()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if isSubmitting {
                    ProgressView()
                        .tint(OPSStyle.Colors.buttonText)
                } else {
                    Image(systemName: "paperplane.fill")
                    Text("SUBMIT REPORT")
                }
            }
            .font(OPSStyle.Typography.button)
            .foregroundColor(OPSStyle.Colors.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetMin)
            .background((draft.description.isEmpty || submitSuccess) ? OPSStyle.Colors.primaryAccent.opacity(OPSStyle.Layout.suspendedOpacity) : OPSStyle.Colors.primaryAccent)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
        }
        .disabled(draft.description.isEmpty || isSubmitting || submitSuccess)
        .buttonStyle(.plain)
    }

    // MARK: - Full Screen Screenshot

    private var fullScreenScreenshotView: some View {
        BugReportScreenshotViewer(
            image: draft.screenshot,
            element: draft.element,
            onClose: { showFullScreenshot = false }
        )
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.successStatus)

            Text("REPORT SAVED")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background.opacity(0.9))
        .transition(.opacity)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            onClose()
        }
    }

    // MARK: - Submit Action

    private func submitReport() {
        guard !draft.description.isEmpty else { return }

        isSubmitting = true
        submitError = nil

        Task {
            do {
                try await BugReportSubmissionService.shared.submitReport(
                    description: draft.description,
                    category: draft.category.rawValue,
                    screenshot: draft.screenshot,
                    element: draft.element,
                    appState: appState,
                    dataController: dataController
                )

                withAnimation(OPSStyle.Animation.standard) {
                    submitSuccess = true
                }
            } catch {
                submitError = error.localizedDescription
            }

            isSubmitting = false
        }
    }
}

// MARK: - Bug Category

enum BugCategory: String, CaseIterable {
    case bug = "bug"
    case uiIssue = "ui_issue"
    case crash = "crash"
    case featureRequest = "feature_request"
    case other = "other"

    var displayName: String {
        switch self {
        case .bug: return "Bug"
        case .uiIssue: return "UI"
        case .crash: return "Crash"
        case .featureRequest: return "Feature"
        case .other: return "Other"
        }
    }
}
