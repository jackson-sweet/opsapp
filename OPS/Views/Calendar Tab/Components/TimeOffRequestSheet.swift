//
//  TimeOffRequestSheet.swift
//  OPS
//
//  Bottom sheet for requesting time off — creates a pending time off event.
//

import SwiftUI

struct TimeOffRequestSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var reason: String = ""
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
                        // Amber info banner
                        HStack(spacing: 10) {
                            Image(systemName: "clock.badge.questionmark")
                                .foregroundColor(Color(red: 196/255, green: 168/255, blue: 104/255))
                            Text("Request will be sent to your admin for approval.")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(Color(red: 196/255, green: 168/255, blue: 104/255).opacity(0.85))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 196/255, green: 168/255, blue: 104/255).opacity(0.10))
                        .overlay(
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(Color(red: 196/255, green: 168/255, blue: 104/255).opacity(0.35)),
                            alignment: .bottom
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .padding(.top, 20)

                        // From date
                        sectionLabel("FROM")
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        // To date
                        sectionLabel("TO")
                        DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                        // Reason field
                        sectionLabel("REASON (OPTIONAL)")
                        TextField("", text: $reason)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .placeholder(when: reason.isEmpty) {
                                Text("ENTER REASON")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(14)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)

                        // Submit button (amber)
                        Button(action: submit) {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("SUBMIT REQUEST")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(.black)
                                }
                                Spacer()
                            }
                            .frame(height: 52)
                            .background(Color(red: 196/255, green: 168/255, blue: 104/255))
                            .cornerRadius(2)
                        }
                        .disabled(isSaving)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("[ REQUEST TIME OFF ]")
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
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.microLabel)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func submit() {
        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        isSaving = true

        let event = CalendarUserEvent(
            userId: userId,
            companyId: companyId,
            type: .timeOff,
            title: reason.isEmpty ? "Time Off Request" : reason,
            startDate: startDate,
            endDate: endDate,
            allDay: true,
            notes: reason.isEmpty ? nil : reason
        )
        event.status = CalendarUserEventStatus.pending.rawValue
        event.needsSync = true

        guard let context = dataController.modelContext else { isSaving = false; return }
        context.insert(event)
        try? context.save()

        Task {
            let repo = CalendarUserEventRepository(companyId: companyId)
            let iso = ISO8601DateFormatter()
            let dto = CreateCalendarUserEventDTO(
                userId: userId,
                companyId: companyId,
                type: "time_off",
                title: event.title,
                startDate: iso.string(from: startDate),
                endDate: iso.string(from: endDate),
                allDay: true,
                notes: reason.isEmpty ? nil : reason,
                status: "pending"
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
