//
//  AppointmentReviewRowSnapshotTests.swift
//  OPSTests
//
//  Visual proof for bug 74bbb5b7 — the appointment-review row before and after:
//  a generic "Confirm the appointment details before booking." that named
//  nobody, versus a row that names the customer, says what is missing, and
//  offers the one remedy a phone has.
//
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult --output-path <dir>
//

#if DEBUG
import XCTest
import SwiftUI
@testable import OPS

@MainActor
final class AppointmentReviewRowSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 390
    private let leadId = "9c137fe0-a1e1-4945-b248-00141ce89fc8"

    private func snapshot<V: View>(
        _ name: String,
        height: CGFloat,
        @ViewBuilder content: () -> V
    ) throws {
        let image = try FixedSizeSnapshot.render(
            content()
                .frame(width: deviceWidth, alignment: .top)
                .background(OPSStyle.Colors.background)
                .environment(\.colorScheme, .dark),
            size: CGSize(width: deviceWidth, height: height)
        )
        guard let data = image.pngData() else {
            return XCTFail("Failed to render \(name)")
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("SNAPSHOT \(name) (\(Int(image.size.width))x\(Int(image.size.height))pt)")
    }

    /// The founder's row, exactly as prod emits it.
    private func reviewRow(body: String = "Confirm the appointment details before booking.") -> NotificationDTO {
        NotificationDTO(
            id: "6f67484a-53b2-4115-9273-5d9b09411914",
            userId: "user-1",
            companyId: "company-1",
            type: "phase_c_appointment_review",
            title: "Appointment needs review",
            body: body,
            projectId: nil,
            noteId: nil,
            expenseId: nil,
            batchId: nil,
            deepLinkType: "lead",
            actionUrl: "/pipeline?opportunityId=\(leadId)",
            actionLabel: "REVIEW",
            persistent: true,
            dedupeKey: "phase-c-bilateral:v1:83ede0eb-62b4-4691-af08-4657a7d6826f:review",
            resolvedAt: nil,
            resolvedBy: nil,
            resolutionReason: nil,
            isRead: false,
            createdAt: "2026-09-08T15:45:19.243188+00:00"
        )
    }

    private func row(
        body: String = "Confirm the appointment details before booking.",
        leadName: String? = "Angela Wall",
        expanded: Bool,
        canSetTime: Bool = true
    ) -> some View {
        AppointmentReviewRow(
            notification: reviewRow(body: body),
            leadName: leadName,
            timestamp: "1d",
            isExpanded: expanded,
            canSetTime: canSetTime,
            onToggle: {},
            onSetTime: {}
        )
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    /// What the founder actually saw: the type says review, the body says
    /// nothing about who, and the only button opens the lead.
    func testBeforeGenericRow() throws {
        try snapshot("appointment-review-before", height: 130) {
            NotificationRowChrome(
                title: "Appointment needs review",
                bodyText: Text("Confirm the appointment details before booking.")
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundStyle(OPSStyle.Colors.secondaryText),
                bodyAccessibilityLabel: "",
                timestamp: "1d",
                isRead: false,
                isExpanded: false,
                onToggle: {},
                icon: {
                    NotificationIconBadge(
                        systemName: "calendar.badge.exclamationmark",
                        tint: OPSStyle.Colors.warningStatus
                    )
                },
                detail: { EmptyView() }
            )
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    func testCollapsedNamesTheCustomer() throws {
        try snapshot("appointment-review-collapsed", height: 130) {
            row(expanded: false)
        }
    }

    func testExpandedOffersSetTheTime() throws {
        try snapshot("appointment-review-expanded", height: 260) {
            row(expanded: true)
        }
    }

    /// The one reason the server names outright.
    func testExpandedTimeVariant() throws {
        try snapshot("appointment-review-expanded-time", height: 260) {
            row(body: "Confirm the appointment time before booking.", expanded: true)
        }
    }

    /// No lead on the row, or a lead this device has never synced: the sentence
    /// drops the name and the action disappears rather than going nowhere.
    func testExpandedWithoutALead() throws {
        try snapshot("appointment-review-expanded-no-lead", height: 220) {
            row(leadName: nil, expanded: true, canSetTime: false)
        }
    }
}
#endif
