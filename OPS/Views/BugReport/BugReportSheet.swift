//
//  BugReportSheet.swift
//  OPS
//
//  Minimal bug report sheet presented on device shake.
//  Screenshot preview, description, category, submit.
//

import SwiftUI

struct BugReportSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var dataController: DataController

    let screenshot: UIImage?
    /// Closes the report. Supplied by BugReportPresenter, which owns the
    /// dedicated overlay window — SwiftUI's `\.dismiss` does not drive a
    /// UIKit-presented hosting controller, so we close explicitly.
    let onClose: () -> Void

    @State private var description: String = ""
    @State private var selectedCategory: BugCategory = .bug
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?
    @State private var showFullScreenshot: Bool = false
    @State private var submitSuccess: Bool = false
    @State private var screenshotDragOffset: CGFloat = 0

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
                    Button("Cancel") {
                        onClose()
                    }
                    .font(OPSStyle.Typography.body)
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

    private func screenshotPreview(_ image: UIImage) -> some View {
        Button {
            showFullScreenshot = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("Screenshot captured")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("Tap to enlarge")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing2)
            .glassSurface()
        }
        .buttonStyle(.plain)
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
            Text(category.displayName)
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
                    Text("Submit Report")
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
        ZStack {
            Color.black.ignoresSafeArea()

            if let screenshot = screenshot {
                Image(uiImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: screenshotDragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Only allow downward drag
                                if value.translation.height > 0 {
                                    screenshotDragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 120 {
                                    showFullScreenshot = false
                                }
                                withAnimation(OPSStyle.Animation.spring) {
                                    screenshotDragOffset = 0
                                }
                            }
                    )
            }

            // Close button — top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullScreenshot = false
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: OPSStyle.Icons.xmark)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .bold))
                            Text("Close")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.overlayMedium)
                        .clipShape(Capsule())
                    }
                    .padding(.top, OPSStyle.Layout.spacing5 + OPSStyle.Layout.spacing4)
                    .padding(.trailing, OPSStyle.Layout.spacing3)
                }
                Spacer()
            }
        }
        .opacity(1.0 - Double(screenshotDragOffset) / 400.0)
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.successStatus)

            Text("Report submitted")
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
