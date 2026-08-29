//
//  ProjectContactPickerSheet.swift
//  OPS
//
//  Bug 2c65fcb8 — point a job at one of the client's people, from the job.
//
//  The assignment already existed, but only inside the client screen: open the
//  client, expand a sub-contact row, tap USE FOR THIS PROJECT. That is the
//  right place to manage a person; it is the wrong place to answer "who is my
//  contact on THIS job." This sheet is that question, asked where it comes up —
//  behind the CLIENT row's long press on the project document, the same gesture
//  every other row on that document already uses.
//
//  The list is a radio choice, not a form: the client itself sits at the top as
//  "no specific contact" (which is what a nil selection means, and what an old
//  client-only job already is), then every active person under that client. One
//  tap commits and closes. No SAVE — there is nothing to compose.
//

import SwiftUI
import SwiftData

struct ProjectContactPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataController: DataController
    @ObservedObject private var permissionStore = PermissionStore.shared

    let project: Project

    /// The row currently committing, so it can show progress in place of its
    /// selection glyph. One row at a time: the list is a single choice.
    @State private var isSavingId: String?
    /// Sentinel for the client row, which has no sub-contact id of its own.
    private static let clientRowId = "__client__"
    @State private var errorMessage: String?

    /// Active people under this project's client, in name order. Deleted ones
    /// are gone from the choice entirely — `primaryProjectContact` already
    /// fails closed on them, so offering one would be offering a no-op.
    private var contacts: [SubClient] {
        (project.client?.subClients ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The same authority the client screen's assignment control gates on, so
    /// the two surfaces can never disagree about who may change this.
    private var canAssign: Bool {
        guard let userId = dataController.currentUser?.id
            ?? SupabaseService.shared.currentUserId
            ?? UserDefaults.standard.string(forKey: "currentUserId") else {
            return false
        }
        return permissionStore.canEditProject(project, userId: userId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if contacts.isEmpty {
                        EmptyStateView(
                            icon: OPSStyle.Icons.person,
                            title: "No sub-contacts yet",
                            message: "Add people on the client page. The client's own info covers this job until then."
                        )
                        .padding(.top, OPSStyle.Layout.spacing5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    } else {
                        contactList
                            .glassSurface()
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.top, OPSStyle.Layout.spacing3)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.top, OPSStyle.Layout.spacing2_5)
                    }
                }
            }
            .background(OPSStyle.Colors.background)
            .standardSheetToolbar(
                title: "Project Contact",
                actionText: "",
                isActionEnabled: false,
                onCancel: { dismiss() },
                onAction: {}
            )
        }
    }

    // MARK: - List

    private var contactList: some View {
        VStack(spacing: 0) {
            clientRow
            ForEach(contacts) { contact in
                rowDivider
                contactRow(contact)
            }
        }
    }

    /// Row zero — the client itself, meaning "no specific contact". Selecting
    /// it is how an assignment is cleared, so clearing needs no separate verb.
    private var clientRow: some View {
        row(
            id: Self.clientRowId,
            primary: project.effectiveClientName,
            secondary: "CLIENT INFO",
            isSelected: project.primarySubClientId == nil,
            accessibilityLabel: "Use the client's own contact information"
        ) {
            commit(nil)
        }
    }

    private func contactRow(_ contact: SubClient) -> some View {
        row(
            id: contact.id,
            primary: contact.name,
            secondary: contact.title,
            isSelected: project.primarySubClientId == contact.id,
            accessibilityLabel: "Use \(contact.name) as this project's contact"
        ) {
            commit(contact.id)
        }
    }

    /// One choice. The glyph is monochrome: this sheet has no primary action,
    /// and a checkmark marking the current state is not one.
    private func row(
        id: String,
        primary: String,
        secondary: String?,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(primary)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if let secondary, !secondary.isEmpty {
                        Text(secondary)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                if isSavingId == id {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if isSelected {
                    Image(systemName: OPSStyle.Icons.checkmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!canAssign || isSavingId != nil)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorderSubtle)
            .frame(height: 1)
            .padding(.leading, OPSStyle.Layout.spacing3)
    }

    // MARK: - Commit

    /// Tapping the current selection is a no-op that closes: the operator has
    /// confirmed what is already true, and a spinner for nothing is noise.
    private func commit(_ subClientId: String?) {
        guard canAssign, isSavingId == nil else { return }
        guard project.primarySubClientId != subClientId else {
            dismiss()
            return
        }

        isSavingId = subClientId ?? Self.clientRowId
        errorMessage = nil

        Task { @MainActor in
            do {
                try await dataController.updateProjectPrimaryContact(
                    project: project,
                    primarySubClientId: subClientId
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isSavingId = nil
                dismiss()
            } catch {
                // The same sentence the client screen uses for the same
                // failure — one message for one failure, everywhere.
                errorMessage = "Project contact was not changed. Check your connection and try again."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                isSavingId = nil
            }
        }
    }
}
