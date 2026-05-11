//
//  TaskTypeReminderEditorSheet.swift
//  OPS
//
//  Reminder template editor surfaces, attached to a TaskType:
//    - `TaskTypeReminderListSection`: embeddable VStack of existing templates
//      with edit + add affordances, intended to drop into TaskTypeDetailSheet.
//    - `TaskTypeReminderEditorSheet`: full-screen sheet for creating or
//      editing a single template.
//
//  See bug 4f00c2d7 + docs/superpowers/specs/2026-05-10-task-reminders-design.md.
//

import SwiftUI
import SwiftData

// MARK: - List section (embedded inside TaskTypeDetailSheet)

struct TaskTypeReminderListSection: View {
    let taskType: TaskType
    @Environment(\.modelContext) private var modelContext

    /// Locally-tracked templates keyed by taskTypeId. Hydrated from the
    /// SwiftData relationship and refreshed after each create/edit/delete.
    @Query private var allTemplates: [TaskTypeReminder]

    @State private var editorState: EditorState? = nil
    @State private var isSubmitting = false
    @State private var error: String? = nil

    /// `EditorState` discriminates between "new for this task type" and
    /// "edit existing." We use a single optional state property so the
    /// sheet binding can drive both flows.
    enum EditorState: Identifiable {
        case create(taskTypeId: String, companyId: String, nextDisplayOrder: Int)
        case edit(template: TaskTypeReminder)

        var id: String {
            switch self {
            case .create(let id, _, _): return "create-\(id)"
            case .edit(let template):   return "edit-\(template.id)"
            }
        }
    }

    init(taskType: TaskType) {
        self.taskType = taskType
        let id = taskType.id
        _allTemplates = Query(
            filter: #Predicate<TaskTypeReminder> {
                $0.taskTypeId == id && $0.deletedAt == nil
            },
            sort: \.displayOrder
        )
    }

    private var templates: [TaskTypeReminder] {
        allTemplates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Image(systemName: "bell.badge")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("REMINDERS")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    editorState = .create(
                        taskTypeId: taskType.id,
                        companyId: taskType.companyId,
                        nextDisplayOrder: (templates.map(\.displayOrder).max() ?? -1) + 1
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: OPSStyle.Icons.plus)
                            .font(.system(size: 12, weight: .semibold))
                        Text("ADD")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .frame(height: OPSStyle.Layout.touchTargetMin)
            }

            if templates.isEmpty {
                Text("// no reminder templates")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(templates) { template in
                        TemplateRow(template: template) {
                            editorState = .edit(template: template)
                        } delete: {
                            Task { await delete(template: template) }
                        }
                    }
                }
            }

            if let error = error {
                Text(error)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
            }
        }
        .sheet(item: $editorState) { state in
            TaskTypeReminderEditorSheet(state: state) { saved in
                editorState = nil
                if let saved = saved { handleSaved(saved) }
            }
        }
    }

    @MainActor
    private func handleSaved(_ saved: TaskTypeReminderDTO) {
        // Hydrate local SwiftData row from the saved server DTO.
        let id = saved.id
        let descriptor = FetchDescriptor<TaskTypeReminder>(predicate: #Predicate { $0.id == id })
        if let existing = try? modelContext.fetch(descriptor).first {
            saved.apply(to: existing)
        } else {
            modelContext.insert(saved.makeLocalRow())
        }
        try? modelContext.save()
    }

    @MainActor
    private func delete(template: TaskTypeReminder) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        do {
            try await TaskReminderRepository.shared.softDeleteTemplate(id: template.id)
            template.deletedAt = Date()
            template.needsSync = false
            try modelContext.save()
        } catch {
            self.error = "Couldn't delete reminder. Try again."
        }
    }

    private struct TemplateRow: View {
        let template: TaskTypeReminder
        let edit: () -> Void
        let delete: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.label.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(template.leadTimeDisplay.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("//")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text(template.requiresAck ? "CONFIRM" : "NO-ACK")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(template.requiresAck ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                        Text("//")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text(template.recipientMode.displayLabel)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                Spacer()
                Menu {
                    Button { edit() } label: {
                        Label("Edit", systemImage: OPSStyle.Icons.pencil)
                    }
                    Button(role: .destructive) { delete() } label: {
                        Label("Delete", systemImage: OPSStyle.Icons.trash)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .contentShape(Rectangle())
            .onTapGesture { edit() }
        }
    }
}

// MARK: - Editor sheet (create / edit a single template)

struct TaskTypeReminderEditorSheet: View {
    let state: TaskTypeReminderListSection.EditorState
    let onClose: (TaskTypeReminderDTO?) -> Void

    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var label: String = ""
    @State private var leadTimeDays: Int = 1
    @State private var fireTime: Date = TaskTypeReminderEditorSheet.defaultFireTime()
    @State private var requiresAck: Bool = true
    @State private var recipientMode: ReminderRecipientMode = .taskCrew
    @State private var permissionKey: String = ""
    @State private var userIdsCSV: String = ""

    @State private var isSubmitting = false
    @State private var error: String? = nil

    private static func defaultFireTime() -> Date {
        Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    }

    private var headerTitle: String {
        switch state {
        case .create: return "NEW REMINDER"
        case .edit:   return "EDIT REMINDER"
        }
    }

    private var isValid: Bool {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard leadTimeDays >= 0, leadTimeDays <= 90 else { return false }
        switch recipientMode {
        case .permission:
            return !permissionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .users:
            return !parsedUserIds.isEmpty
        case .taskCrew, .admins:
            return true
        }
    }

    private var parsedUserIds: [String] {
        userIdsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        labelField
                        leadTimeField
                        fireTimeField
                        ackField
                        recipientField
                        if let error = error {
                            Text(error)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle(headerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { onClose(nil) }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await save() } }) {
                        if isSubmitting {
                            ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        } else {
                            Text("SAVE")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
            .onAppear(perform: loadInitialState)
        }
    }

    // MARK: - Fields

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LABEL")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField("e.g. Order vinyl", text: $label)
                .textInputAutocapitalization(.sentences)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private var leadTimeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LEAD TIME")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            HStack(spacing: 8) {
                ForEach([1, 2, 3, 7, 14], id: \.self) { days in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        leadTimeDays = days
                    } label: {
                        Text(presetLabel(days))
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(leadTimeDays == days ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(leadTimeDays == days ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            }
            Stepper("\(leadTimeDays) day\(leadTimeDays == 1 ? "" : "s") before", value: $leadTimeDays, in: 0...90)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private func presetLabel(_ days: Int) -> String {
        switch days {
        case 1:  return "1D"
        case 2:  return "2D"
        case 3:  return "3D"
        case 7:  return "1W"
        case 14: return "2W"
        default: return "\(days)D"
        }
    }

    private var fireTimeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FIRE TIME")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            DatePicker("", selection: $fireTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .padding(OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private var ackField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACKNOWLEDGEMENT")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Toggle(isOn: $requiresAck) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require checkmark")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(requiresAck ? "Stays in rail until ticked" : "Informational ping, dismissible")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .tint(OPSStyle.Colors.primaryAccent)
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private var recipientField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECIPIENTS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Picker("Recipient mode", selection: $recipientMode) {
                ForEach(ReminderRecipientMode.allCases, id: \.self) { mode in
                    Text(mode.displayLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch recipientMode {
            case .taskCrew:
                Text("// fires for everyone on the task")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            case .admins:
                Text("// fires for company admins")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            case .permission:
                TextField("e.g. inventory.manage", text: $permissionKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                Text("// anyone with this permission key gets the reminder")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            case .users:
                TextField("user-id-1, user-id-2", text: $userIdsCSV)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                Text("// comma-separated user ids; web-side picker coming")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }

    // MARK: - Behaviors

    private func loadInitialState() {
        switch state {
        case .create:
            label = ""
            leadTimeDays = 1
            fireTime = TaskTypeReminderEditorSheet.defaultFireTime()
            requiresAck = true
            recipientMode = .taskCrew
            permissionKey = ""
            userIdsCSV = ""
        case .edit(let template):
            label = template.label
            leadTimeDays = template.leadTimeDays
            fireTime = template.fireTimeOfDay
            requiresAck = template.requiresAck
            recipientMode = template.recipientMode
            permissionKey = template.recipientConfig.permission ?? ""
            userIdsCSV = (template.recipientConfig.userIds ?? []).joined(separator: ", ")
        }
    }

    @MainActor
    private func save() async {
        guard isValid else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        defer { isSubmitting = false }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: fireTime)
        let fireSeconds = (comps.hour ?? 9) * 3600 + (comps.minute ?? 0) * 60

        let config: ReminderRecipientConfig
        switch recipientMode {
        case .taskCrew, .admins:
            config = ReminderRecipientConfig.empty
        case .permission:
            config = ReminderRecipientConfig(permission: permissionKey.trimmingCharacters(in: .whitespacesAndNewlines), userIds: nil)
        case .users:
            config = ReminderRecipientConfig(permission: nil, userIds: parsedUserIds)
        }

        do {
            switch state {
            case .create(let taskTypeId, let companyId, let nextOrder):
                let temp = TaskTypeReminder(
                    id: UUID().uuidString,
                    taskTypeId: taskTypeId,
                    companyId: companyId,
                    label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                    leadTimeDays: leadTimeDays,
                    fireTimeLocalSeconds: fireSeconds,
                    requiresAck: requiresAck,
                    recipientMode: recipientMode,
                    recipientConfig: config,
                    displayOrder: nextOrder
                )
                let payload = CreateTaskTypeReminderDTO(from: temp)
                let saved = try await TaskReminderRepository.shared.createTemplate(payload)
                onClose(saved)

            case .edit(let template):
                template.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
                template.leadTimeDays = leadTimeDays
                template.fireTimeLocalSeconds = fireSeconds
                template.requiresAck = requiresAck
                template.recipientMode = recipientMode
                template.recipientConfig = config
                let payload = UpdateTaskTypeReminderDTO(from: template)
                let saved = try await TaskReminderRepository.shared.updateTemplate(id: template.id, payload: payload)
                onClose(saved)
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = "Couldn't save. Try again."
        }
    }
}
