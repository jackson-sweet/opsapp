//
//  WhatsNewView.swift
//  OPS
//
//  Shows upcoming features fetched from Supabase, grouped by status then category.
//

import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var categories: [WhatsNewCategoryDTO] = []
    @State private var isLoading = true
    @State private var expandedCategories: Set<String> = []

    // Vote state
    @State private var votingFeatures: Set<String> = []
    @State private var votedFeatures: Set<String> = []
    @State private var showVoteError = false
    @State private var voteErrorMessage = ""

    // Beta access state
    @State private var requestedItemIds: Set<String> = []
    @State private var requestingItemId: String?
    @State private var showCompanySheet = false
    @State private var pendingRequestItemId: String?
    @State private var showRequestConfirm = false
    @State private var showRequestError = false
    @State private var requestErrorMessage = ""

    private let repository = WhatsNewRepository()

    // Group all items by status for section display
    private var statusSections: [(status: WhatsNewStatus, items: [(item: WhatsNewItemDTO, categoryName: String)])] {
        let allItems = categories.flatMap { cat in
            cat.items.map { (item: $0, categoryName: cat.name) }
        }

        let statusOrder: [WhatsNewStatus] = [.inTesting, .inDevelopment, .comingSoon, .planned, .shipped, .completed]

        return statusOrder.compactMap { status in
            let matching = allItems.filter { $0.item.status == status.rawValue }
            guard !matching.isEmpty else { return nil }
            return (status: status, items: matching)
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "WHAT'S COMING",
                    showEditButton: false,
                    onBackTapped: { dismiss() }
                )

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(OPSStyle.Colors.secondaryText)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Intro
                            VStack(alignment: .leading, spacing: 12) {
                                Text("We're always working to make OPS better for our crews.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("Here's what's coming next:".uppercased())
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                            // Status sections
                            VStack(spacing: 20) {
                                ForEach(statusSections, id: \.status) { section in
                                    StatusSection(
                                        status: section.status,
                                        items: section.items,
                                        expandedCategories: expandedCategories,
                                        onToggleCategory: { catName in
                                            withAnimation(OPSStyle.Animation.standard) {
                                                if expandedCategories.contains(catName) {
                                                    expandedCategories.remove(catName)
                                                } else {
                                                    expandedCategories.insert(catName)
                                                }
                                            }
                                        },
                                        votingFeatures: votingFeatures,
                                        votedFeatures: votedFeatures,
                                        requestedItemIds: requestedItemIds,
                                        requestingItemId: requestingItemId,
                                        onVote: voteForFeature,
                                        onRequestAccess: handleRequestAccess
                                    )
                                }
                            }
                            .padding(.horizontal, 20)

                            // Feedback section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Have a Feature Request?")
                                    .font(OPSStyle.Typography.subtitle)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Text("We build OPS based on feedback from actual field crews. Your input shapes our roadmap.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)

                                NavigationLink(destination: FeatureRequestView()) {
                                    HStack {
                                        Image(systemName: OPSStyle.Icons.envelopeFill)
                                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                                            .foregroundColor(OPSStyle.Colors.secondaryText)

                                        Text("Send Feature Request")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                                        Spacer()

                                        Image(systemName: OPSStyle.Icons.chevronRight)
                                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                    .padding()
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                    )
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 32)
                            .padding(.bottom, 40)
                        }
                        .tabBarPadding()
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .enableNativeSwipeBack()
        .alert("Error", isPresented: $showVoteError) {
            Button("OK") { }
        } message: {
            Text(voteErrorMessage)
        }
        .alert("Request Beta Access", isPresented: $showRequestConfirm) {
            Button("Cancel", role: .cancel) { pendingRequestItemId = nil }
            Button("Request Access") {
                if let itemId = pendingRequestItemId {
                    submitBetaRequest(itemId: itemId)
                }
            }
        } message: {
            if let itemId = pendingRequestItemId,
               let item = categories.flatMap({ $0.items }).first(where: { $0.id == itemId }) {
                Text("Request beta access to \(item.title)?")
            } else {
                Text("Request beta access to this feature?")
            }
        }
        .alert("Error", isPresented: $showRequestError) {
            Button("OK") { }
        } message: {
            Text(requestErrorMessage)
        }
        .sheet(isPresented: $showCompanySheet) {
            if let company = dataController.getCurrentUserCompany() {
                CompanyProfileCompletionSheet(company: company) {
                    // Company info now complete, show confirmation
                    if pendingRequestItemId != nil {
                        showRequestConfirm = true
                    }
                }
            }
        }
        .onAppear {
            loadData()
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        // Load cached votes
        if let savedVotes = UserDefaults.standard.array(forKey: "votedFeatures") as? [String] {
            votedFeatures = Set(savedVotes)
        }

        // Load cached request IDs
        if let savedRequests = UserDefaults.standard.array(forKey: "betaRequestedItemIds") as? [String] {
            requestedItemIds = Set(savedRequests)
        }

        // Load cached categories first for instant display
        if let cached = repository.getCachedCategories() {
            categories = cached
            isLoading = false
        }

        // Then fetch fresh data
        Task {
            do {
                let fresh = try await repository.fetchCategories()
                await MainActor.run {
                    categories = fresh
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    if categories.isEmpty {
                        isLoading = false
                    }
                }
            }

            // Reconcile beta request state
            if let userId = dataController.currentUser?.id {
                do {
                    let serverRequestIds = try await repository.fetchUserRequests(userId: userId)
                    await MainActor.run {
                        requestedItemIds = requestedItemIds.union(Set(serverRequestIds))
                        UserDefaults.standard.set(Array(requestedItemIds), forKey: "betaRequestedItemIds")
                    }
                } catch {
                    // Non-critical, keep local state
                }
            }
        }
    }

    // MARK: - Vote

    private func voteForFeature(_ item: WhatsNewItemDTO) {
        guard !votingFeatures.contains(item.title),
              !votedFeatures.contains(item.title) else { return }

        votingFeatures.insert(item.title)

        Task {
            do {
                guard let userEmail = dataController.currentUser?.email else {
                    throw NSError(domain: "WhatsNewView", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
                }

                try await SupabaseService.shared.client
                    .from("feature_requests")
                    .insert([
                        "type": "vote",
                        "title": item.title,
                        "description": item.description,
                        "platform": "iOS mobile",
                        "user_email": userEmail,
                        "status": "new"
                    ])
                    .execute()

                await MainActor.run {
                    votingFeatures.remove(item.title)
                    votedFeatures.insert(item.title)
                    UserDefaults.standard.set(Array(votedFeatures), forKey: "votedFeatures")
                }
            } catch {
                await MainActor.run {
                    votingFeatures.remove(item.title)
                    voteErrorMessage = "Failed to submit vote. Please try again."
                    showVoteError = true
                }
            }
        }
    }

    // MARK: - Beta Access Request

    private func handleRequestAccess(_ item: WhatsNewItemDTO) {
        guard !requestedItemIds.contains(item.id) else { return }

        pendingRequestItemId = item.id

        // Check company profile completeness
        guard let company = dataController.getCurrentUserCompany() else { return }

        let nameOk = !company.name.trimmingCharacters(in: .whitespaces).isEmpty
        let emailOk = !(company.email ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let phoneOk = !(company.phone ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let addressOk = !(company.address ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let sizeOk = !(company.companySize ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let industryOk = !company.getIndustries().isEmpty

        if nameOk && emailOk && phoneOk && addressOk && sizeOk && industryOk {
            showRequestConfirm = true
        } else {
            showCompanySheet = true
        }
    }

    private func submitBetaRequest(itemId: String) {
        guard let user = dataController.currentUser,
              let company = dataController.getCurrentUserCompany() else { return }

        requestingItemId = itemId

        let dto = BetaAccessRequestDTO(
            userId: user.id,
            userEmail: user.email ?? "",
            userName: user.fullName,
            companyId: company.id,
            companyName: company.name,
            whatsNewItemId: itemId,
            companyPhone: company.phone,
            companyAddress: company.address,
            companySize: company.companySize,
            companyIndustries: company.getIndustries()
        )

        Task {
            do {
                try await repository.submitBetaAccessRequest(dto)
                await MainActor.run {
                    requestedItemIds.insert(itemId)
                    UserDefaults.standard.set(Array(requestedItemIds), forKey: "betaRequestedItemIds")
                    requestingItemId = nil
                    pendingRequestItemId = nil
                }
            } catch {
                await MainActor.run {
                    requestingItemId = nil
                    requestErrorMessage = "Failed to submit request. Please try again."
                    showRequestError = true
                }
            }
        }
    }
}

// MARK: - Status Section

private struct StatusSection: View {
    let status: WhatsNewStatus
    let items: [(item: WhatsNewItemDTO, categoryName: String)]
    let expandedCategories: Set<String>
    let onToggleCategory: (String) -> Void
    let votingFeatures: Set<String>
    let votedFeatures: Set<String>
    let requestedItemIds: Set<String>
    let requestingItemId: String?
    let onVote: (WhatsNewItemDTO) -> Void
    let onRequestAccess: (WhatsNewItemDTO) -> Void

    private var statusColor: Color {
        switch status {
        case .inTesting: return OPSStyle.Colors.warningStatus
        case .inDevelopment: return OPSStyle.Colors.primaryText
        case .comingSoon: return OPSStyle.Colors.primaryAccent
        case .planned: return OPSStyle.Colors.tertiaryText
        case .shipped, .completed: return OPSStyle.Colors.successStatus
        }
    }

    private var statusIcon: String {
        switch status {
        case .inTesting: return "flask"
        case .inDevelopment: return "hammer"
        case .comingSoon: return "rocket"
        case .planned: return "lightbulb"
        case .shipped: return "shippingbox"
        case .completed: return "checkmark.circle.fill"
        }
    }

    // Group items by category
    private var categorizedItems: [(categoryName: String, items: [WhatsNewItemDTO])] {
        var grouped: [String: [WhatsNewItemDTO]] = [:]
        for entry in items {
            grouped[entry.categoryName, default: []].append(entry.item)
        }
        return grouped.map { ($0.key, $0.value) }.sorted { $0.categoryName < $1.categoryName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(statusColor)

                Text(status.displayName.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(statusColor)

                Text("(\(items.count))")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Spacer()
            }

            // Items grouped by category
            ForEach(categorizedItems, id: \.categoryName) { group in
                VStack(spacing: 0) {
                    // Category header (collapsible)
                    Button {
                        onToggleCategory("\(status.rawValue)_\(group.categoryName)")
                    } label: {
                        HStack {
                            Text(group.categoryName.uppercased())
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Spacer()

                            Text("\(group.items.count)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)

                            Image(systemName: OPSStyle.Icons.chevronRight)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .rotationEffect(.degrees(expandedCategories.contains("\(status.rawValue)_\(group.categoryName)") ? 90 : 0))
                        }
                        .padding(12)
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Expanded items
                    if expandedCategories.contains("\(status.rawValue)_\(group.categoryName)") {
                        VStack(spacing: 8) {
                            ForEach(group.items) { item in
                                WhatsNewFeatureCard(
                                    item: item,
                                    status: status,
                                    isVoting: votingFeatures.contains(item.title),
                                    hasVoted: votedFeatures.contains(item.title),
                                    isRequested: requestedItemIds.contains(item.id),
                                    isRequesting: requestingItemId == item.id,
                                    onVote: { onVote(item) },
                                    onRequestAccess: { onRequestAccess(item) }
                                )
                                .padding(.leading, 20)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }
}

// MARK: - Feature Card

private struct WhatsNewFeatureCard: View {
    let item: WhatsNewItemDTO
    let status: WhatsNewStatus
    let isVoting: Bool
    let hasVoted: Bool
    let isRequested: Bool
    let isRequesting: Bool
    let onVote: () -> Void
    let onRequestAccess: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .frame(width: 36, height: 36)

                Image(systemName: item.icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                HStack {
                    Text(item.description)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    // Action button based on status
                    if status == .shipped || status == .completed {
                        // Green checkmark
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.lg))
                            .foregroundColor(OPSStyle.Colors.successStatus)
                    } else if status == .inTesting {
                        // Request Access button
                        Button(action: onRequestAccess) {
                            HStack(spacing: 4) {
                                if isRequesting {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(OPSStyle.Colors.warningStatus)
                                } else {
                                    Image(systemName: isRequested ? "checkmark.circle.fill" : "flask")
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    Text(isRequested ? "Requested" : "Request Access")
                                        .font(OPSStyle.Typography.caption)
                                }
                            }
                            .foregroundColor(isRequested ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isRequested ? OPSStyle.Colors.successStatus.opacity(0.2) : OPSStyle.Colors.warningStatus.opacity(0.2)
                            )
                            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(
                                        isRequested ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus,
                                        lineWidth: OPSStyle.Layout.Border.standard
                                    )
                            )
                        }
                        .disabled(isRequested || isRequesting)
                    } else {
                        // Vote +1 button
                        Button(action: onVote) {
                            HStack(spacing: 4) {
                                Image(systemName: hasVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                Text("+1")
                                    .font(OPSStyle.Typography.caption)
                            }
                            .foregroundColor(hasVoted ? OPSStyle.Colors.successStatus : OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                hasVoted ? OPSStyle.Colors.successStatus.opacity(0.2) : OPSStyle.Colors.cardBackgroundDark
                            )
                            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(
                                        hasVoted ? OPSStyle.Colors.successStatus : OPSStyle.Colors.cardBorder,
                                        lineWidth: OPSStyle.Layout.Border.standard
                                    )
                            )
                        }
                        .disabled(isVoting || hasVoted)
                        .opacity(isVoting ? 0.6 : 1.0)
                    }
                }
            }
        }
        .padding(12)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

#Preview {
    NavigationStack {
        WhatsNewView()
            .environmentObject(DataController())
    }
    .preferredColorScheme(.dark)
}
