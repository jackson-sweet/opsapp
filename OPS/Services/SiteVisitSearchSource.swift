import Foundation
import SwiftData
import Combine

/// Local clients render synchronously; remote suggestions never own form state.
@MainActor
final class SiteVisitSearchSource: ObservableObject {
    typealias Search = (String, String) async throws -> [OpportunityDTO]
    @Published private(set) var clients: [Client] = []
    @Published private(set) var leads: [Opportunity] = []
    private var generation = 0
    private var successfulResponseRevision = 0
    private var owner: String?
    private let search: Search

    init(search: @escaping Search = { company, query in
        try await OpportunityRepository(companyId: company).searchForSiteVisit(query)
    }) { self.search = search }

    func loadLocalClients(context: ModelContext, companyId: String) {
        let company = companyId.lowercased()
        clients = (try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate {
            $0.companyId == company && $0.deletedAt == nil
        }, sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func loadCachedLeads(companyId: String, userId: String) async {
        let key = "\(companyId.lowercased())::\(userId.lowercased())"
        if owner != key { leads = []; owner = key }
        let responseRevision = successfulResponseRevision
        let snapshot = await Task.detached(priority: .utility) {
            DaySheetCache.shared.load(userId: userId, companyId: companyId)?.dtos ?? []
        }.value
        guard !Task.isCancelled, responseRevision == successfulResponseRevision, owner == key else { return }
        owner = key
        leads = snapshot.map { $0.toModel() }.filter {
            $0.companyId.lowercased() == companyId.lowercased()
                && !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived
        }
    }

    func refresh(query: String, companyId: String, userId: String) async {
        let key = "\(companyId.lowercased())::\(userId.lowercased())"
        if owner != key { leads = []; owner = key }
        generation += 1
        let request = generation
        do {
            let rows = try await search(companyId, query)
            guard !Task.isCancelled, generation == request, owner == key else { return }
            successfulResponseRevision += 1
            leads = rows.map { $0.toModel() }.filter {
                $0.companyId.lowercased() == companyId.lowercased()
                    && !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived
            }
        } catch {
            // Keep usable local suggestions. A delayed/error response never
            // rewrites the active identity draft or replaces a newer request.
        }
    }
}
