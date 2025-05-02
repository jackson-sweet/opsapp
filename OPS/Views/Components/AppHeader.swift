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
            let greeting = getGreeting()
            return "\(greeting), \(dataController.currentUser?.firstName ?? "User")"
        case .settings:
            return "Settings"
        case .schedule:
            return "Schedule"
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                if headerType == .home, let company = dataController.getCurrentUserCompany() {
                    Text(company.name.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            Spacer()
            
            // User profile image
            if let imageData = dataController.currentUser?.profileImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(dataController.currentUser?.firstName.prefix(1) ?? "U")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
        .padding()
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