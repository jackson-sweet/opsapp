//
//  PhoneContactImporterTests.swift
//  OPSTests
//


import Contacts
import SwiftData
import XCTest
@testable import OPS

@MainActor
final class PhoneContactImporterTests: XCTestCase {
    func testCreateClientReturnsTheContextManagedSaveBeforeLeadDelivery() async throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        let contact = CNMutableContact()
        contact.givenName = "West Shore"
        contact.familyName = "Decks"
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: "250-555-0199"))]
        let queue = RecordingClientLeadQueue()

        let result = try await PhoneContactImporter.createClient(
            from: contact,
            companyId: "company-1",
            dataController: dataController,
            postSuccessToast: false,
            leadQueue: queue
        )

        XCTAssertTrue(dataController.getClient(id: result.client.id) === result.client)
        XCTAssertEqual(result.client.name, "West Shore Decks")
        XCTAssertNil(result.opportunityId)
        XCTAssertEqual(queue.enqueuedClientId, result.client.id)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertTrue(operations.contains {
            $0.entityType == SyncEntityType.client.rawValue
                && $0.entityId == result.client.id
                && $0.operationType == "create"
        })
    }

    func testFinishedClientImportReturnsSavedClientBeforeLeadDelivery() {
        let client = Client(
            id: "client-1",
            name: "West Shore Decks",
            companyId: "company-1"
        )
        let queue = RecordingClientLeadQueue()

        let result = PhoneContactImporter.finishImport(
            savedClient: client,
            companyId: "company-1",
            postSuccessToast: false,
            leadQueue: queue
        )

        XCTAssertTrue(result.client === client)
        XCTAssertNil(result.opportunityId)
        XCTAssertEqual(queue.enqueuedClientId, "client-1")
        XCTAssertEqual(queue.enqueuedCompanyId, "company-1")
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            SyncOperation.self,
            ProjectVinylOrderMarker.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

@MainActor
private final class RecordingClientLeadQueue: ClientLeadAutocreateQueueing {
    private(set) var enqueuedClientId: String?
    private(set) var enqueuedCompanyId: String?

    func enqueueAndDrainInBackground(_ client: Client, companyId: String) {
        enqueuedClientId = client.id
        enqueuedCompanyId = companyId
    }
}
