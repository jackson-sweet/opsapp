//
//  PlanSelectionView.swift
//  OPS
//
//  Created by Assistant on 2025-01-16.
//
//  Plan selection and payment view for subscriptions

import SwiftUI
import StripePaymentSheet

struct PlanSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var dataController: DataController
    
    @State var selectedPlan: SubscriptionPlan = .starter
    @State var selectedSchedule: PaymentSchedule = .monthly
    @State var isProcessingPayment = false
    @State var showPaymentError = false
    @State var errorMessage = ""
    @State private var promoCode = ""
    @State private var showPromoField = false
    @State private var validatedPromoCode: String? = nil
    @State private var promoDiscount: Int? = nil // Percentage discount
    @State private var isValidatingPromo = false
    
    // Feature flag to use new setup intent flow
    private let useSetupIntentFlow = true // Set to true to use the new secure flow
    @State private var promoValidationError: String? = nil
    @State private var showHelpMeChoose = false
    
    // Stripe payment sheet
    @State private var paymentSheet: PaymentSheet?
    @State private var presentingPaymentSheet = false
    @State private var currentSetupIntentId: String? = nil
    
    // Payment success polling states
    @State private var isPollingSubscriptionStatus = false
    @State private var pollingMessage = "Processing payment..."
    @State private var pollingStartTime: Date? = nil
    @State private var pollingTimer: Timer? = nil
    @State private var pollingAttempts = 0
    @State private var maxPollingAttempts = 10 // 30 seconds / 3 second intervals
    
    // Current subscription info
    private var currentPlan: SubscriptionPlan? {
        guard let company = dataController.getCurrentUserCompany() else { return nil }
        return SubscriptionPlan(rawValue: company.subscriptionPlan ?? "")
    }
    
    private var currentStatus: SubscriptionStatus? {
        guard let company = dataController.getCurrentUserCompany() else { return nil }
        return SubscriptionStatus(rawValue: company.subscriptionStatus ?? "")
    }
    
    // Get recommended plan based on company size
    private var recommendedPlan: SubscriptionPlan {
        guard let company = dataController.getCurrentUserCompany() else { return .starter }
        let employeeCount = dataController.getTeamMembers(companyId: company.id).count
        
        // Check against max seats of plans
        if employeeCount <= SubscriptionPlan.starter.maxSeats { // 3 seats
            return .starter
        } else if employeeCount <= SubscriptionPlan.team.maxSeats { // 10 seats
            return .team
        } else { // More than 10 seats
            return .business
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Billing toggle
                        billingToggle
                        
                        // Plan suggestion
                        if recommendedPlan == selectedPlan {
                            planRecommendation
                        }
                        
                        // Plan cards
                        planCards
                        
                        // Help Me Choose section
                        helpMeChooseSection
                        
                        // Features comparison
                        featuresSection
                        
                        // Promo code section
                        promoCodeSection
                        
                        // Payment button
                        paymentButton
                            .padding(.top, 20)
                        
                        // Terms and conditions
                        termsSection
                            .padding(.bottom, 40)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Cancel any ongoing polling
                        pollingTimer?.invalidate()
                        pollingTimer = nil
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .disabled(isPollingSubscriptionStatus || isProcessingPayment) // Disable during processing
                }
            }
            // Prevent interactive dismissal during payment processing or polling
            .interactiveDismissDisabled(isPollingSubscriptionStatus || isProcessingPayment)
            // Payment success polling overlay
            .overlay(
                paymentSuccessOverlay
            )
        }
        .onAppear {
            // Set initial plan based on recommendation
            if currentPlan == nil {
                selectedPlan = recommendedPlan
            } else {
                selectedPlan = currentPlan ?? .starter
            }
        }
        .onDisappear {
            // Clean up any polling timers when view disappears
            cleanupPolling()
        }
        .alert("Payment Error", isPresented: $showPaymentError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: presentingPaymentSheet) { _, isPresented in
            if isPresented, let paymentSheet = paymentSheet {
                // Present payment sheet directly without intermediate sheet
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    var topController = rootViewController
                    while let presented = topController.presentedViewController {
                        topController = presented
                    }
                    
                    paymentSheet.present(from: topController) { result in
                        presentingPaymentSheet = false
                        handlePaymentResult(result)
                    }
                }
            }
        }
    }
    
    // MARK: - Payment Success Overlay
    
    @ViewBuilder
    private var paymentSuccessOverlay: some View {
        if isPollingSubscriptionStatus {
            ZStack {
                // Pure black background with subtle opacity
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                // Tactical content container
                VStack(spacing: 0) {
                    // Top accent line
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(height: 2)
                        .opacity(0.8)
                    
                    // Main content
                    VStack(spacing: 28) {
                        // Status indicator section
                        VStack(spacing: 20) {
                            // Tactical icon with accent
                            ZStack {
                                // Background circle with subtle accent
                                Circle()
                                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 2)
                                    .frame(width: 56, height: 56)
                                
                                // Inner checkmark
                                Image(systemName: "checkmark")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .scaleEffect(isPollingSubscriptionStatus ? 1.0 : 0.8)
                            .animation(.easeOut(duration: 0.3), value: isPollingSubscriptionStatus)
                            
                            // Status text stack
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("STATUS:")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    
                                    Text("PAYMENT CONFIRMED")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                                
                                // Progress message
                                Text(pollingMessage.uppercased())
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .frame(minHeight: 20)
                            }
                        }
                        
                        // Loading or action section
                        if pollingAttempts < maxPollingAttempts {
                            // Tactical loading indicator
                            HStack(spacing: 6) {
                                ForEach(0..<3) { index in
                                    Rectangle()
                                        .fill(OPSStyle.Colors.primaryAccent)
                                        .frame(width: 3, height: 12)
                                        .opacity(pollingAttempts % 3 == index ? 1.0 : 0.3)
                                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(index) * 0.2), value: pollingAttempts)
                                }
                            }
                            .padding(.vertical, 8)
                        } else {
                            // Timeout state
                            VStack(spacing: 20) {
                                // Warning indicator
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 14))
                                        .foregroundColor(OPSStyle.Colors.warningStatus)
                                    
                                    Text("PROCESSING DELAYED")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.warningStatus)
                                }
                                
                                Text("SUBSCRIPTION ACTIVATION IN PROGRESS")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .multilineTextAlignment(.center)
                                
                                // Tactical continue button
                                Button(action: {
                                    stopPollingAndDismiss()
                                }) {
                                    HStack(spacing: 8) {
                                        Text("CONTINUE")
                                            .font(OPSStyle.Typography.captionBold)
                                        
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                                }
                            }
                        }
                        
                        // Bottom status indicator
                        if pollingAttempts < maxPollingAttempts {
                            HStack(spacing: 12) {
                                Text("ATTEMPT")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                
                                Text("\(pollingAttempts)/\(maxPollingAttempts)")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 36)
                    
                    // Bottom accent line
                    Rectangle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(height: 2)
                        .opacity(0.8)
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .scaleEffect(isPollingSubscriptionStatus ? 1.0 : 0.95)
                .opacity(isPollingSubscriptionStatus ? 1.0 : 0)
                .animation(.easeOut(duration: 0.2), value: isPollingSubscriptionStatus)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("SELECT PLAN")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text("Choose team size")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Billing Toggle
    
    private var billingToggle: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Minimal section header
            Text("BILLING CYCLE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            // Toggle buttons
            HStack(spacing: 0) {
                ForEach([PaymentSchedule.monthly, PaymentSchedule.annual], id: \.self) { schedule in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSchedule = schedule
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text(schedule.displayName.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(selectedSchedule == schedule ? .black : OPSStyle.Colors.primaryText)
                            
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            selectedSchedule == schedule ? 
                            Color.white : 
                            Color.clear
                        )
                    }
                }
            }
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Plan Cards
    
    private var planCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Minimal section header
            Text("AVAILABLE PLANS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            VStack(spacing: 8) {
                ForEach([SubscriptionPlan.starter, SubscriptionPlan.team, SubscriptionPlan.business], id: \.self) { plan in
                    PlanCard(
                        plan: plan,
                        schedule: selectedSchedule,
                        isSelected: selectedPlan == plan,
                        isCurrentPlan: plan == currentPlan,
                        isRecommended: plan == recommendedPlan,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedPlan = plan
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Minimal section header
            Text("ALL PLANS INCLUDE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            // Features grid
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(text: "Unlimited projects")
                        FeatureRow(text: "Photo attachments")
                        FeatureRow(text: "Team collaboration")
                        FeatureRow(text: "Offline mode")
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(text: "Real-time sync")
                        FeatureRow(text: "Calendar scheduling")
                        FeatureRow(text: "Location tracking")
                        FeatureRow(text: "Client management")
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Promo Code Section
    
    private var promoCodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Toggle button to show/hide promo field
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPromoField.toggle()
                    if !showPromoField {
                        promoCode = ""
                        validatedPromoCode = nil
                        promoDiscount = nil
                        promoValidationError = nil
                    }
                }
            }) {
                HStack {
                    Image(systemName: validatedPromoCode != nil ? "checkmark.seal.fill" : "tag")
                        .font(.system(size: 14))
                        .foregroundColor(validatedPromoCode != nil ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.secondaryText)
                    
                    if let discount = promoDiscount {
                        Text("\(discount)% OFF APPLIED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                    } else {
                        Text("PROMO CODE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    Image(systemName: showPromoField ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            // Promo code input field
            if showPromoField {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        TextField("ENTER CODE", text: $promoCode)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(
                                        validatedPromoCode != nil ? OPSStyle.Colors.warningStatus.opacity(0.3) :
                                        Color.white.opacity(0.1),
                                        lineWidth: 1
                                    )
                            )
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .disabled(validatedPromoCode != nil)
                            .opacity(validatedPromoCode != nil ? 0.6 : 1.0)
                        
                        // Apply/Clear button
                        Button(action: {
                            if validatedPromoCode != nil {
                                // Clear validated promo
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    promoCode = ""
                                    validatedPromoCode = nil
                                    promoDiscount = nil
                                    promoValidationError = nil
                                }
                            } else if !promoCode.isEmpty {
                                // Validate promo code
                                validatePromoCode()
                            }
                        }) {
                            if isValidatingPromo {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                    .scaleEffect(0.8)
                                    .frame(width: 80, height: 40)
                            } else if validatedPromoCode != nil {
                                HStack {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("CLEAR")
                                        .font(OPSStyle.Typography.captionBold)
                                }
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .frame(width: 80, height: 40)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            } else {
                                Text("APPLY")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(promoCode.isEmpty ? OPSStyle.Colors.tertiaryText : .black)
                                    .frame(width: 80, height: 40)
                                    .background(
                                        promoCode.isEmpty ? 
                                        OPSStyle.Colors.cardBackgroundDark.opacity(0.8) :
                                        OPSStyle.Colors.primaryAccent
                                    )
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(
                                                promoCode.isEmpty ?
                                                Color.white.opacity(0.1) :
                                                Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                            }
                        }
                        .disabled(isValidatingPromo || (validatedPromoCode == nil && promoCode.isEmpty))
                    }
                    
                    // Success or error message
                    if let error = promoValidationError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text(error)
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    } else if let discount = promoDiscount, validatedPromoCode != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("\(discount)% discount will be applied at checkout")
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Payment Button
    
    private var paymentButton: some View {
        Button(action: {
            initiatePayment()
        }) {
            HStack {
                if isProcessingPayment {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                }
                
                Text(paymentButtonText.uppercased())
                    .font(OPSStyle.Typography.captionBold)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(paymentButtonBackgroundColor)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .disabled(isProcessingPayment || shouldDisablePaymentButton)
    }
    
    private var shouldDisablePaymentButton: Bool {
        // Disable if selecting current active plan
        if let current = currentPlan,
           let status = currentStatus,
           selectedPlan == current &&
           (status == .active || status == .trial) {
            return true
        }
        return false
    }
    
    private var paymentButtonBackgroundColor: Color {
        if shouldDisablePaymentButton {
            return OPSStyle.Colors.tertiaryText.opacity(0.3)
        }
        return OPSStyle.Colors.primaryAccent
    }
    
    private var paymentButtonText: String {
        // Check if this is the current active plan
        if let current = currentPlan,
           let status = currentStatus,
           selectedPlan == current {
            switch status {
            case .active, .trial:
                return "This Plan Already Active"
            case .cancelled, .expired:
                return "Re-Join This Plan"
            case .grace:
                return "Reactivate Plan"
            default:
                break
            }
        }
        
        // Check if this is an upgrade
        if let current = currentPlan {
            if selectedPlan.maxSeats > current.maxSeats {
                // Calculate price for button
                let price = selectedSchedule == .monthly ?
                    selectedPlan.monthlyPrice :
                    selectedPlan.annualPrice
                
                var displayPrice = Double(price) / 100.0
                
                // Apply discount if available
                if let discount = promoDiscount {
                    let discountAmount = displayPrice * (Double(discount) / 100.0)
                    displayPrice = displayPrice - discountAmount
                }
                
                let priceString = String(format: "$%.2f", displayPrice)
                let period = selectedSchedule == .monthly ? "/mo" : "/yr"
                
                return "Upgrade • \(priceString)\(period)"
            }
        }
        
        // Default subscribe text
        let price = selectedSchedule == .monthly ?
            selectedPlan.monthlyPrice :
            selectedPlan.annualPrice
        
        var displayPrice = Double(price) / 100.0
        
        // Apply discount if available
        if let discount = promoDiscount {
            let discountAmount = displayPrice * (Double(discount) / 100.0)
            displayPrice = displayPrice - discountAmount
        }
        
        let priceString = String(format: "$%.2f", displayPrice)
        let period = selectedSchedule == .monthly ? "/mo" : "/yr"
        
        // Show discount info in button
        if let discount = promoDiscount, discount == 100 {
            return "Complete Setup • FREE"
        } else if promoDiscount != nil {
            let originalPriceString = String(format: "$%.2f", Double(price) / 100.0)
            return "Subscribe • \(priceString)\(period) (was \(originalPriceString))"
        } else {
            return "Subscribe • \(priceString)\(period)"
        }
    }
    
    // MARK: - Terms Section
    
    private var termsSection: some View {
        VStack(spacing: 8) {
            Text("By subscribing, you agree to our")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            
            HStack(spacing: 16) {
                Button("Terms of Service") {
                    if let url = URL(string: "https://opsapp.co/legal") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                
                Text("and")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                
                Button("Privacy Policy") {
                    if let url = URL(string: "https://opsapp.co/legal") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
    }
    
    // MARK: - Payment Processing
    
    private func initiatePayment() {
        print("🔵 INITIATING PAYMENT:")
        print("  - Selected Plan: \(selectedPlan.displayName)")
        print("  - Schedule: \(selectedSchedule.displayName)")
        
        isProcessingPayment = true
        
        // Get the selected price ID
        let priceId: String? = selectedSchedule == .monthly ? 
            selectedPlan.stripePriceIds.monthly : 
            selectedPlan.stripePriceIds.annual
        
        print("  - Price ID: \(priceId ?? "nil")")
        
        guard let priceId = priceId else {
            errorMessage = "Invalid plan selection"
            showPaymentError = true
            isProcessingPayment = false
            return
        }
        
        // Get company information
        guard let company = dataController.getCurrentUserCompany() else {
            errorMessage = "Unable to load account information"
            showPaymentError = true
            isProcessingPayment = false
            return
        }
        
        // Directly create subscription through Bubble
        // Bubble handles customer creation automatically
        createSubscriptionThroughBubble(priceId: priceId, companyId: company.id)
    }
    
    private func validatePromoCode() {
        isValidatingPromo = true
        promoValidationError = nil
        
        // Call Bubble API to validate promo code
        let endpoint = "https://opsapp.co/api/1.1/wf/validate_promo_code?api_token=f81e9da85b7a12e996ac53e970a52299"
        
        guard let url = URL(string: endpoint) else {
            isValidatingPromo = false
            promoValidationError = "Invalid server URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "promo_code": promoCode.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            isValidatingPromo = false
            promoValidationError = "Failed to validate code"
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isValidatingPromo = false
                
                if let error = error {
                    self.promoValidationError = "Network error: \(error.localizedDescription)"
                    return
                }
                
                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 404 {
                        self.promoValidationError = "Validation service not available"
                        return
                    } else if httpResponse.statusCode != 200 {
                        self.promoValidationError = "Server error (\(httpResponse.statusCode))"
                        return
                    }
                }
                
                guard let data = data else {
                    self.promoValidationError = "No response data"
                    return
                }
                
                // Debug: Print raw response
                #if DEBUG
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📥 PROMO VALIDATION RESPONSE: \(jsonString)")
                }
                #endif
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🔍 PROMO RESPONSE KEYS: \(json.keys.sorted())")
                        
                        // Check if it's wrapped in a response object
                        let responseData = json["response"] as? [String: Any] ?? json
                        print("🔍 RESPONSE DATA KEYS: \(responseData.keys.sorted())")
                        
                        if let valid = responseData["valid"] as? Bool {
                            if valid {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    self.validatedPromoCode = self.promoCode
                                    
                                    // Get discount details
                                    if let percentage = responseData["discount_percentage"] as? Double {
                                        self.promoDiscount = Int(percentage)
                                    } else if let percentage = responseData["discount_percentage"] as? Int {
                                        self.promoDiscount = percentage
                                    } else if let amountOff = responseData["discount_amount"] as? Int {
                                        // Calculate percentage from fixed amount if needed
                                        let price = self.selectedSchedule == .monthly ? 
                                            self.selectedPlan.monthlyPrice : 
                                            self.selectedPlan.annualPrice
                                        if price > 0 {
                                            self.promoDiscount = min(100, Int((Double(amountOff) / Double(price)) * 100))
                                        }
                                    }
                                    
                                    // Show coupon name if available
                                    if let couponName = responseData["coupon_name"] as? String {
                                    }
                                    
                                    // Check remaining uses if available
                                    if let maxRedemptions = responseData["max_redemptions"] as? Int,
                                       let timesRedeemed = responseData["times_redeemed"] as? Int {
                                        let remainingUses = maxRedemptions - timesRedeemed
                                        if remainingUses == 1 {
                                        } else if remainingUses <= 5 {
                                        }
                                    }
                                    
                                    self.promoValidationError = nil
                                }
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    // Get specific error message
                                    let errorMessage = responseData["error"] as? String ?? "Invalid promo code"
                                    
                                    // Provide user-friendly error messages
                                    switch errorMessage.lowercased() {
                                    case let msg where msg.contains("maximum redemptions"):
                                        self.promoValidationError = "This code has reached its usage limit"
                                    case let msg where msg.contains("expired"):
                                        self.promoValidationError = "This promo code has expired"
                                    case let msg where msg.contains("inactive"):
                                        self.promoValidationError = "This promo code is no longer active"
                                    case let msg where msg.contains("invalid"):
                                        self.promoValidationError = "Invalid promo code"
                                    default:
                                        self.promoValidationError = errorMessage
                                    }
                                    
                                    self.validatedPromoCode = nil
                                    self.promoDiscount = nil
                                }
                            }
                        } else {
                            self.promoValidationError = "Invalid response format"
                        }
                    }
                } catch {
                    self.promoValidationError = "Failed to parse response"
                }
            }
        }.resume()
    }
    
    private func createSubscriptionThroughBubble(priceId: String, companyId: String) {
        if useSetupIntentFlow {
            // New secure flow: Create setup intent first, subscription after payment
            print("🔐 Using secure setup intent flow")
            BubbleSubscriptionService.shared.createSetupIntent(
                companyId: companyId,
                priceId: priceId
            ) { result in
                switch result {
                case .success(let response):
                    print("📦 SETUP INTENT CREATED:")
                    print("  - Has Client Secret: \(response.paymentClientSecret != nil)")
                    print("  - Customer ID: \(response.customer_id ?? "nil")")
                    print("  - Setup Intent ID: \(response.setup_intent_id ?? "nil")")
                    print("  - Amount Due: \(response.amount_due ?? -1)")
                    
                    // Store the setup intent ID from the response
                    self.currentSetupIntentId = response.setup_intent_id
                    print("  - Stored Setup Intent ID: \(self.currentSetupIntentId ?? "nil")")
                    
                    // Check if payment is required
                    if response.amount_due == 0 {
                        // 100% discount - no payment needed, complete subscription immediately
                        print("✅ 100% discount applied - completing subscription without payment")
                        self.completeSubscriptionAfterPayment(
                            setupIntentId: self.currentSetupIntentId,
                            priceId: priceId,
                            companyId: companyId
                        )
                    } else if let clientSecret = response.paymentClientSecret,
                              let ephemeralKey = response.ephemeral_key,
                              let customerId = response.customer_id {
                        // Payment required - present payment sheet
                        self.presentPaymentSheet(
                            clientSecret: clientSecret,
                            ephemeralKey: ephemeralKey,
                            customerId: customerId
                        )
                    } else {
                        self.isProcessingPayment = false
                        self.errorMessage = "Payment setup failed. Missing required payment details."
                        self.showPaymentError = true
                    }
                    
                case .failure(let error):
                    self.isProcessingPayment = false
                    self.errorMessage = error.localizedDescription
                    self.showPaymentError = true
                }
            }
        } else {
            // Old flow (for backward compatibility)
            BubbleSubscriptionService.shared.createSubscriptionWithPayment(
            priceId: priceId,
            companyId: companyId,
            promoCode: validatedPromoCode ?? nil
        ) { result in
            switch result {
            case .success(let response):
                // Log the response for debugging
                print("📦 SUBSCRIPTION CREATED:")
                print("  - Status: \(response.subscription_status ?? "unknown")")
                print("  - Amount Due: \(response.amount_due ?? -1)")
                print("  - Has Client Secret: \(response.paymentClientSecret != nil)")
                
                // Check if subscription is already active (100% discount applied)
                if response.subscription_status == "active" || response.amount_due == 0 {
                    // Subscription is active with 100% discount - no payment needed
                    print("✅ Subscription active with 100% discount - no payment needed")
                    self.isProcessingPayment = false
                    self.handleSuccessfulSubscription()
                } else if response.subscription_status == "incomplete" || response.subscription_status == "trialing" {
                    // Subscription created but payment needed
                    if let clientSecret = response.paymentClientSecret,
                       let ephemeralKey = response.ephemeral_key,
                       let customerId = response.customer_id {
                        print("💳 Presenting payment sheet for incomplete subscription")
                        self.presentPaymentSheet(
                            clientSecret: clientSecret,
                            ephemeralKey: ephemeralKey,
                            customerId: customerId
                        )
                    } else {
                        print("❌ Incomplete subscription but missing payment details")
                        self.isProcessingPayment = false
                        self.errorMessage = "Payment setup required but payment details missing. Please contact support."
                        self.showPaymentError = true
                    }
                } else if let clientSecret = response.paymentClientSecret,
                          let ephemeralKey = response.ephemeral_key,
                          let customerId = response.customer_id {
                    // Payment is needed (legacy flow)
                    self.presentPaymentSheet(
                        clientSecret: clientSecret,
                        ephemeralKey: ephemeralKey,
                        customerId: customerId
                    )
                } else {
                    self.isProcessingPayment = false
                    
                    // More helpful error message
                    var errorDetails = "Unable to complete payment setup. "
                    if response.paymentClientSecret == nil {
                        errorDetails += "Payment method not initialized. "
                    }
                    if response.customer_id == nil {
                        errorDetails += "Customer account not found. "
                    }
                    errorDetails += "Please try again or contact support."
                    
                    // Log debug info
                    print("❌ PAYMENT SETUP FAILED:")
                    print("  - Client Secret: \(response.paymentClientSecret ?? "nil")")
                    print("  - Ephemeral Key: \(response.ephemeral_key ?? "nil")")
                    print("  - Customer ID: \(response.customer_id ?? "nil")")
                    print("  - Subscription ID: \(response.subscription_id ?? "nil")")
                    print("  - Status: \(response.subscription_status ?? "nil")")
                    
                    self.errorMessage = errorDetails
                    self.showPaymentError = true
                }
                
            case .failure(let error):
                self.isProcessingPayment = false
                self.errorMessage = error.localizedDescription
                self.showPaymentError = true
            }
        }
        }  // Close the else block for old flow
    }
    
    private func createSubscription(customerId: String, priceId: String) {
        guard let company = dataController.getCurrentUserCompany() else {
            errorMessage = "Unable to load company information"
            showPaymentError = true
            isProcessingPayment = false
            return
        }
        
        // Use Bubble service to create subscription
        BubbleSubscriptionService.shared.createSubscriptionWithPayment(
            priceId: priceId,
            companyId: company.id
        ) { result in
            switch result {
            case .success(let response):
                // Check if we got the necessary payment details
                if let clientSecret = response.paymentClientSecret,
                   let ephemeralKey = response.ephemeral_key,
                   let customerId = response.customer_id {
                    self.presentPaymentSheet(
                        clientSecret: clientSecret,
                        ephemeralKey: ephemeralKey,
                        customerId: customerId
                    )
                } else {
                    self.isProcessingPayment = false
                    
                    // More helpful error message
                    var errorDetails = "Unable to complete payment setup. "
                    if response.paymentClientSecret == nil {
                        errorDetails += "Payment method not initialized. "
                    }
                    if response.customer_id == nil {
                        errorDetails += "Customer account not found. "
                    }
                    errorDetails += "Please try again or contact support."
                    
                    // Log debug info
                    print("❌ PAYMENT SETUP FAILED:")
                    print("  - Client Secret: \(response.paymentClientSecret ?? "nil")")
                    print("  - Ephemeral Key: \(response.ephemeral_key ?? "nil")")
                    print("  - Customer ID: \(response.customer_id ?? "nil")")
                    print("  - Subscription ID: \(response.subscription_id ?? "nil")")
                    print("  - Status: \(response.subscription_status ?? "nil")")
                    
                    self.errorMessage = errorDetails
                    self.showPaymentError = true
                }
                
            case .failure(let error):
                self.isProcessingPayment = false
                self.errorMessage = error.localizedDescription
                self.showPaymentError = true
            }
        }
    }
    
    private func completeSubscriptionAfterPayment(setupIntentId: String?, priceId: String, companyId: String) {
        // Call the complete_subscription endpoint
        BubbleSubscriptionService.shared.completeSubscription(
            companyId: companyId,
            priceId: priceId,
            setupIntentId: setupIntentId,
            promoCode: validatedPromoCode
        ) { result in
            switch result {
            case .success(let response):
                print("✅ SUBSCRIPTION COMPLETED:")
                print("  - Subscription ID: \(response.subscription_id ?? "nil")")
                print("  - Status: \(response.subscription_status ?? "unknown")")
                
                self.isProcessingPayment = false
                // Don't call handleSuccessfulSubscription here since polling is already running
                // The polling will detect the subscription activation and dismiss
                
            case .failure(let error):
                self.isProcessingPayment = false
                // Stop polling and show error
                self.stopPollingWithError("Failed to activate subscription: \(error.localizedDescription)")
            }
        }
    }
    
    private func presentPaymentSheet(clientSecret: String, ephemeralKey: String, customerId: String) {
        guard let company = dataController.getCurrentUserCompany(),
              let user = dataController.currentUser else {
            isProcessingPayment = false
            return
        }
        
        // Calculate the display amount
        let price = selectedSchedule == .monthly ?
            selectedPlan.monthlyPrice :
            selectedPlan.annualPrice
        
        var displayPrice = Double(price) / 100.0
        
        // Apply discount if available
        if let discount = promoDiscount {
            let discountAmount = displayPrice * (Double(discount) / 100.0)
            displayPrice = displayPrice - discountAmount
        }
        
        // Configure payment sheet
        var configuration = StripeConfiguration.shared.createPaymentSheetConfiguration(
            for: customerId,
            customerEmail: user.email,
            companyName: company.name
        )
        
        // Set customer configuration
        configuration.customer = .init(
            id: customerId,
            ephemeralKeySecret: ephemeralKey
        )
        
        // Add custom primary button label to show the amount for SetupIntents
        // For SetupIntents, Stripe doesn't show the amount by default
        if clientSecret.hasPrefix("seti_") {
            // Format the amount and period
            let amountString = String(format: "$%.2f", displayPrice)
            let period = selectedSchedule == .monthly ? "/month" : "/year"
            
            // Set primary button label to show what will be charged
            configuration.primaryButtonLabel = "Subscribe • \(amountString)\(period)"
        }
        
        // Create payment sheet based on client secret type
        // SetupIntent secrets start with "seti_" and PaymentIntent secrets start with "pi_"
        if clientSecret.hasPrefix("seti_") {
            // It's a SetupIntent - use setupIntentClientSecret initializer
            paymentSheet = PaymentSheet(
                setupIntentClientSecret: clientSecret,
                configuration: configuration
            )
        } else {
            // It's a PaymentIntent - use paymentIntentClientSecret initializer
            paymentSheet = PaymentSheet(
                paymentIntentClientSecret: clientSecret,
                configuration: configuration
            )
        }
        
        // Present the sheet
        presentingPaymentSheet = true
        isProcessingPayment = false
    }
    
    private func handlePaymentResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            // Payment successful - immediately show loading screen
            print("💳 Payment completed successfully")
            
            // Start polling immediately to show loading screen
            startPollingSubscriptionStatus()
            
            if useSetupIntentFlow {
                // For setup intent flow, we need to complete the subscription
                guard let company = dataController.getCurrentUserCompany() else {
                    // Stop polling and show error
                    stopPollingWithError("Unable to load company information")
                    return
                }
                
                // Get the selected price ID
                let priceId: String? = selectedSchedule == .monthly ? 
                    selectedPlan.stripePriceIds.monthly : 
                    selectedPlan.stripePriceIds.annual
                
                guard let priceId = priceId else {
                    // Stop polling and show error
                    stopPollingWithError("Invalid plan selection")
                    return
                }
                
                // Complete the subscription after successful payment
                // Note: Loading screen is already showing via startPollingSubscriptionStatus
                completeSubscriptionAfterPayment(
                    setupIntentId: self.currentSetupIntentId, // Pass the setup intent ID
                    priceId: priceId,
                    companyId: company.id
                )
            }
            // For legacy flow, polling has already started
            
        case .canceled:
            // User cancelled - do nothing
            break
            
        case .failed(let error):
            errorMessage = error.localizedDescription
            showPaymentError = true
        }
    }
    
    private func handleSuccessfulSubscription() {
        // Show special message for 100% discount
        if let discount = promoDiscount, discount == 100 {
            // For 100% discount, show success message
            Task {
                // Refresh subscription status
                await subscriptionManager.checkSubscriptionStatus()
                
                // Show brief success feedback then dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.dismiss()
                }
            }
        } else {
            // Normal payment flow completed - start polling for subscription activation
            startPollingSubscriptionStatus()
        }
    }
    
    // MARK: - Subscription Status Polling
    
    private func startPollingSubscriptionStatus() {
        // Show the polling overlay
        withAnimation(.easeInOut(duration: 0.3)) {
            isPollingSubscriptionStatus = true
            pollingMessage = "Activating your subscription..."
            pollingAttempts = 0
        }
        
        // Start polling timer
        pollingStartTime = Date()
        
        // Initial check immediately
        checkSubscriptionStatusOnce()
        
        // Set up timer for periodic checks every 3 seconds
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.checkSubscriptionStatusOnce()
        }
    }
    
    private func checkSubscriptionStatusOnce() {
        Task {
            // Increment attempt counter
            pollingAttempts += 1
            
            // Update message based on attempts
            if pollingAttempts >= 7 {
                pollingMessage = "This is taking longer than expected..."
            } else if pollingAttempts >= 4 {
                pollingMessage = "Confirming with payment processor..."
            } else {
                pollingMessage = "Activating your subscription..."
            }
            
            print("📊 POLLING ATTEMPT \(pollingAttempts)/\(maxPollingAttempts)")
            
            // IMPORTANT: Actually sync company data from server first
            if let company = dataController.getCurrentUserCompany() {
                do {
                    print("🔄 Syncing company data from server...")
                    // Force refresh company data from the API
                    try await dataController.forceRefreshCompany(id: company.id)
                    
                    // Get the refreshed company
                    if let refreshedCompany = dataController.getCompany(id: company.id) {
                        print("✅ Company synced successfully:")
                        print("  - Status: \(refreshedCompany.subscriptionStatus ?? "unknown")")
                        print("  - Plan: \(refreshedCompany.subscriptionPlan ?? "unknown")")
                        print("  - Max Seats: \(refreshedCompany.maxSeats)")
                        print("  - Seated Employees: \(refreshedCompany.getSeatedEmployeeIds().count)")
                        print("  - Seated IDs: \(refreshedCompany.seatedEmployeeIds ?? "none")")
                    }
                    
                    // Now check the updated subscription status
                    await subscriptionManager.checkSubscriptionStatus()
                    
                } catch {
                    print("❌ Failed to sync company data: \(error)")
                    // Continue anyway - maybe local data has updated
                    await subscriptionManager.checkSubscriptionStatus()
                }
            }
            
            // Check if subscription is now active
            if let company = dataController.getCurrentUserCompany(),
               let status = company.subscriptionStatus {
                
                let subscriptionStatus = SubscriptionStatus(rawValue: status)
                
                print("📱 Current subscription status: \(status)")
                
                // Check if status changed to active or trial
                if subscriptionStatus == .active || subscriptionStatus == .trial {
                    print("🎉 Subscription is now active!")
                    // Success! Stop polling and dismiss
                    await MainActor.run {
                        stopPollingAndDismiss()
                    }
                    return
                }
            }
            
            // Check if we've reached max attempts (30 seconds)
            if pollingAttempts >= maxPollingAttempts {
                print("⏱️ Polling timeout reached after 30 seconds")
                await MainActor.run {
                    // Show timeout message
                    pollingMessage = "Your payment was successful. Please check back in a few minutes. If your subscription is still not active, contact support."
                    
                    // Invalidate timer
                    pollingTimer?.invalidate()
                    pollingTimer = nil
                }
            }
        }
    }
    
    private func stopPollingAndDismiss() {
        // Stop the timer
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        // Hide the overlay with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isPollingSubscriptionStatus = false
        }
        
        // Dismiss the view after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
    
    private func stopPollingWithError(_ error: String) {
        // Stop the timer
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        // Hide the overlay
        withAnimation(.easeInOut(duration: 0.3)) {
            isPollingSubscriptionStatus = false
        }
        
        // Show error after overlay is hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.errorMessage = error
            self.showPaymentError = true
        }
    }
    
    // Clean up timer on view disappear
    private func cleanupPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPollingSubscriptionStatus = false
    }
}

// MARK: - Plan Recommendation

extension PlanSelectionView {
    private var planRecommendation: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            
            Text("RECOMMENDED FOR YOUR TEAM SIZE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OPSStyle.Colors.warningStatus.opacity(0.1))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Help Me Choose Section
    
    private var helpMeChooseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showHelpMeChoose.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                    
                    Text("HELP ME CHOOSE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Spacer()
                    
                    Image(systemName: showHelpMeChoose ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            
            if showHelpMeChoose {
                VStack(alignment: .leading, spacing: 12) {
                    // Starter plan
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("STARTER (1-3 EMPLOYEES)")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        Text("Perfect for small crews and independent contractors. Includes all core features with up to 3 team members.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    // Remove card backgrounds for minimalist look
                    
                    // Team plan
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.2")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("TEAM (4-10 EMPLOYEES)")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        Text("Ideal for growing companies. Supports up to 10 team members with enhanced collaboration features.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    // Remove card backgrounds for minimalist look
                    
                    // Business plan
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.3")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("BUSINESS (11+ EMPLOYEES)")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        Text("For established companies. Unlimited team members, priority support, and advanced features.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    // Remove card backgrounds for minimalist look
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Plan Card Component

struct PlanCard: View {
    let plan: SubscriptionPlan
    let schedule: PaymentSchedule
    let isSelected: Bool
    let isCurrentPlan: Bool
    let isRecommended: Bool
    let onSelect: () -> Void
    
    private var price: String {
        let amount = schedule == .monthly ? plan.monthlyPrice : plan.annualPrice
        return String(format: "$%.0f", Double(amount) / 100.0)
    }
    
    private var period: String {
        schedule == .monthly ? "/month" : "/year"
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // Current plan badge
                if isCurrentPlan {
                    HStack {
                        Spacer()
                        Text("CURRENT PLAN")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white)
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        // Plan name
                        HStack(spacing: 6) {
                            Text(plan.displayName.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            if isRecommended && !isCurrentPlan {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            }
                        }
                        
                        // Seats
                        Text("\(plan.maxSeats) SEATS")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    
                    Spacer()
                    
                    // Price
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Text(period.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    
                    // Selection indicator
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, isCurrentPlan ? 8 : 14)
                .padding(.bottom, isCurrentPlan ? 14 : 0)
            }
            .background(isSelected ? Color.white.opacity(0.05) : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        isSelected ? Color.white.opacity(0.5) :
                        isCurrentPlan ? Color.white.opacity(0.3) :
                        Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            
            Text(text)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Spacer()
        }
    }
}

// MARK: - PaymentSheetView Wrapper removed - payment sheet now presented directly

// MARK: - Preview

struct PlanSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        PlanSelectionView()
            .environmentObject(SubscriptionManager.shared)
            .environmentObject(DataController())
            .preferredColorScheme(.dark)
    }
}
