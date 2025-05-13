//
//  AppHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI

struct AppHeader: View {
    enum HeaderType {
        case home
        case settings
        case schedule
    }
    
    @EnvironmentObject private var dataController: DataController
    var headerType: HeaderType
    
    private var title: String {
        switch headerType {
        case .home:
            let greeting = getGreeting().uppercased()
            return "\(greeting), \(dataController.currentUser?.firstName.uppercased() ?? "USER")"
        case .settings:
            return "SETTINGS"
        case .schedule:
            return "SCHEDULE"
        }
    }
    
    var body: some View {
        
        if headerType == .home {
            
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if let company = dataController.getCurrentUserCompany() {
                        Text(company.name.uppercased())
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
                
                // User profile image - always shown for all header types now
                if let imageData = dataController.currentUser?.profileImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(radius: 2)
                } else {
                    Circle()
                        .fill(Color("Background"))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(dataController.currentUser?.firstName.prefix(1) ?? "U")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(radius: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
        } else {
            
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if headerType == .home, let company = dataController.getCurrentUserCompany() {
                        Text(company.name.uppercased())
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
                

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        
        
    }
    
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 0..<12:
            return "Good Morning"
        case 12..<17:
            return "Good Afternoon"
        default:
            return "Good Evening"
        }
    }
}
