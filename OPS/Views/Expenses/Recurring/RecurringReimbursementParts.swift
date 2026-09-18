//
//  RecurringReimbursementParts.swift
//  OPS
//
//  Small shared pieces for recurring reimbursements: the neutral repeat mark
//  that stands where a receipt would, the person value type, and the option
//  list sheet behind every picker row.
//

import SwiftUI

// MARK: - Person

/// Someone a recurring reimbursement can be paid to.
struct RecurringPerson: Identifiable, Hashable {
    let id: String
    let name: String
}

extension RecurringPerson {
    /// Active teammates who can receive one, by name. The acting operator is
    /// left out unless they are an admin — the database refuses anyone else a
    /// reimbursement for themselves, so the choice is never offered.
    static func eligible(
        users: [User],
        companyId: String?,
        currentUserId: String?,
        currentUserIsAdmin: Bool
    ) -> [RecurringPerson] {
        let company = companyId?.lowercased()
        let me = currentUserId?.lowercased()
        var people: [RecurringPerson] = []
        var seen = Set<String>()
        for user in users {
            let id = user.id.lowercased()
            guard user.deletedAt == nil, user.isActive != false else { continue }
            guard let company, user.companyId?.lowercased() == company else { continue }
            guard currentUserIsAdmin || id != me else { continue }
            guard seen.insert(id).inserted else { continue }
            let name = displayName(first: user.firstName, last: user.lastName, email: user.email)
            people.append(RecurringPerson(id: user.id, name: name))
        }
        people.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return people
    }

    static func displayName(first: String?, last: String?, email: String?) -> String {
        let full = [first, last]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !full.isEmpty { return full }
        if let email, !email.isEmpty { return email }
        return "—"
    }
}

// MARK: - Mark

/// The neutral repeat mark a recurring line shows in place of a receipt — never
/// the missing-receipt alarm. Sized by the surface it sits in.
struct RecurringReimbursementMark: View {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = OPSStyle.Layout.smallCornerRadius
    var iconSize: CGFloat = OPSStyle.Layout.IconSize.sm

    var body: some View {
        Image(systemName: OPSStyle.Icons.recurring)
            .font(.system(size: iconSize, weight: .regular))
            .foregroundColor(OPSStyle.Colors.text3)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recurring reimbursement")
    }
}

// MARK: - Picker row

/// An input-row picker (MOBILE.md §9): label above, current value inside the
/// input chrome, trailing chevron. Tapping opens the option sheet.
struct RecurringPickerRow: View {
    let label: String
    let value: String?
    var placeholder: String = "Choose"
    /// Numbers and months render mono; names render in the body face.
    var mono: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(OPSStyle.Typography.trackingStandard)
                .textCase(.uppercase)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(value ?? placeholder)
                        .font(mono ? OPSStyle.Typography.cardSubtitle : OPSStyle.Typography.body)
                        .monospacedDigit()
                        .foregroundColor(value == nil ? OPSStyle.Colors.text3 : OPSStyle.Colors.text)
                        .lineLimit(1)
                    Spacer(minLength: OPSStyle.Layout.spacing2)
                    Image(systemName: OPSStyle.Icons.chevronDown)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.inputHeight)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(label)
            .accessibilityValue(value ?? placeholder)
        }
    }
}

// MARK: - Option sheet

/// Half sheet listing a picker's options — one tap chooses and closes.
struct RecurringOptionSheet: View {
    struct Option: Identifiable, Hashable {
        let id: String
        let label: String
    }

    let title: String
    let options: [Option]
    let selectedId: String?
    var mono: Bool = false
    /// Shown when there is nothing to choose.
    var emptyLabel: String = "NOTHING TO CHOOSE"
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                if options.isEmpty {
                    Text("// \(emptyLabel)")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(OPSStyle.Layout.emptyStatePadding)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(options) { option in
                                    optionRow(option)
                                        .id(option.id)
                                    if option.id != options.last?.id {
                                        Rectangle()
                                            .fill(OPSStyle.Colors.cardBorder)
                                            .frame(height: OPSStyle.Layout.Border.standard)
                                            .padding(.leading, OPSStyle.Layout.spacing3_5)
                                    }
                                }
                            }
                            .padding(.top, OPSStyle.Layout.spacing2)
                        }
                        .onAppear {
                            // Long month lists open on the current choice.
                            guard let selectedId else { return }
                            DispatchQueue.main.async {
                                proxy.scrollTo(selectedId, anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func optionRow(_ option: Option) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(option.id)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Text(option.label)
                    .font(mono ? OPSStyle.Typography.cardSubtitle : OPSStyle.Typography.body)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                if option.id == selectedId {
                    Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityAddTraits(option.id == selectedId ? .isSelected : [])
    }
}
