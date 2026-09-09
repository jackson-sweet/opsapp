//
//  BugReportSheet.swift
//  OPS
//
//  Minimal bug report sheet presented on device shake.
//  Screenshot preview, description, category, submit.
//
//  POINT AT IT (bug 5aabcc3a): one optional tap that says WHERE. The operator
//  opens the captured shot, taps the spot, and a ring lands on it; the report
//  then carries `custom_metadata.element` — the coordinates plus whatever the
//  frozen view hierarchy could name there. Skippable, no new screen, and the
//  ring is the sheet's one accent element.
//

import SwiftUI
import UIKit

struct BugReportSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var dataController: DataController

    /// The screen at trigger time: the picture, and the view hierarchy behind
    /// it that POINT AT IT resolves a tap against.
    let capture: BugReportCaptureService.AppWindowCapture?
    /// Closes the report. Supplied by BugReportPresenter, which owns the
    /// dedicated overlay window — SwiftUI's `\.dismiss` does not drive a
    /// UIKit-presented hosting controller, so we close explicitly.
    let onClose: () -> Void

    private var screenshot: UIImage? { capture?.screenshot }

    @State private var description: String = ""
    @State private var selectedCategory: BugCategory = .bug
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?
    @State private var showFullScreenshot: Bool = false
    @State private var submitSuccess: Bool = false
    /// The spot the operator pointed at, if they did.
    @State private var elementMark: BugReportElementMark?
    /// True while the full-screen shot is waiting for that tap.
    @State private var isPointing: Bool = false

    /// Snapshot/preview seam — a preseeded mark renders the marked state
    /// without driving a tap. Production callers omit both.
    init(
        capture: BugReportCaptureService.AppWindowCapture?,
        onClose: @escaping () -> Void,
        initialElementMark: BugReportElementMark? = nil,
        initialPointing: Bool = false
    ) {
        self.capture = capture
        self.onClose = onClose
        _elementMark = State(initialValue: initialElementMark)
        _isPointing = State(initialValue: initialPointing)
        _showFullScreenshot = State(initialValue: initialPointing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        // Screenshot preview
                        if let screenshot = screenshot {
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
    /// makes it precise. The thumbnail enlarges; POINT AT IT opens the same
    /// full-screen shot armed for a single tap (bug 5aabcc3a).
    private func screenshotPreview(_ image: UIImage) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                isPointing = false
                showFullScreenshot = true
            } label: {
                thumbnail(image)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enlarge the captured screenshot")

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(elementMark == nil ? "SCREENSHOT CAPTURED" : "SPOT MARKED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                if let name = markedElementName {
                    Text(name)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
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
            ZStack {
                // Fit, not fill: a cropped thumbnail would put the ring on the
                // wrong feature, and "where on the screen" is the whole point.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)

                if let mark = elementMark {
                    let rect = BugReportElementHitTest.fittedRect(
                        imageSize: image.size,
                        in: geo.size
                    )
                    markRing(diameter: 14, lineWidth: 1.5)
                        .position(
                            x: rect.minX + mark.normalized.x * rect.width,
                            y: rect.minY + mark.normalized.y * rect.height
                        )
                }
            }
        }
        .frame(width: 80, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    /// One control, two states: arm the tap, or clear the mark it produced.
    private var pointerControl: some View {
        Button {
            if elementMark == nil {
                isPointing = true
                showFullScreenshot = true
            } else {
                withAnimation(OPSStyle.Animation.fast) { elementMark = nil }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(elementMark == nil ? "POINT AT IT" : "CLEAR")
                .font(OPSStyle.Typography.captionBold)
                .tracking(0.5)
                .foregroundColor(
                    elementMark == nil
                        ? OPSStyle.Colors.primaryAccent
                        : OPSStyle.Colors.secondaryText
                )
                .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// What the frozen hierarchy could name at the marked point — the label
    /// first, then the identifier, then the view class. Nil when it named
    /// nothing; the coordinates alone still ship.
    private var markedElementName: String? {
        guard let mark = elementMark else { return nil }
        let name = mark.label ?? mark.identifier ?? mark.viewType
        return name.map { $0.uppercased() }
    }

    /// The one accent element on this sheet. The dark halo underneath keeps it
    /// legible when the mark lands on a filled accent control.
    private func markRing(diameter: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(OPSStyle.Colors.background.opacity(0.6), lineWidth: lineWidth * 2.5)
                .frame(width: diameter, height: diameter)
            Circle()
                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)
            Circle()
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: lineWidth * 2, height: lineWidth * 2)
        }
    }

    // MARK: - Description Field

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("DESCRIPTION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextEditor(text: $description)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.surfaceInput)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if description.isEmpty {
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
                selectedCategory = category
            }
        } label: {
            Text(category.displayName.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(selectedCategory == category ? OPSStyle.Colors.buttonText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                .frame(maxWidth: .infinity)
                .background(
                    selectedCategory == category
                        ? OPSStyle.Colors.primaryAccent
                        : OPSStyle.Colors.surfaceInput
                )
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            selectedCategory == category
                                ? Color.clear
                                : OPSStyle.Colors.cardBorder,
                            lineWidth: 1
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
        .background(OPSStyle.Colors.errorStatus.opacity(0.1))
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
            .background((description.isEmpty || submitSuccess) ? OPSStyle.Colors.primaryAccent.opacity(0.4) : OPSStyle.Colors.primaryAccent)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
        }
        .disabled(description.isEmpty || isSubmitting || submitSuccess)
        .buttonStyle(.plain)
    }

    // MARK: - Full Screen Screenshot

    private var fullScreenScreenshotView: some View {
        BugReportScreenshotViewer(
            image: screenshot,
            mark: elementMark,
            isPointing: isPointing,
            onPlace: { normalized in place(normalized: normalized) },
            onClose: {
                isPointing = false
                showFullScreenshot = false
            }
        )
    }

    /// Resolve one placed tap against the frozen hierarchy and close.
    private func place(normalized: CGPoint) {
        guard let capture else { return }
        elementMark = BugReportElementHitTest.mark(
            atNormalized: normalized,
            windowSize: capture.size,
            candidates: capture.elements
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isPointing = false
        showFullScreenshot = false
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
        guard !description.isEmpty else { return }

        isSubmitting = true
        submitError = nil

        Task {
            do {
                try await BugReportSubmissionService.shared.submitReport(
                    description: description,
                    category: selectedCategory.rawValue,
                    screenshot: screenshot,
                    element: elementMark,
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
