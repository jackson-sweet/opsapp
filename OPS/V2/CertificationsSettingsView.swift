//
//  CertificationsSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI

struct CertificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var certifications: [Certification] = []
    @State private var trainings: [Training] = []
    @State private var showAddCertification = false
    @State private var showAddTraining = false
    @State private var isLoading = true
    
    // Placeholder model structures
    struct Certification: Identifiable {
        let id: String
        let name: String
        let issuer: String
        let issueDate: Date
        let expiryDate: Date?
        let status: CertStatus
        let documentURL: String?
        
        enum CertStatus: String {
            case valid = "Valid"
            case expired = "Expired"
            case pendingReview = "Pending Review"
        }
        
        var statusColor: Color {
            switch status {
            case .valid:
                return Color.green
            case .expired:
                return Color.red
            case .pendingReview:
                return Color.orange
            }
        }
    }
    
    struct Training: Identifiable {
        let id: String
        let name: String
        let provider: String
        let completionDate: Date
        let hours: Int
        let documentURL: String?
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    // Header
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        
                        Text("Certifications & Training")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Spacer()
                    }
                    .padding()
                    
                    if isLoading {
                        loadingView
                    } else {
                        // Certifications section
                        certificationsSection
                        
                        // Training section
                        trainingSection
                    }
                }
                .padding(.bottom, OPSStyle.Layout.spacing4)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadUserData()
        }
        .sheet(isPresented: $showAddCertification) {
            // In a real implementation, this would be a form to add a new certification
            Text("Add Certification Form")
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddTraining) {
            // In a real implementation, this would be a form to add a new training
            Text("Add Training Form")
                .presentationDetents([.medium])
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.5)
            
            Text("Loading certifications and training...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var certificationsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Header with add button
            HStack {
                Text("CERTIFICATIONS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Button(action: {
                    showAddCertification = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal)
            
            if certifications.isEmpty {
                // Empty state
                VStack {
                    Image(systemName: "certificate")
                        .font(.system(size: 36))
                        .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                        .padding(.bottom, 8)
                    
                    Text("No certifications added")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("Add your professional certifications to keep track of them in one place")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding(.horizontal)
            } else {
                // List of certifications
                ForEach(certifications) { cert in
                    certificationCard(cert: cert)
                }
            }
        }
    }
    
    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Header with add button
            HStack {
                Text("TRAINING")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.top, OPSStyle.Layout.spacing3)
                
                Spacer()
                
                Button(action: {
                    showAddTraining = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal)
            
            if trainings.isEmpty {
                // Empty state
                VStack {
                    Image(systemName: "book.fill")
                        .font(.system(size: 36))
                        .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                        .padding(.bottom, 8)
                    
                    Text("No training records")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("Add your completed training courses to track your professional development")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding(.horizontal)
            } else {
                // List of trainings
                ForEach(trainings) { training in
                    trainingCard(training: training)
                }
            }
        }
    }
    
    private func certificationCard(cert: Certification) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Top row with name and status
            HStack {
                Text(cert.name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                // Status badge
                Text(cert.status.rawValue)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(cert.statusColor)
                    .cornerRadius(12)
            }
            
            // Issuer
            Text("Issued by: \(cert.issuer)")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Divider()
                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
            
            // Dates row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Issue Date")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(formatDate(cert.issueDate))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
                
                if let expiryDate = cert.expiryDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Expiry Date")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Text(formatDate(expiryDate))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(
                                expiryDate < Date() ? Color.red : OPSStyle.Colors.primaryText
                            )
                    }
                }
            }
            
            // Document link if available
            if cert.documentURL != nil {
                Button(action: {
                    // Action to view document
                }) {
                    HStack {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 14))
                        
                        Text("View Certificate")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
    }
    
    private func trainingCard(training: Training) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Course name
            Text(training.name)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            // Provider
            Text("Provider: \(training.provider)")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Divider()
                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
            
            // Details row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Completion Date")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(formatDate(training.completionDate))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Hours")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text("\(training.hours)")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            
            // Document link if available
            if training.documentURL != nil {
                Button(action: {
                    // Action to view document
                }) {
                    HStack {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 14))
                        
                        Text("View Certificate")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func loadUserData() {
        // Simulated data loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // This would normally load from your data controller
            // For now, using sample data
            
            // Empty for now to show the empty state UI
            self.certifications = []
            self.trainings = []
            
            // Sample data if needed - uncomment to see populated UI:
            /*
            self.certifications = [
                Certification(
                    id: "1",
                    name: "OSHA Safety Certification",
                    issuer: "Occupational Safety and Health Administration",
                    issueDate: Date().addingTimeInterval(-365*24*60*60),
                    expiryDate: Date().addingTimeInterval(365*24*60*60),
                    status: .valid,
                    documentURL: "https://example.com/cert1.pdf"
                ),
                Certification(
                    id: "2",
                    name: "Commercial Driver's License",
                    issuer: "Department of Motor Vehicles",
                    issueDate: Date().addingTimeInterval(-730*24*60*60),
                    expiryDate: Date().addingTimeInterval(-30*24*60*60),
                    status: .expired,
                    documentURL: "https://example.com/cert2.pdf"
                )
            ]
            
            self.trainings = [
                Training(
                    id: "1",
                    name: "Heavy Equipment Operation",
                    provider: "Construction Training Institute",
                    completionDate: Date().addingTimeInterval(-180*24*60*60),
                    hours: 40,
                    documentURL: "https://example.com/training1.pdf"
                )
            ]
            */
            
            self.isLoading = false
        }
    }
}

#Preview {
    CertificationsSettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}