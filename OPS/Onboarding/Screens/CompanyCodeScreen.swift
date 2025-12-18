//
//  CompanyCodeScreen.swift
//  OPS
//
//  Displays the company code after successful company creation.
//  Clean celebration screen with copy functionality.
//  Uses phased animation system for entrance effects.
//

import SwiftUI
import SwiftData

struct CompanyCodeScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    @State private var showCopied = false
    @State private var showInviteSheet = false
    @State private var isSyncing = false

    // Animation coordinator
    @StateObject private var animationCoordinator = OnboardingAnimationCoordinator()

    private var companyCode: String {
        manager.state.companyData.companyCode ?? "------"
    }

    private var companyName: String {
        manager.state.companyData.name
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header area with phased typing animation
            PhasedOnboardingHeader(
                title: "YOU'RE SET UP.",
                subtitle: "\(companyName) is ready.",
                coordinator: animationCoordinator
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 60)

            Spacer()
                .frame(height: 48)

            // Content section - fades in upward
            PhasedContent(coordinator: animationCoordinator) {
                VStack(spacing: 0) {
                    // Company code section
                    VStack(alignment: .leading, spacing: 16) {
                        PhasedLabel("CREW CODE", index: 0, isLast: true, coordinator: animationCoordinator)

                        // Code display
                        Button {
                            copyCode()
                        } label: {
                            HStack(spacing: 12) {
                                Text("[\(companyCode)]")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Spacer()

                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 14))
                                    .foregroundColor(showCopied ? OPSStyle.Colors.successStatus : OPSStyle.Colors.tertiaryText)
                            }
                            .padding(16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }

                        Text("Share this with your crew so they can join.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .padding(.horizontal, 40)

                    Spacer()
                        .frame(height: 32)

                    // Invite team button
                    Button {
                        showInviteSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2")
                                .font(.system(size: 14, weight: .semibold))

                            Text("INVITE CREW")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 40)
                }
            }

            Spacer()

            // Info text
            Text("You'll find this code in Settings anytime.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)

            // Continue button with phased animation
            PhasedPrimaryButton(
                "LET'S GO",
                isLoading: isSyncing,
                loadingText: "Setting up...",
                coordinator: animationCoordinator
            ) {
                syncAndContinue()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .sheet(isPresented: $showInviteSheet) {
            InviteTeamSheet(
                companyCode: companyCode,
                companyName: companyName,
                companyId: manager.state.companyData.companyId ?? "",
                isPresented: $showInviteSheet
            )
        }
        .onAppear {
            animationCoordinator.start()
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = companyCode

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }

    private func syncAndContinue() {
        isSyncing = true

        Task {
            print("[COMPANY_CODE] ========== SYNC AND CONTINUE START ==========")
            print("[COMPANY_CODE] Starting full data sync before continuing...")

            // Debug: Check what we have
            let stateCompanyId = manager.state.companyData.companyId
            let stateCompanyCode = manager.state.companyData.companyCode
            let stateUserId = manager.state.userData.userId
            print("[COMPANY_CODE] State companyId: \(stateCompanyId ?? "nil")")
            print("[COMPANY_CODE] State companyCode: \(stateCompanyCode ?? "nil")")
            print("[COMPANY_CODE] State userId: \(stateUserId ?? "nil")")

            // Check UserDefaults
            let udCurrentUserId = UserDefaults.standard.string(forKey: "currentUserId")
            let udUserId = UserDefaults.standard.string(forKey: "user_id")
            let udCompanyId = UserDefaults.standard.string(forKey: "company_id")
            print("[COMPANY_CODE] UserDefaults currentUserId: \(udCurrentUserId ?? "nil")")
            print("[COMPANY_CODE] UserDefaults user_id: \(udUserId ?? "nil")")
            print("[COMPANY_CODE] UserDefaults company_id: \(udCompanyId ?? "nil")")

            // Check dataController.currentUser
            if let dcUser = dataController.currentUser {
                print("[COMPANY_CODE] DataController.currentUser exists:")
                print("[COMPANY_CODE]   - id: \(dcUser.id)")
                print("[COMPANY_CODE]   - companyId BEFORE: \(dcUser.companyId ?? "nil")")
            } else {
                print("[COMPANY_CODE] ⚠️ DataController.currentUser is NIL!")
            }

            // Ensure user has company ID set
            if let companyId = manager.state.companyData.companyId,
               let currentUser = dataController.currentUser {
                currentUser.companyId = companyId
                print("[COMPANY_CODE] ✅ Set user companyId to: \(companyId)")
                print("[COMPANY_CODE]   - companyId AFTER: \(currentUser.companyId ?? "nil")")

                // Also save to UserDefaults for sync manager
                UserDefaults.standard.set(companyId, forKey: "company_id")
                UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                print("[COMPANY_CODE] ✅ Saved companyId to UserDefaults")

                // Ensure currentUserId is set
                if UserDefaults.standard.string(forKey: "currentUserId") == nil {
                    UserDefaults.standard.set(currentUser.id, forKey: "currentUserId")
                    print("[COMPANY_CODE] ✅ Set currentUserId in UserDefaults: \(currentUser.id)")
                }

                // Save the model context to persist the change
                if let modelContext = dataController.modelContext {
                    do {
                        try modelContext.save()
                        print("[COMPANY_CODE] ✅ ModelContext saved")
                    } catch {
                        print("[COMPANY_CODE] ❌ ModelContext save failed: \(error)")
                    }
                }
            } else {
                print("[COMPANY_CODE] ⚠️ Could not set companyId:")
                print("[COMPANY_CODE]   - companyId from state: \(manager.state.companyData.companyId ?? "nil")")
                print("[COMPANY_CODE]   - currentUser exists: \(dataController.currentUser != nil)")
            }

            // Perform full sync
            if let syncManager = dataController.syncManager {
                print("[COMPANY_CODE] SyncManager exists, starting sync...")
                do {
                    // Sync company data
                    print("[COMPANY_CODE] Calling syncCompany()...")
                    try await syncManager.syncCompany()
                    print("[COMPANY_CODE] ✅ Company sync complete")

                    // Sync team members
                    if let companyId = manager.state.companyData.companyId {
                        print("[COMPANY_CODE] Calling syncCompanyTeamMembers(\(companyId))...")
                        try await syncManager.syncCompanyTeamMembers(companyId: companyId)
                        print("[COMPANY_CODE] ✅ Team members sync complete")

                        // Sync task types
                        print("[COMPANY_CODE] Calling syncCompanyTaskTypes(\(companyId))...")
                        try await syncManager.syncCompanyTaskTypes(companyId: companyId)
                        print("[COMPANY_CODE] ✅ Task types sync complete")
                    } else {
                        print("[COMPANY_CODE] ⚠️ No companyId for team/task type sync")
                    }
                } catch {
                    print("[COMPANY_CODE] ❌ Sync error: \(error)")
                }
            } else {
                print("[COMPANY_CODE] ⚠️ SyncManager is NIL!")
            }

            // Verify company was synced
            if let modelContext = dataController.modelContext,
               let companyId = manager.state.companyData.companyId {
                let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == companyId })
                if let company = try? modelContext.fetch(descriptor).first {
                    print("[COMPANY_CODE] ✅ Company found in local DB:")
                    print("[COMPANY_CODE]   - id: \(company.id)")
                    print("[COMPANY_CODE]   - name: \(company.name)")
                    print("[COMPANY_CODE]   - externalId: \(company.externalId ?? "nil")")
                } else {
                    print("[COMPANY_CODE] ❌ Company NOT found in local DB after sync!")
                }
            }

            print("[COMPANY_CODE] ========== SYNC AND CONTINUE END ==========")

            await MainActor.run {
                isSyncing = false
                print("[COMPANY_CODE] Proceeding to ready screen")
                manager.goToScreen(.ready)
            }
        }
    }
}

// MARK: - Invite Team Sheet

struct InviteTeamSheet: View {
    let companyCode: String
    let companyName: String
    let companyId: String
    @Binding var isPresented: Bool

    @State private var showCopiedFeedback = false
    @State private var showEmailInvite = false
    @State private var inviteEmails: [String] = [""]
    @State private var isSendingInvites = false
    @State private var inviteSentSuccess = false

    private let onboardingService = OnboardingService()

    // Centralized copy
    private var smsMessage: String {
        OnboardingCopy.TeamInvite.smsMessage(companyName: companyName, companyCode: companyCode)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("GET YOUR CREW ON OPS")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Share this code. They'll download the app and enter it to join \(companyName).")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)

                mainInviteOptions
            }
            .padding(.horizontal, 24)
            .background(OPSStyle.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
    }

    // MARK: - Main Invite Options

    private var mainInviteOptions: some View {
        VStack(spacing: 16) {
            // Code display card with copy button
            VStack(alignment: .leading, spacing: 8) {
                Text("CREW CODE")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                HStack {
                    Text("[\(companyCode)]")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = companyCode
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        showCopiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopiedFeedback = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12))

                            Text(showCopiedFeedback ? "COPIED" : "COPY")
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(showCopiedFeedback ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            // Share options
            VStack(spacing: 12) {
                // Send via Text Message
                if let smsURL = URL(string: "sms:&body=\(smsMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    Link(destination: smsURL) {
                        HStack {
                            Image(systemName: "message")
                                .font(.system(size: 14))

                            Text("TEXT IT")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }

                // Email invite section (expands inline)
                VStack(spacing: 12) {
                    // Email fields (revealed when showEmailInvite is true)
                    if showEmailInvite {
                        VStack(spacing: 12) {
                            // Section header with divider
                            HStack(spacing: 12) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 1)

                                Text("EMAIL INVITES")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 1)
                            }

                            ForEach(inviteEmails.indices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    ZStack(alignment: .leading) {
                                        if inviteEmails[index].isEmpty {
                                            Text("team.member@example.com")
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                .padding(.horizontal, 16)
                                        }
                                        TextField("", text: $inviteEmails[index])
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .keyboardType(.emailAddress)
                                            .autocapitalization(.none)
                                            .padding(.horizontal, 16)
                                    }
                                    .padding(.vertical, 14)
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )

                                    // Remove button - always visible, collapses section if last email
                                    Button {
                                        if inviteEmails.count == 1 {
                                            // Collapse the section
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                inviteEmails = [""]
                                                showEmailInvite = false
                                            }
                                        } else {
                                            inviteEmails.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            .frame(width: 28, height: 28)
                                    }
                                }
                            }

                            // Add another email button
                            if inviteEmails.count < 10 {
                                Button {
                                    inviteEmails.append("")
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16))

                                        Text("+ Add another")
                                            .font(OPSStyle.Typography.body)
                                    }
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // Success message
                            if inviteSentSuccess {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(OPSStyle.Colors.successStatus)

                                    Text("Sent.")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.successStatus)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Send via Email button (transforms to Send Invites when expanded)
                    Button {
                        if showEmailInvite {
                            // Send invites
                            sendInvites()
                        } else {
                            // Expand email fields
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showEmailInvite = true
                            }
                        }
                    } label: {
                        if isSendingInvites {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: showEmailInvite ? .black : OPSStyle.Colors.primaryText))
                        } else {
                            HStack {
                                Image(systemName: showEmailInvite ? "paperplane" : "envelope")
                                    .font(.system(size: 14))

                                Text(showEmailInvite ? "SEND INVITES" : "EMAIL IT")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(showEmailInvite && hasValidEmails ? Color.white : (showEmailInvite ? Color.white.opacity(0.5) : OPSStyle.Colors.cardBackgroundDark.opacity(0.8)))
                    .foregroundColor(showEmailInvite ? .black : OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(showEmailInvite ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .disabled(showEmailInvite && (!hasValidEmails || isSendingInvites))
                }
            }

            Spacer()

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW IT WORKS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text("1. They download OPS (free)")
                    Text("2. They tap \"Join a Crew\"")
                    Text("3. They enter the code above")
                }
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    private var hasValidEmails: Bool {
        inviteEmails.contains { email in
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && isValidEmail(trimmed)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func sendInvites() {
        let validEmails = inviteEmails.compactMap { email in
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && isValidEmail(trimmed) ? trimmed : nil
        }

        guard !validEmails.isEmpty else { return }

        isSendingInvites = true

        Task {
            do {
                _ = try await onboardingService.sendInvites(emails: validEmails, companyId: companyId)

                await MainActor.run {
                    isSendingInvites = false
                    inviteSentSuccess = true
                    inviteEmails = [""]

                    // Reset success message after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        inviteSentSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSendingInvites = false
                    // Could show error alert here
                    print("[INVITE] Failed to send invites: \(error)")
                }
            }
        }
    }
}

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.companyCreator)
    manager.state.companyData.name = "Acme Construction"
    manager.state.companyData.companyCode = "ACME42"

    return CompanyCodeScreen(manager: manager)
        .environmentObject(dataController)
}

#Preview("Invite Sheet") {
    InviteTeamSheet(
        companyCode: "ACME42",
        companyName: "Acme Construction",
        companyId: "123456",
        isPresented: .constant(true)
    )
}
