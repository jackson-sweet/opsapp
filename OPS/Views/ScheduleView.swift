//
//  ScheduleView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// ScheduleView.swift
import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading) {
                Text("Schedule")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal)
                
                Text("JACOB, RAIL CREW")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal)
                    .padding(.bottom)
                
                Text("Schedule view coming soon")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top)
        }
    }
}

// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading) {
                Text("Settings")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal)
                
                if let user = dataController.currentUser {
                    Text(user.fullName.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal)
                        .padding(.bottom)
                }
                
                Text("Settings view coming soon")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top)
        }
    }
}