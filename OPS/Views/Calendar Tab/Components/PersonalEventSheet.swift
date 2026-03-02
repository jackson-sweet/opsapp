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
                            .font(.custom("Mohave-Regular", size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .placeholder(when: title.isEmpty) {
                                Text("TITLE")
                                    .font(.custom("Mohave-Regular", size: 16))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(14)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                        // All day toggle
                        sectionLabel("ALL DAY")
                        Toggle("", isOn: $allDay)
                            .tint(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                        // Start date
                        sectionLabel("START")
                        DatePicker(
                            "",
                            selection: $startDate,
                            displayedComponents: allDay ? [.date] : [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

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
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                        // Notes
                        sectionLabel("NOTES (OPTIONAL)")
                        TextEditor(text: $notes)
                            .font(.custom("Mohave-Regular", size: 15))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(minHeight: 80)
                            .padding(10)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)

                        // Save button
                        Button(action: save) {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("SAVE EVENT")
                                        .font(.custom("Kosugi-Regular", size: 14))
                                        .foregroundColor(.black)
                                }
                                Spacer()
                            }
                            .frame(height: 52)
                            .background(OPSStyle.Colors.primaryText)
                            .cornerRadius(2)
                        }
                        .disabled(title.isEmpty || isSaving)
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("[ PERSONAL EVENT ]")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { isPresented = false }
                        .font(.custom("Kosugi-Regular", size: 13))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .colorScheme(.dark)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.custom("Kosugi-Regular", size: 11))
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func save() {
        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        isSaving = true

        let event = CalendarUserEvent(
            userId: userId,
            companyId: companyId,
            type: .personal,
            title: title,
            startDate: startDate,
            endDate: endDate,
            allDay: allDay,
            notes: notes.isEmpty ? nil : notes
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
                status: "none"
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
