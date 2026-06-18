//
//  PersonalEventSheet.swift
//  OPS
//
//  Bottom sheet for creating a personal calendar event.
//

import SwiftUI

struct PersonalEventSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel

    @State private var title: String = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var allDay: Bool = true
    @State private var notes: String = ""
    @State private var address: String = ""
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var showingTeamPicker: Bool = false
    @State private var isSaving: Bool = false

    init(isPresented: Binding<Bool>, viewModel: CalendarViewModel) {
        _isPresented = isPresented
        self.viewModel = viewModel
        _startDate = State(initialValue: viewModel.selectedDate)
        _endDate = State(initialValue: viewModel.selectedDate)
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title field
                        sectionLabel("EVENT TITLE")
                        TextField("", text: $title)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .placeholder(when: title.isEmpty) {
                                Text("TITLE")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(14)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing3_5)

                        // All day toggle
                        sectionLabel("ALL DAY")
                        Toggle("", isOn: $allDay)
                            .tint(OPSStyle.Colors.text)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing3_5)

                        // Start date
                        sectionLabel("START")
                        DatePicker(
                            "",
                            selection: $startDate,
                            displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing2_5)

                        // End date
                        sectionLabel("END")
                        DatePicker(
                            "",
                            selection: $endDate,
                            in: startDate...,
                            displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing3_5)

                        // Address
                        sectionLabel("ADDRESS (OPTIONAL)")
                        TextField("", text: $address)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .placeholder(when: address.isEmpty) {
                                Text("ADDRESS")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(14)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing3_5)

                        // Team assignment
                        sectionLabel("TEAM (OPTIONAL)")
                        Button(action: { showingTeamPicker = true }) {
                            HStack {
                                if selectedTeamMemberIds.isEmpty {
                                    Text("ASSIGN TEAM MEMBERS")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                } else {
                                    Text("\(selectedTeamMemberIds.count) MEMBER\(selectedTeamMemberIds.count == 1 ? "" : "S") ASSIGNED")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(14)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing3_5)

                        // Notes
                        sectionLabel("NOTES (OPTIONAL)")
                        TextEditor(text: $notes)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(minHeight: 80)
                            .padding(10)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing5)

                        // Save button
                        Button(action: save) {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("SAVE EVENT")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(.black)
                                }
                                Spacer()
                            }
                            .frame(height: 52)
                            .background(OPSStyle.Colors.primaryText)
                            .cornerRadius(OPSStyle.Layout.progressBarRadius)
                        }
                        .disabled(title.isEmpty || isSaving)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    }
                    .padding(.top, OPSStyle.Layout.spacing3_5)
                }
            }
            .navigationTitle("[ PERSONAL EVENT ]")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { isPresented = false }
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .colorScheme(.dark)
        .sheet(isPresented: $showingTeamPicker) {
            if let companyId = dataController.currentUser?.companyId {
                // Use full User objects so the picker renders real profile photos.
                let members = dataController.getTeamMembers(companyId: companyId)
                    .sorted { $0.fullName < $1.fullName }
                TeamMemberPickerSheet(
                    selectedTeamMemberIds: $selectedTeamMemberIds,
                    allTeamMembers: members
                )
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.microLabel)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 6)
    }

    private func save() {
        guard !isSaving else { return }
        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        isSaving = true

        let teamIds = selectedTeamMemberIds.isEmpty ? nil : Array(selectedTeamMemberIds)
        let event = CalendarUserEvent(
            userId: userId,
            companyId: companyId,
            type: .personal,
            title: title,
            startDate: startDate,
            endDate: endDate,
            allDay: allDay,
            notes: notes.isEmpty ? nil : notes,
            address: address.isEmpty ? nil : address,
            teamMemberIds: teamIds
        )
        event.needsSync = true

        guard let context = dataController.modelContext else { isSaving = false; return }
        context.insert(event)
        try? context.save()

        // Sync to Supabase in background
        Task {
            let repo = CalendarUserEventRepository(companyId: companyId)
            let iso = ISO8601DateFormatter()
            let dto = CreateCalendarUserEventDTO(
                userId: userId,
                companyId: companyId,
                type: "personal",
                title: title,
                startDate: iso.string(from: startDate),
                endDate: iso.string(from: endDate),
                allDay: allDay,
                notes: notes.isEmpty ? nil : notes,
                status: "none",
                address: address.isEmpty ? nil : address,
                teamMemberIds: teamIds
            )
            if let saved = try? await repo.create(dto) {
                await MainActor.run {
                    event.id = saved.id
                    event.needsSync = false
                    event.lastSyncedAt = Date()
                    try? context.save()
                }
            }
            await MainActor.run {
                isSaving = false
                viewModel.loadUserEvents()
                isPresented = false
            }
        }
    }
}
