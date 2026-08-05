//
//  LeadsQueryEngineTests.swift
//  OPSTests
//
//  The LEADS console redesign (2026-08-05) moved search, sort, crew filtering,
//  roster resolution and band-state selection out of the view and into one
//  pure engine. These tests are the contract: every rule the console renders
//  is pinned here so the view can stay dumb.
//
//  Fixtures are built on the shipped `Opportunity.preview` factory and widened
//  with a local builder for the fields the factory does not expose (address,
//  email, phone, description, source, exact createdAt).
//

import XCTest
@testable import OPS

/// Ids are fixed rather than random so `shortDisplayId` (last 6 of the
/// un-hyphenated uuid) is a known quantity — several tests assert on it, and
/// the digit-token tests need a lead whose id carries no stray digits.
/// File scope: a default argument cannot reference `Self`.
private let plainLeadId = "00000000-0000-0000-0000-0000000000a1"

final class LeadsQueryEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func lead(
        id: String = plainLeadId,
        contactName: String = "Dana Whitfield",
        title: String? = nil,
        description: String? = nil,
        address: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        source: String? = nil,
        stage: PipelineStage = .quoted,
        estimatedValue: Double? = nil,
        assignedTo: String? = nil,
        createdAt: Date? = nil
    ) -> Opportunity {
        let opp = Opportunity.preview(
            id: id,
            title: title,
            contactName: contactName,
            stage: stage,
            estimatedValue: estimatedValue,
            assignedTo: assignedTo
        )
        opp.descriptionText = description
        opp.address = address
        opp.contactEmail = email
        opp.contactPhone = phone
        opp.source = source
        if let createdAt { opp.createdAt = createdAt }
        return opp
    }

    /// Distinct ids per fixture so the assertions compare identity, not content.
    private func numbered(
        _ index: Int,
        name: String,
        title: String? = nil,
        value: Double? = nil,
        assignedTo: String? = nil,
        createdDaysAgo: Int = 0
    ) -> Opportunity {
        lead(
            id: "0000000\(index)-0000-0000-0000-00000000000\(index)",
            contactName: name,
            title: title,
            estimatedValue: value,
            assignedTo: assignedTo,
            createdAt: Date().addingTimeInterval(-Double(createdDaysAgo) * 86_400)
        )
    }

    private func buckets(
        overdue: [Opportunity] = [],
        dueToday: [Opportunity] = [],
        waitingOnYou: [Opportunity] = [],
        fresh: [Opportunity] = [],
        waitingOnThem: [Opportunity] = [],
        unconvertedWon: [Opportunity] = []
    ) -> PipelineViewModel.TriageBuckets {
        PipelineViewModel.TriageBuckets(
            overdue: overdue,
            dueToday: dueToday,
            waitingOnYou: waitingOnYou,
            fresh: fresh,
            waitingOnThem: waitingOnThem,
            unconvertedWon: unconvertedWon
        )
    }

    private func controls(
        query: String = "",
        sort: LeadSort = .urgency,
        crew: CrewFilter = .all
    ) -> LeadsListControls {
        LeadsListControls(query: query, sort: sort, crew: crew)
    }

    private func flatLeads(
        _ result: LeadsQueryResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Opportunity] {
        guard case .flat(let leads) = result else {
            XCTFail("Expected a flat result", file: file, line: line)
            return []
        }
        return leads
    }

    private func groups(
        _ result: LeadsQueryResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [(bucket: PipelineViewModel.TriageBucket, leads: [Opportunity])] {
        guard case .grouped(let groups) = result else {
            XCTFail("Expected a grouped result", file: file, line: line)
            return []
        }
        return groups
    }

    // MARK: - Controls defaults

    func testControlsDefaultToUrgencyAllCrewNoQuery() {
        let controls = LeadsListControls()
        XCTAssertEqual(controls.query, "")
        XCTAssertEqual(controls.sort, .urgency)
        XCTAssertEqual(controls.crew, .all)
        XCTAssertFalse(controls.isSearching)
    }

    func testControlsIsSearchingIgnoresWhitespaceOnlyQuery() {
        var controls = LeadsListControls()
        controls.query = "   \n "
        XCTAssertFalse(controls.isSearching, "A whitespace-only query must not suspend browse filters")
        controls.query = " dana "
        XCTAssertTrue(controls.isSearching)
    }

    // MARK: - Search matching · fields

    func testMatchesContactName() {
        let lead = lead(contactName: "Dana Whitfield")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "whitfield"))
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "WHIT"))
    }

    /// A lead with no contact name falls back to its title for display — the
    /// engine searches the same string the card shows.
    func testMatchesDisplayNameFallbackWhenContactNameBlank() {
        let lead = lead(contactName: "", title: "Website enquiry — cedar fence")
        XCTAssertEqual(lead.displayContactName, "Website enquiry — cedar fence")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "cedar"))
    }

    func testMatchesTitle() {
        let lead = lead(title: "Roof replacement")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "replacement"))
    }

    func testMatchesDescriptionText() {
        let lead = lead(description: "Needs a quote for the back deck railing")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "railing"))
    }

    func testMatchesAddress() {
        let lead = lead(address: "1440 Beacon Hill Road, Kelowna")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "kelowna"))
    }

    func testMatchesContactEmail() {
        let lead = lead(email: "dana@northgatefitness.com")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "northgate"))
    }

    func testMatchesSource() {
        let lead = lead(source: "referral")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "referral"))
    }

    func testMatchesShortDisplayId() {
        let lead = lead(id: "9f2b7c1e-4a55-4d2e-9b3c-1122ff9911")
        XCTAssertEqual(lead.shortDisplayId, "L-FF9911")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "ff9911"))
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "L-FF9911"))
    }

    func testUnrelatedQueryDoesNotMatch() {
        let lead = lead(contactName: "Dana Whitfield", title: "Roof replacement")
        XCTAssertFalse(LeadsQueryEngine.matches(lead, query: "furnace"))
    }

    // MARK: - Search matching · folding

    func testMatchIsDiacriticInsensitiveInBothDirections() {
        let accented = lead(contactName: "Ana Muñoz")
        XCTAssertTrue(LeadsQueryEngine.matches(accented, query: "munoz"),
                      "An unaccented query must reach an accented name")

        let plain = lead(contactName: "Ana Munoz")
        XCTAssertTrue(LeadsQueryEngine.matches(plain, query: "Muñoz"),
                      "An accented query must reach an unaccented name")
    }

    // MARK: - Search matching · multi-token AND

    func testMultiTokenQueryRequiresEveryToken() {
        let hit = lead(contactName: "Dana Whitfield", title: "Roof replacement")
        XCTAssertTrue(LeadsQueryEngine.matches(hit, query: "dana roof"))

        let miss = lead(contactName: "Dana Whitfield", title: "Deck rebuild")
        XCTAssertFalse(LeadsQueryEngine.matches(miss, query: "dana roof"),
                       "Every token must hit a field — one match is not enough")
    }

    func testMultiTokenQueryCollapsesExtraWhitespace() {
        let hit = lead(contactName: "Dana Whitfield", title: "Roof replacement")
        XCTAssertTrue(LeadsQueryEngine.matches(hit, query: "  dana   roof \n"))
    }

    // MARK: - Search matching · phone digits

    func testPhoneMatchesThroughFormattingWhenQueryCarriesThreeOrMoreDigits() {
        let lead = lead(contactName: "Pat Donovan", phone: "(555) 123-4567")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "5551234"))
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "555-1234"),
                      "The query's own formatting must be normalised away too")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "1234567"),
                      "A digit run from the middle of the number still matches")
    }

    func testShortDigitTokenDoesNotReachThePhonePath() {
        let lead = lead(contactName: "Pat Donovan", phone: "(555) 123-4567")
        XCTAssertFalse(LeadsQueryEngine.matches(lead, query: "55"),
                       "Under 3 digits the phone path stays shut — every lead would match otherwise")
    }

    func testPhonePathIsNotConsultedWhenLeadHasNoPhone() {
        let lead = lead(contactName: "Pat Donovan", phone: nil)
        XCTAssertFalse(LeadsQueryEngine.matches(lead, query: "5551234"))
    }

    func testMixedTokenQueryCombinesTextAndPhone() {
        let lead = lead(contactName: "Pat Donovan", phone: "(555) 123-4567")
        XCTAssertTrue(LeadsQueryEngine.matches(lead, query: "donovan 5551234"))
        XCTAssertFalse(LeadsQueryEngine.matches(lead, query: "donovan 9998888"))
    }

    // MARK: - Search matching · empty query

    func testEmptyQueryMatchesEveryLead() {
        let a = lead(contactName: "Dana Whitfield")
        let b = lead(id: "11111111-2222-3333-4444-5566778899aa", contactName: "Cedar Ridge HOA")
        for query in ["", "   ", "\n\t"] {
            XCTAssertTrue(LeadsQueryEngine.matches(a, query: query))
            XCTAssertTrue(LeadsQueryEngine.matches(b, query: query))
        }
    }

    // MARK: - apply · grouped browse (URGENCY, no query)

    func testUrgencyGroupsInTheQueuesVisualBrowseOrder() {
        let b = buckets(
            overdue: [numbered(1, name: "Overdue One")],
            dueToday: [numbered(2, name: "Due Two")],
            waitingOnYou: [numbered(3, name: "Move Three")],
            fresh: [numbered(4, name: "Fresh Four")],
            waitingOnThem: [numbered(5, name: "Waiting Five")]
        )
        let result = LeadsQueryEngine.apply(controls: controls(), buckets: b,
                                            selectedBucket: .all, currentUserId: "u-1")

        XCTAssertEqual(groups(result).map(\.bucket),
                       [.overdue, .dueToday, .waitingOnYou, .waitingOnThem, .fresh],
                       "Browse order puts WAITING above FRESH — the queue's own visual order")
        XCTAssertEqual(groups(result).map(\.bucket), LeadsQueryEngine.groupOrder)
    }

    func testGroupedResultSkipsEmptyBuckets() {
        let b = buckets(
            overdue: [numbered(1, name: "Overdue One")],
            waitingOnThem: [numbered(5, name: "Waiting Five")]
        )
        let result = LeadsQueryEngine.apply(controls: controls(), buckets: b,
                                            selectedBucket: .all, currentUserId: "u-1")
        XCTAssertEqual(groups(result).map(\.bucket), [.overdue, .waitingOnThem])
    }

    func testGroupedResultPreservesInBucketOrder() {
        let first = numbered(1, name: "First")
        let second = numbered(2, name: "Second")
        let result = LeadsQueryEngine.apply(controls: controls(), buckets: buckets(overdue: [first, second]),
                                            selectedBucket: .all, currentUserId: "u-1")
        XCTAssertEqual(groups(result).first?.leads, [first, second])
    }

    // MARK: - apply · crew filter (AND)

    func testCrewFilterAndsIntoEveryGroupAndDropsEmptiedOnes() {
        let mine = numbered(1, name: "Mine One", assignedTo: "USER-1")
        let theirs = numbered(2, name: "Theirs Two", assignedTo: "user-2")
        let alsoTheirs = numbered(3, name: "Theirs Three", assignedTo: "user-2")
        let b = buckets(overdue: [mine, theirs], waitingOnThem: [alsoTheirs])

        let result = LeadsQueryEngine.apply(controls: controls(crew: .mine), buckets: b,
                                            selectedBucket: .all, currentUserId: "user-1")

        XCTAssertEqual(groups(result).map(\.bucket), [.overdue],
                       "A bucket emptied by the crew filter drops out of the grouped result")
        XCTAssertEqual(groups(result).first?.leads, [mine])
    }

    func testCrewFilterAppliesToFlatSortsToo() {
        let unassigned = numbered(1, name: "Nobody's", assignedTo: nil, createdDaysAgo: 5)
        let assigned = numbered(2, name: "Somebody's", assignedTo: "user-2", createdDaysAgo: 1)
        let b = buckets(overdue: [assigned], waitingOnThem: [unassigned])

        let result = LeadsQueryEngine.apply(controls: controls(sort: .newest, crew: .unassigned),
                                            buckets: b, selectedBucket: .all, currentUserId: "user-1")
        XCTAssertEqual(flatLeads(result), [unassigned])
    }

    // MARK: - apply · bucket chip

    func testActiveBucketChipFlattensToThatBucket() {
        let overdueLead = numbered(1, name: "Overdue One")
        let freshLead = numbered(2, name: "Fresh Two")
        let b = buckets(overdue: [overdueLead], fresh: [freshLead])

        let result = LeadsQueryEngine.apply(controls: controls(), buckets: b,
                                            selectedBucket: .overdue, currentUserId: "u-1")
        XCTAssertEqual(flatLeads(result), [overdueLead])
    }

    func testEmptyBucketChipFallsBackToTheGroupedAllView() {
        let b = buckets(fresh: [numbered(2, name: "Fresh Two")])

        let result = LeadsQueryEngine.apply(controls: controls(), buckets: b,
                                            selectedBucket: .dueToday, currentUserId: "u-1")
        XCTAssertEqual(groups(result).map(\.bucket), [.fresh],
                       "An emptied chip falls back to ALL rather than stranding an empty list")
        XCTAssertEqual(LeadsQueryEngine.effectiveBucket(.dueToday, in: b), .all)
        XCTAssertEqual(LeadsQueryEngine.effectiveBucket(.fresh, in: b), .fresh)
    }

    // MARK: - apply · NEWEST

    func testNewestSortFlattensByCreatedAtDescending() {
        let oldest = numbered(1, name: "Oldest", createdDaysAgo: 30)
        let newest = numbered(2, name: "Newest", createdDaysAgo: 1)
        let middle = numbered(3, name: "Middle", createdDaysAgo: 10)
        let b = buckets(overdue: [oldest], fresh: [newest], waitingOnThem: [middle])

        let result = LeadsQueryEngine.apply(controls: controls(sort: .newest), buckets: b,
                                            selectedBucket: .all, currentUserId: "u-1")
        XCTAssertEqual(flatLeads(result), [newest, middle, oldest])
    }

    // MARK: - apply · VALUE

    func testValueSortRanksDescendingWithUnpricedLast() {
        let big = numbered(1, name: "Big", value: 78_500)
        let small = numbered(2, name: "Small", value: 6_200)
        let zero = numbered(3, name: "Zero", value: 0)
        let none = numbered(4, name: "None", value: nil)
        let b = buckets(overdue: [zero, none, small, big])

        let ordered = flatLeads(LeadsQueryEngine.apply(controls: controls(sort: .value), buckets: b,
                                                       selectedBucket: .all, currentUserId: "u-1"))
        XCTAssertEqual(ordered.prefix(2).map(\.id), [big.id, small.id])
        XCTAssertEqual(Set(ordered.suffix(2).map(\.id)), [zero.id, none.id],
                       "Nil and zero both mean unpriced — both sink below every priced lead")
    }

    func testValueSortBreaksTiesByNewest() {
        let older = numbered(1, name: "Older", value: 10_000, createdDaysAgo: 9)
        let newer = numbered(2, name: "Newer", value: 10_000, createdDaysAgo: 2)
        let b = buckets(overdue: [older, newer])

        let result = LeadsQueryEngine.apply(controls: controls(sort: .value), buckets: b,
                                            selectedBucket: .all, currentUserId: "u-1")
        XCTAssertEqual(flatLeads(result), [newer, older])
    }

    // MARK: - apply · search suspension

    func testSearchSuspendsTheBucketChipAndTheCrewFilter() {
        let theirFresh = numbered(1, name: "Dana Whitfield", assignedTo: "user-2")
        let b = buckets(overdue: [numbered(2, name: "Someone Else")], fresh: [theirFresh])

        let result = LeadsQueryEngine.apply(
            controls: controls(query: "dana", crew: .mine),
            buckets: b,
            selectedBucket: .overdue,
            currentUserId: "user-1"
        )
        XCTAssertEqual(flatLeads(result), [theirFresh],
                       "Search reaches every lead the tab owns — no hidden filter may swallow a hit")
    }

    func testSearchPopulationIncludesUnconvertedWins() {
        let won = numbered(1, name: "Tom Liu")
        let open = numbered(2, name: "Tom Liuson")
        let b = buckets(overdue: [open], unconvertedWon: [won])

        let result = LeadsQueryEngine.apply(controls: controls(query: "tom liu"), buckets: b,
                                            selectedBucket: .all, currentUserId: "u-1")
        XCTAssertEqual(Set(flatLeads(result).map(\.id)), [won.id, open.id])
    }

    func testSearchUrgencyOrderFollowsTriagePriorityThenUnconvertedWins() {
        let overdueLead = numbered(1, name: "Cedar Overdue")
        let dueLead = numbered(2, name: "Cedar Due")
        let moveLead = numbered(3, name: "Cedar Move")
        let freshLead = numbered(4, name: "Cedar Fresh")
        let waitingLead = numbered(5, name: "Cedar Waiting")
        let wonLead = numbered(6, name: "Cedar Won")
        let b = buckets(overdue: [overdueLead], dueToday: [dueLead], waitingOnYou: [moveLead],
                        fresh: [freshLead], waitingOnThem: [waitingLead], unconvertedWon: [wonLead])

        let ordered = flatLeads(LeadsQueryEngine.apply(controls: controls(query: "cedar"), buckets: b,
                                                       selectedBucket: .all, currentUserId: "u-1"))

        XCTAssertEqual(ordered, b.all + b.unconvertedWon,
                       "Search order IS TriageBuckets.all order (fresh before waiting), wins last")
        XCTAssertEqual(ordered.map(\.id),
                       [overdueLead.id, dueLead.id, moveLead.id, freshLead.id, waitingLead.id, wonLead.id])
    }

    func testSearchAlwaysFlattensEvenUnderUrgency() {
        let b = buckets(overdue: [numbered(1, name: "Dana Whitfield")])
        let result = LeadsQueryEngine.apply(controls: controls(query: "dana"), buckets: b,
                                            selectedBucket: .all, currentUserId: "u-1")
        guard case .flat = result else { return XCTFail("Search must never group") }
    }

    func testSearchHonoursTheActiveSort() {
        let older = numbered(1, name: "Cedar Older", createdDaysAgo: 20)
        let newer = numbered(2, name: "Cedar Newer", createdDaysAgo: 2)
        let b = buckets(overdue: [older], fresh: [newer])

        let result = LeadsQueryEngine.apply(controls: controls(query: "cedar", sort: .newest),
                                            buckets: b, selectedBucket: .all, currentUserId: "u-1")
        XCTAssertEqual(flatLeads(result), [newer, older])
    }

    func testSearchWithNoHitsReturnsAnEmptyFlatResult() {
        let b = buckets(overdue: [numbered(1, name: "Dana Whitfield")])
        let result = LeadsQueryEngine.apply(controls: controls(query: "furnace"), buckets: b,
                                            selectedBucket: .all, currentUserId: "u-1")
        XCTAssertEqual(flatLeads(result), [])
    }

    // MARK: - crewMatches

    func testCrewMatchesAllAcceptsEveryLead() {
        XCTAssertTrue(LeadsQueryEngine.crewMatches(lead(assignedTo: "user-2"),
                                                   filter: .all, currentUserId: "user-1"))
        XCTAssertTrue(LeadsQueryEngine.crewMatches(lead(assignedTo: nil),
                                                   filter: .all, currentUserId: nil))
    }

    func testCrewMatchesMineFoldsCaseOnBothSides() {
        let upper = lead(assignedTo: "6F2B7C1E-4A55-4D2E-9B3C-1122FF9911")
        XCTAssertTrue(
            LeadsQueryEngine.crewMatches(upper, filter: .mine,
                                         currentUserId: "6f2b7c1e-4a55-4d2e-9b3c-1122ff9911"),
            "UUID().uuidString is uppercase; Postgres stores uuids lowercased"
        )
    }

    func testCrewMatchesMineIsFalseWithoutAnIdentity() {
        XCTAssertFalse(LeadsQueryEngine.crewMatches(lead(assignedTo: "user-1"),
                                                    filter: .mine, currentUserId: nil))
    }

    func testCrewMatchesUnassignedCoversNilAndBlank() {
        XCTAssertTrue(LeadsQueryEngine.crewMatches(lead(assignedTo: nil),
                                                   filter: .unassigned, currentUserId: "user-1"))
        XCTAssertTrue(LeadsQueryEngine.crewMatches(lead(assignedTo: "   "),
                                                   filter: .unassigned, currentUserId: "user-1"))
        XCTAssertFalse(LeadsQueryEngine.crewMatches(lead(assignedTo: "user-2"),
                                                    filter: .unassigned, currentUserId: "user-1"))
    }

    func testCrewMatchesMemberFoldsCase() {
        let upper = lead(assignedTo: "USER-2")
        XCTAssertTrue(LeadsQueryEngine.crewMatches(upper, filter: .member("user-2"), currentUserId: "user-1"))
        XCTAssertFalse(LeadsQueryEngine.crewMatches(upper, filter: .member("user-3"), currentUserId: "user-1"))
    }
}
