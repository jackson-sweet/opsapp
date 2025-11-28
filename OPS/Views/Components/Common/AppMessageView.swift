//
//  AppMessageView.swift
//  OPS
//
//  Full-screen overlay for displaying app messages
//  Supports update notices, maintenance alerts, and announcements
//

import SwiftUI

struct AppMessageView: View {
    let message: AppMessageDTO
    let onDismiss: (() -> Void)?

    @State private var containerOpacity: Double = 0

    private var messageType: AppMessageType {
        guard let typeString = message.messageType else { return .info }
        return AppMessageType(rawValue: typeString) ?? .info
    }

    private var isDismissable: Bool {
        message.dismissable ?? true
    }

    private var hasAppStoreUrl: Bool {
        guard let url = message.appStoreUrl, !url.isEmpty else { return false }
        return true
    }

    private var accentColor: Color {
        switch messageType {
        case .mandatoryUpdate:
            return OPSStyle.Colors.errorStatus
        case .optionalUpdate:
            return OPSStyle.Colors.primaryAccent
        case .maintenance:
            return OPSStyle.Colors.warningStatus
        case .announcement:
            return OPSStyle.Colors.primaryAccent
        case .info:
            return OPSStyle.Colors.secondaryText
        }
    }

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Content Card
                VStack(alignment: .leading, spacing: 20) {
                    // Callout at top
                    Text("[ \(messageType.displayName.uppercased()) ]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(accentColor.opacity(0.7))
                        .tracking(1)

                    // Header with icon inline
                    HStack(spacing: 10) {
                        Image(systemName: messageType.iconName)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(accentColor)

                        if let title = message.title, !title.isEmpty {
                            Text(title.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .tracking(2)
                        }
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 1)

                    // Body - left aligned
                    if let body = message.body, !body.isEmpty {
                        Text(body)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Decorative loading bar for blocked state
                    if !isDismissable && !hasAppStoreUrl {
                        TacticalLoadingBarAnimated(
                            barCount: 6,
                            barWidth: 2,
                            barHeight: 6,
                            spacing: 4,
                            emptyColor: OPSStyle.Colors.inputFieldBorder,
                            fillColor: accentColor.opacity(0.6)
                        )
                        .padding(.top, 8)
                    }

                    // Action area inside card
                    VStack(spacing: 0) {
                        // Divider above button
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.top, 8)
                            .padding(.bottom, 20)

                        if isDismissable {
                            Button(action: {
                                dismissWithAnimation()
                            }) {
                                Text("DISMISS")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .tracking(2)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            }
                        } else if hasAppStoreUrl {
                            Button(action: {
                                openAppStore()
                            }) {
                                Text("UPDATE NOW")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(accentColor)
                                    .tracking(2)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            }
                        } else {
                            Text("[ ACCESS SUSPENDED ]")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.5))
                                .tracking(2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)

                Spacer()
            }
        }
        .opacity(containerOpacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) {
                containerOpacity = 1.0
            }
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            containerOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onDismiss?()
        }
    }

    private func openAppStore() {
        guard let urlString = message.appStoreUrl,
              let url = URL(string: urlString) else {
            return
        }

        UIApplication.shared.open(url)
    }
}

// MARK: - Previews

#Preview("Mandatory Update") {
    AppMessageView(
        message: AppMessageDTO.preview(
            title: "Update Required",
            body: "A critical update is available. Please update to continue using OPS.",
            messageType: "mandatory_update",
            dismissable: false,
            appStoreUrl: "https://apps.apple.com"
        ),
        onDismiss: nil
    )
}

#Preview("Optional Update") {
    AppMessageView(
        message: AppMessageDTO.preview(
            title: "Update Available",
            body: "A new version of OPS is available with bug fixes and improvements.",
            messageType: "optional_update",
            dismissable: true,
            appStoreUrl: nil
        ),
        onDismiss: {}
    )
}

#Preview("Maintenance") {
    AppMessageView(
        message: AppMessageDTO.preview(
            title: "Scheduled Maintenance",
            body: "OPS will be undergoing maintenance on Sunday from 2-4 AM EST. Some features may be unavailable.",
            messageType: "maintenance",
            dismissable: true,
            appStoreUrl: nil
        ),
        onDismiss: {}
    )
}

#Preview("Announcement") {
    AppMessageView(
        message: AppMessageDTO.preview(
            title: "New Feature",
            body: "Check out the new calendar view! Swipe left and right to navigate between weeks.",
            messageType: "announcement",
            dismissable: true,
            appStoreUrl: nil
        ),
        onDismiss: {}
    )
}

#Preview("Blocked - No URL") {
    AppMessageView(
        message: AppMessageDTO.preview(
            title: "App Unavailable",
            body: "This version of OPS is no longer supported.",
            messageType: "mandatory_update",
            dismissable: false,
            appStoreUrl: nil
        ),
        onDismiss: nil
    )
}

// MARK: - Preview Helper

extension AppMessageDTO {
    static func preview(
        title: String,
        body: String,
        messageType: String,
        dismissable: Bool,
        appStoreUrl: String?
    ) -> AppMessageDTO {
        // Create a mock DTO for previews
        let json: [String: Any] = [
            "_id": "preview_\(UUID().uuidString)",
            "active": true,
            "title": title,
            "body": body,
            "messageType": messageType,
            "dismissable": dismissable,
            "appStoreUrl": appStoreUrl as Any,
            "targetUserTypes": [],
            "Created Date": "2025-01-01T00:00:00.000Z"
        ]

        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(AppMessageDTO.self, from: data)
    }
}
