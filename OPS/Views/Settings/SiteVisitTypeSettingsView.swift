//
//  SiteVisitTypeSettingsView.swift
//  OPS
//
//  Company-wide reusable site-visit checklist administration.
//

import SwiftData
import SwiftUI
import UIKit

struct SiteVisitTypeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Query private var allTypes: [SiteVisitType]

    @State private var editorDraft: SiteVisitTypeDraft?
    @State private var errorMessage: String?

    private var companyId: String {
        dataController.currentUser?.companyId?.lowercased() ?? ""
    }

    private var types: [SiteVisitType] {
        allTypes
            .filter {
                $0.companyId.lowercased() == companyId && $0.deletedAt == nil
            }
            .sorted {
                if $0.sortOrder == $1.sortOrder { return $0.name < $1.name }
                return $0.sortOrder < $1.sortOrder
            }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Site Visit Types",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, OPSStyle.Layout.spacing2)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            Text("// COMPANY CHECKLISTS")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Text("Changes apply to future visits. Existing visit records stay unchanged.")
                                .font(OPSStyle.Typography.smallBody)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        VStack(spacing: 0) {
                            if types.isEmpty {
                                Text("NO VISIT TYPES")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                            } else {
                                ForEach(Array(types.enumerated()), id: \.element.id) { index, type in
                                    typeRow(type)
                                    if index < types.count - 1 { separator }
                                }
                                separator
                            }
                            createRow
                        }
                        .glassSurface()
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                }
            }
        }
        .navigationBarHidden(true)
        .trackScreen("Settings.SiteVisitTypes")
        .task { seedAndRefresh() }
        .onReceive(NotificationCenter.default.publisher(for: .siteVisitTypesChanged)) { _ in
            // @Query owns the refresh. This receiver keeps the view subscribed
            // to mutations arriving through realtime while the cover is open.
        }
        .sheet(item: $editorDraft) { draft in
            NavigationStack {
                SiteVisitTypeEditorView(draft: draft)
                    .environmentObject(dataController)
            }
        }
        .errorToast($errorMessage, label: Feedback.Err.operationFailed)
    }

    private func typeRow(_ type: SiteVisitType) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editorDraft = SiteVisitTypeDraft(type: type)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(
                    systemName: type.isSystemTemplate
                        ? OPSStyle.Icons.checklist
                        : OPSStyle.Icons.listBullet
                )
                    .font(.system(
                        size: OPSStyle.Layout.IconSize.md,
                        weight: .medium
                    ))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(type.name.uppercased())
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        if type.isDefault {
                            Text("DEFAULT")
                                .font(OPSStyle.Typography.miniLabel)
                                .foregroundColor(OPSStyle.Colors.tanTextM)
                        }
                    }

                    let visibleCount = type.fields.filter(\.isShown).count
                    Text("\(visibleCount) FIELD\(visibleCount == 1 ? "" : "S") SHOWN")
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(type.name) checklist")
    }

    private var createRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editorDraft = .blank
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: OPSStyle.Icons.plus)
                    .font(.system(
                        size: OPSStyle.Layout.IconSize.sm,
                        weight: .semibold
                    ))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: OPSStyle.Layout.touchTargetMin)
                Text("NEW VISIT TYPE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var separator: some View {
        OPSStyle.Colors.separator
            .frame(height: OPSStyle.Layout.Border.standard)
            .padding(.leading, OPSStyle.Layout.spacing5)
    }

    private func seedAndRefresh() {
        do {
            _ = try dataController.ensureSiteVisitTypesSeeded(
                deckBuilderEnabled: PermissionStore.shared.isFeatureEnabled("deck_builder")
            )
            Task { await dataController.refreshSiteVisitTypes() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SiteVisitTypeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var draft: SiteVisitTypeDraft
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var isSaving = false

    init(draft: SiteVisitTypeDraft) {
        _draft = State(initialValue: draft)
    }

    private var canonicalFieldIds: Set<String> {
        guard draft.isSystemTemplate, let slug = draft.slug else { return [] }
        let companyId = dataController.currentUser?.companyId ?? ""
        return Set(
            SiteVisitType.builtInTemplates(
                companyId: companyId,
                deckBuilderEnabled: true
            )
            .first(where: { $0.slug == slug })?
            .fields.map(\.id) ?? []
        )
    }

    private var canSave: Bool {
        !isSaving
            && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.fields.contains(where: \.isShown)
            && draft.fields.allSatisfy {
                !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                OPSScreenHeader(
                    draft.id == nil ? "NEW VISIT TYPE" : "EDIT VISIT TYPE",
                    leading: { OPSHeaderCloseButton(action: { dismiss() }) },
                    trailing: {
                        Button(action: save) {
                            Text("SAVE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(
                                    canSave
                                        ? OPSStyle.Colors.invertedText
                                        : OPSStyle.Colors.tertiaryText
                                )
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: OPSStyle.Layout.buttonRadius,
                                        style: .continuous
                                    )
                                    .fill(
                                        canSave
                                            ? OPSStyle.Colors.primaryAccent
                                            : OPSStyle.Colors.surfaceHover
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                    }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        identitySection
                        fieldsSection
                        if draft.id != nil && !draft.isSystemTemplate {
                            deleteSection
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarHidden(true)
        .confirmationDialog(
            "DELETE THIS VISIT TYPE?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("DELETE VISIT TYPE", role: .destructive, action: deleteType)
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("Existing visit records stay unchanged.")
        }
        .errorToast($errorMessage, label: Feedback.Err.operationFailed)
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionLabel("VISIT TYPE")

            VStack(spacing: OPSStyle.Layout.spacing2) {
                TextField("NAME", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .disabled(draft.isSystemTemplate)
                    .opsFieldStyle()

                TextField(
                    "DESCRIPTION",
                    text: $draft.descriptionText,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .disabled(draft.isSystemTemplate)
                .opsFieldStyle()

                if !draft.isDefault {
                    Button {
                        draft.isDefault = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text("MAKE DEFAULT")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Spacer()
                            Image(systemName: OPSStyle.Icons.checkmarkCircle)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Text("DEFAULT VISIT TYPE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tanTextM)
                        Spacer()
                        Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                            .foregroundColor(OPSStyle.Colors.tanTextM)
                    }
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface()
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                sectionLabel("CHECKLIST FIELDS")
                Spacer()
                Text("\(draft.fields.filter(\.isShown).count) SHOWN")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            if draft.fields.isEmpty {
                Text("ADD THE FIRST FIELD TO BUILD THIS CHECKLIST")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard)
                    .glassSurface()
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(Array(draft.fields.indices), id: \.self) { index in
                        fieldCard(index: index)
                    }
                }
            }

            Button(action: addField) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.plus)
                    Text("ADD FIELD")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                    .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        OPSStyle.Colors.cardBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func fieldCard(index: Int) -> some View {
        let locked = canonicalFieldIds.contains(draft.fields[index].id)
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("FIELD \(index + 1)")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                reorderButton(icon: OPSStyle.Icons.chevronUp, index: index, offset: -1)
                reorderButton(icon: OPSStyle.Icons.chevronDown, index: index, offset: 1)
                if !locked {
                    Button {
                        draft.fields.remove(at: index)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: OPSStyle.Icons.trash)
                            .foregroundColor(OPSStyle.Colors.roseTextM)
                            .frame(
                                width: OPSStyle.Layout.touchTargetMin,
                                height: OPSStyle.Layout.touchTargetMin
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove field \(index + 1)")
                }
            }

            TextField(
                "FIELD LABEL",
                text: Binding(
                    get: { draft.fields[index].label },
                    set: { draft.fields[index].label = $0 }
                )
            )
            .disabled(locked)
            .opsFieldStyle()

            Menu {
                ForEach(SiteVisitFieldKind.settingsChoices, id: \.self) { kind in
                    Button(kind.settingsName) {
                        draft.fields[index].kind = kind
                    }
                }
            } label: {
                HStack {
                    Text(draft.fields[index].kind.settingsName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                    Image(systemName: OPSStyle.Icons.sort)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                    .fill(OPSStyle.Colors.surfaceInput)
                )
            }
            .disabled(locked)

            Toggle(
                "SHOWN ON SITE VISITS",
                isOn: Binding(
                    get: { draft.fields[index].isShown },
                    set: {
                        draft.fields[index].isVisible = $0
                        if !$0 { draft.fields[index].required = false }
                    }
                )
            )
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .tint(OPSStyle.Colors.primaryAccent)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)

            Toggle(
                "REQUIRED",
                isOn: Binding(
                    get: { draft.fields[index].required },
                    set: { draft.fields[index].required = $0 }
                )
            )
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .tint(OPSStyle.Colors.primaryAccent)
            .disabled(!draft.fields[index].isShown)
            .opacity(draft.fields[index].isShown ? 1 : 0.5)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private func reorderButton(icon: String, index: Int, offset: Int) -> some View {
        let target = index + offset
        let enabled = draft.fields.indices.contains(target)
        return Button {
            guard enabled else { return }
            draft.fields.swapAt(index, target)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: icon)
                .foregroundColor(
                    enabled
                        ? OPSStyle.Colors.secondaryText
                        : OPSStyle.Colors.tertiaryText
                )
                .frame(
                    width: OPSStyle.Layout.touchTargetMin,
                    height: OPSStyle.Layout.touchTargetMin
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var deleteSection: some View {
        Button {
            showingDeleteConfirmation = true
        } label: {
            Text("DELETE VISIT TYPE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.roseTextM)
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                    .fill(OPSStyle.Colors.roseSoft)
                )
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.secondaryText)
    }

    private func addField() {
        guard draft.fields.count < SiteVisitTypeSettingsLogic.maximumFieldCount else {
            errorMessage = SiteVisitTypeSettingsError.fieldLimitReached.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        draft.fields.append(
            SiteVisitTypeFieldDefinition(
                label: "",
                kind: .shortText,
                sortOrder: (draft.fields.count + 1) * 10
            )
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try dataController.saveSiteVisitType(draft)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    private func deleteType() {
        guard let id = draft.id else { return }
        do {
            try dataController.deleteSiteVisitType(id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}

private extension SiteVisitFieldKind {
    static var settingsChoices: [SiteVisitFieldKind] {
        [.checkbox, .yesNoNA, .shortText, .longText, .measurement, .photo, .photoMarkup]
    }

    var settingsName: String {
        switch self {
        case .checkbox: return "Checkbox"
        case .yesNoNA: return "Yes / No / N/A"
        case .shortText: return "Short answer"
        case .longText: return "Long answer"
        case .measurement: return "Measurement"
        case .photo: return "Photo"
        case .photoMarkup: return "Photo + markup"
        case .deckDesign: return "Deck design"
        }
    }
}

private extension View {
    func opsFieldStyle() -> some View {
        self
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(
                    cornerRadius: OPSStyle.Layout.buttonRadius,
                    style: .continuous
                )
                .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: OPSStyle.Layout.buttonRadius,
                    style: .continuous
                )
                .strokeBorder(
                    OPSStyle.Colors.cardBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
            )
    }
}
