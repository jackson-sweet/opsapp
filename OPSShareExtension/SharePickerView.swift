//
//  SharePickerView.swift
//  OPSShareExtension
//
//  The "Add to OPS" picker. A searchable, single-select list of the projects
//  the signed-in user may attach photos to, with a fixed bottom CTA. State-aware:
//  shows a signed-out / no-permission / no-projects message instead of an empty
//  list. Styled entirely from ShareTheme (OPS military-tactical minimalist).
//

import SwiftUI

/// What the picker should render, resolved from the session bridge.
enum SharePickerContent {
    case ready([ShareProjectRef])
    case noSession
    case noPermission
    case noProjects
    case noImages
}

/// Drives the picker. The view observes it; the host view controller flips
/// `phase` to `.done` once capture completes, then dismisses.
@MainActor
final class SharePickerModel: ObservableObject {
    enum Phase { case picking, submitting, done }

    @Published var phase: Phase = .picking
    @Published var confirmedTitle: String = ""

    let content: SharePickerContent
    let photoCount: Int
    var onConfirm: ((ShareProjectRef) -> Void)?
    var onCancel: (() -> Void)?

    init(content: SharePickerContent, photoCount: Int) {
        self.content = content
        self.photoCount = photoCount
    }
}

struct SharePickerView: View {
    @ObservedObject var model: SharePickerModel
    @State private var search = ""
    @State private var selectedId: String?

    var body: some View {
        ZStack {
            ShareTheme.Color.background.ignoresSafeArea()

            if model.phase == .done {
                successView
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    header
                    Divider().background(ShareTheme.Color.line)
                    contentBody
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            VStack(spacing: ShareTheme.Spacing.s1) {
                Text("ADD TO PROJECT")
                    .font(ShareTheme.Font.title(20))
                    .foregroundColor(ShareTheme.Color.textPrimary)
                if model.photoCount > 0 {
                    Text(photoCountLabel.uppercased())
                        .font(ShareTheme.Font.monoMedium(11))
                        .foregroundColor(ShareTheme.Color.textTertiary)
                }
            }
            HStack {
                Button { model.onCancel?() } label: {
                    Text("Cancel")
                        .font(ShareTheme.Font.body(15))
                        .foregroundColor(ShareTheme.Color.textSecondary)
                        .frame(minWidth: ShareTheme.Size.touchMin, minHeight: ShareTheme.Size.touchMin, alignment: .leading)
                }
                Spacer()
            }
        }
        .padding(.horizontal, ShareTheme.Spacing.s3)
        .padding(.top, ShareTheme.Spacing.s2)
        .padding(.bottom, ShareTheme.Spacing.s2_5)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentBody: some View {
        switch model.content {
        case .ready(let projects):
            readyBody(projects)
        case .noSession:
            messageView(
                icon: "person.crop.circle.badge.exclamationmark",
                title: "Sign in to OPS",
                message: "open OPS to sign in, then share again"
            )
        case .noPermission:
            messageView(
                icon: "lock",
                title: "No access",
                message: "you don't have permission to add photos"
            )
        case .noProjects:
            messageView(
                icon: "folder",
                title: "No projects yet",
                message: "projects you can add photos to show up here"
            )
        case .noImages:
            messageView(
                icon: "photo",
                title: "No photos",
                message: "nothing here to add"
            )
        }
    }

    private func readyBody(_ projects: [ShareProjectRef]) -> some View {
        let visible = filtered(projects)
        return VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, ShareTheme.Spacing.s3)
                .padding(.vertical, ShareTheme.Spacing.s2_5)

            if visible.isEmpty {
                Spacer()
                Text("[no match]")
                    .font(ShareTheme.Font.mono(13))
                    .foregroundColor(ShareTheme.Color.textTertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { project in
                            ProjectRow(
                                project: project,
                                selected: selectedId == project.id
                            ) {
                                ShareHaptics.selection()
                                selectedId = project.id
                            }
                        }
                    }
                }
            }

            ctaBar(projects)
        }
        .disabled(model.phase != .picking)
    }

    private var searchBar: some View {
        HStack(spacing: ShareTheme.Spacing.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(ShareTheme.Color.textTertiary)
            TextField(
                "",
                text: $search,
                prompt: Text("Search projects").foregroundColor(ShareTheme.Color.textTertiary)
            )
            .font(ShareTheme.Font.body())
            .foregroundColor(ShareTheme.Color.textPrimary)
            .tint(ShareTheme.Color.accent)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(ShareTheme.Color.textTertiary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, ShareTheme.Spacing.s2_5)
        .background(ShareTheme.Color.surfaceInput)
        .cornerRadius(ShareTheme.Radius.button)
        .overlay(
            RoundedRectangle(cornerRadius: ShareTheme.Radius.button)
                .stroke(ShareTheme.Color.line, lineWidth: 1)
        )
    }

    private func ctaBar(_ projects: [ShareProjectRef]) -> some View {
        VStack(spacing: 0) {
            Divider().background(ShareTheme.Color.line)
            Button {
                guard let id = selectedId,
                      let project = projects.first(where: { $0.id == id }) else { return }
                ShareHaptics.commit()
                model.phase = .submitting
                model.onConfirm?(project)
            } label: {
                HStack(spacing: ShareTheme.Spacing.s2) {
                    if model.phase == .submitting {
                        ProgressView().tint(ShareTheme.Color.accent)
                    }
                    Text(ctaLabel)
                        .font(ShareTheme.Font.buttonLabel())
                        .textCase(.uppercase)
                }
            }
            .buttonStyle(SharePrimaryButtonStyle(enabled: selectedId != nil && model.phase == .picking))
            .disabled(selectedId == nil || model.phase != .picking)
            .padding(.horizontal, ShareTheme.Spacing.s3)
            .padding(.vertical, ShareTheme.Spacing.s2_5)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: ShareTheme.Spacing.s3) {
            ZStack {
                Circle()
                    .fill(ShareTheme.Color.success.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(ShareTheme.Color.success)
            }
            Text(model.photoCount == 1 ? "PHOTO ADDED" : "PHOTOS ADDED")
                .font(ShareTheme.Font.title(24))
                .foregroundColor(ShareTheme.Color.textPrimary)
            Text("[\(model.photoCount) → \(model.confirmedTitle)]")
                .font(ShareTheme.Font.mono(13))
                .foregroundColor(ShareTheme.Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ShareTheme.Spacing.s4)
        }
    }

    // MARK: - Message (empty/blocked states)

    private func messageView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: ShareTheme.Spacing.s2) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(ShareTheme.Color.textMute)
                .padding(.bottom, ShareTheme.Spacing.s2)
            Text(title.uppercased())
                .font(ShareTheme.Font.title(18))
                .foregroundColor(ShareTheme.Color.textPrimary)
            Text("[\(message)]")
                .font(ShareTheme.Font.mono(13))
                .foregroundColor(ShareTheme.Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ShareTheme.Spacing.s4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var photoCountLabel: String {
        model.photoCount == 1 ? "1 photo" : "\(model.photoCount) photos"
    }

    private var ctaLabel: String {
        model.photoCount == 1 ? "Add photo" : "Add \(model.photoCount) photos"
    }

    private func filtered(_ projects: [ShareProjectRef]) -> [ShareProjectRef] {
        guard !search.isEmpty else { return projects }
        let q = search.lowercased()
        return projects.filter {
            $0.title.lowercased().contains(q) || ($0.clientName?.lowercased().contains(q) ?? false)
        }
    }
}

// MARK: - Row

private struct ProjectRow: View {
    let project: ShareProjectRef
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ShareTheme.Spacing.s2_5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title)
                        .font(ShareTheme.Font.bodyBold())
                        .foregroundColor(ShareTheme.Color.textPrimary)
                        .lineLimit(1)
                    if let client = project.clientName, !client.isEmpty {
                        Text(client)
                            .font(ShareTheme.Font.mono(12))
                            .foregroundColor(ShareTheme.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: ShareTheme.Spacing.s2)
                ZStack {
                    Circle()
                        .stroke(selected ? ShareTheme.Color.accent : ShareTheme.Color.line, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ShareTheme.Color.accent)
                    }
                }
            }
            .padding(.horizontal, ShareTheme.Spacing.s3)
            .frame(minHeight: ShareTheme.Size.touchStandard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? ShareTheme.Color.surfaceActive : Color.clear)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(ShareTheme.Color.line),
                alignment: .bottom
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary button (mirrors OPSButtonStyle.Primary)

private struct SharePrimaryButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(minHeight: ShareTheme.Size.cta)
            .foregroundColor(foreground(pressed: configuration.isPressed))
            .background(background(pressed: configuration.isPressed))
            .cornerRadius(ShareTheme.Radius.button)
            .overlay(
                RoundedRectangle(cornerRadius: ShareTheme.Radius.button)
                    .stroke(enabled ? ShareTheme.Color.accent : ShareTheme.Color.line, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private func foreground(pressed: Bool) -> Color {
        guard enabled else { return ShareTheme.Color.textMute }
        return pressed ? .black : ShareTheme.Color.accent
    }

    private func background(pressed: Bool) -> Color {
        guard enabled else { return .clear }
        return pressed ? ShareTheme.Color.accent : .clear
    }
}
