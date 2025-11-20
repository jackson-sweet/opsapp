//
//  NotificationSettingsControls.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import SwiftUI

struct NotificationTimeWindow: View {
    @Binding var startHour: Int
    @Binding var endHour: Int
    var title: String
    var description: String
    
    private let hours = Array(0...23)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            HStack(spacing: 8) {
                // Start time picker
                HStack {
                    Text("From:")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Picker("", selection: $startHour) {
                        ForEach(hours, id: \.self) { hour in
                            Text("\(formatHour(hour))")
                                .tag(hour)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                    .cornerRadius(8)
                }
                
                // End time picker
                HStack {
                    Text("To:")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Picker("", selection: $endHour) {
                        ForEach(hours, id: \.self) { hour in
                            Text("\(formatHour(hour))")
                                .tag(hour)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                    .cornerRadius(8)
                }
            }
            
            // Preview of selected time window
            Text("You will receive notifications between \(formatHour(startHour)) and \(formatHour(endHour))")
                .font(.system(size: 13))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.top, 4)
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
    
    private func formatHour(_ hour: Int) -> String {
        let hourString = hour == 0 ? "12" : hour > 12 ? "\(hour - 12)" : "\(hour)"
        let amPm = hour >= 12 ? "PM" : "AM"
        return "\(hourString) \(amPm)"
    }
}

struct NotificationPrioritySelector: View {
    @Binding var selectedPriority: NotificationPriority
    
    enum NotificationPriority: String, CaseIterable, Identifiable {
        case all = "All Updates"
        case important = "Important Only"
        case critical = "Critical Only"
        
        var id: String { self.rawValue }
        
        var description: String {
            switch self {
            case .all:
                return "Receive all notifications related to your projects"
            case .important:
                return "Only receive updates about status changes and client messages"
            case .critical:
                return "Only receive notifications about urgent matters requiring attention"
            }
        }
        
        var icon: String {
            switch self {
            case .all:
                return "bell.fill"
            case .important:
                return "exclamationmark.circle.fill"
            case .critical:
                return "exclamationmark.triangle.fill"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notification Priority")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                ForEach(NotificationPriority.allCases) { priority in
                    Button(action: {
                        withAnimation {
                            selectedPriority = priority
                        }
                    }) {
                        HStack(spacing: 16) {
                            // Icon
                            ZStack {
                                Circle()
                                    .fill(selectedPriority == priority ? 
                                          OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: priority.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(selectedPriority == priority ? .white : OPSStyle.Colors.secondaryText)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(priority.rawValue)
                                    .font(.system(size: 16, weight: selectedPriority == priority ? .semibold : .regular))
                                    .foregroundColor(.white)
                                
                                Text(priority.description)
                                    .font(.system(size: 13))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            // Selection indicator
                            if selectedPriority == priority {
                                Image(systemName: OPSStyle.Icons.checkmark)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                        .padding(12)
                        .background(selectedPriority == priority ? 
                                    OPSStyle.Colors.primaryAccent.opacity(0.15) : OPSStyle.Colors.cardBackground.opacity(0.3))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
}

struct TemporaryMuteControl: View {
    @Binding var isMuted: Bool
    @Binding var muteHours: Int
    @State private var muteEndTime: Date?
    
    private let muteOptions = [1, 2, 4, 8, 24]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temporary Mute")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("Silence notifications for a specific period")
                        .font(.system(size: 13))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                Toggle("", isOn: $isMuted)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
                    .onChange(of: isMuted) { _, newValue in
                        if newValue {
                            // Set mute end time when enabling
                            muteEndTime = Calendar.current.date(byAdding: .hour, value: muteHours, to: Date())
                        } else {
                            // Clear end time when disabling
                            muteEndTime = nil
                        }
                    }
            }
            
            if isMuted {
                VStack(spacing: 12) {
                    // Mute duration options
                    HStack {
                        Text("Mute for:")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Spacer()
                        
                        // Segmented control for mute duration
                        HStack(spacing: 8) {
                            ForEach(muteOptions, id: \.self) { hours in
                                Button(action: {
                                    muteHours = hours
                                    muteEndTime = Calendar.current.date(byAdding: .hour, value: hours, to: Date())
                                }) {
                                    Text("\(hours)h")
                                        .font(.system(size: 14))
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(muteHours == hours ? 
                                                    OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
                                        .foregroundColor(muteHours == hours ? .black : .white)
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }
                    
                    // Show when notifications will resume
                    if let endTime = muteEndTime {
                        HStack {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            
                            Text("Notifications will resume at \(formatTime(endTime))")
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}