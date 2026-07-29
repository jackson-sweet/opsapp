//
//  SiteVisitCaptureQAHost.swift
//  OPS
//
//  DEBUG-only harness for the two site-visit capture bugs. Mirrors
//  ScheduleLongPressQAHost / CatalogSetupQALocalHost: in-memory store, seeded
//  operator, no auth, no network writes.
//
//   • 5d5df5b0 — importing a device contact dismissed the whole visit and left
//     an empty intake form behind. Reproducing it needs the REAL presentation
//     shape (a `.fullScreenCover` over a root screen) and the REAL
//     `CNContactPickerViewController`, because the fault was UIKit's imperative
//     dismissal walking up past the retiring picker sheet onto the cover.
//   • 13c66762 — a lead the durable queue delivers must not report as a failure.
//
//  VISIT PRESENTED / VISIT CLOSED is the assertion surface: after a contact is
//  picked it must still read PRESENTED, and the intake fields must be filled.
//

#if DEBUG
import Contacts
import SwiftData
import SwiftUI

struct SiteVisitCaptureQAHost: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @State private var isReady = false
    @State private var showingVisit = false
    @State private var contactsStatus = "CONTACTS · PENDING"
    @State private var operatorStatus = "OPERATOR · —"

    private static let companyId = "qa_site_visit_company"
    private static let userId = "qa_site_visit_user"

    private static let modelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: OPSSchemaV19.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create site-visit QA container: \(error.localizedDescription)")
        }
    }()

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                Text("// SITE VISIT QA")
                    .font(OPSStyle.Typography.pageTitle)
                    .foregroundColor(OPSStyle.Colors.text)

                Text(contactsStatus)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .accessibilityIdentifier("qa_contacts_state")

                Text(operatorStatus)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .accessibilityIdentifier("qa_operator_state")

                Text(showingVisit ? "VISIT PRESENTED" : "VISIT CLOSED")
                    .font(OPSStyle.Typography.dataValueLg)
                    .foregroundColor(showingVisit ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.roseTextM)
                    .accessibilityIdentifier("qa_visit_state")

                Button {
                    showingVisit = true
                } label: {
                    Text("START SITE VISIT")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .fill(OPSStyle.Colors.opsAccent)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("qa_start_visit")
                .disabled(!isReady)

                Spacer()
            }
            .padding(OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing5)
        }
        .modelContainer(Self.modelContainer)
        .fullScreenCover(isPresented: $showingVisit) {
            SiteVisitCaptureView(opportunity: nil, onCreateProject: { _ in })
                .environmentObject(dataController)
                .modelContainer(Self.modelContainer)
        }
        .task { await prepare() }
        .onReceive(dataController.$currentUser) { user in
            // The real DataController restores (and clears) its own session on
            // launch. This host owns the fiction of a signed-in operator, so any
            // value that is not ours is put back — otherwise the capture console
            // reads an empty company id and never leaves its spinner.
            guard user?.id != Self.userId else { return }
            DispatchQueue.main.async { restoreOperator() }
        }
    }

    @MainActor
    private func prepare() async {
        let context = Self.modelContainer.mainContext

        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )
        restoreOperator()

        contactsStatus = await seedDeviceContact()
        restoreOperator()
        isReady = true
    }

    @MainActor
    private func restoreOperator() {
        let context = Self.modelContainer.mainContext
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        let user = users.first { $0.id == Self.userId } ?? User(
            id: Self.userId,
            firstName: "Site",
            lastName: "QA",
            role: .owner,
            companyId: Self.companyId
        )
        if !users.contains(where: { $0.id == user.id }) {
            context.insert(user)
            try? context.save()
        }

        dataController.currentUser = user
        dataController.isAuthenticated = true
        operatorStatus = "OPERATOR · \(user.companyId ?? "—")"
    }

    /// Puts a known person in the simulator's address book so the real picker
    /// has something to pick. Requires the contacts privacy grant
    /// (`xcrun simctl privacy <udid> grant contacts co.ops.app`).
    private func seedDeviceContact() async -> String {
        let store = CNContactStore()
        let granted = await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        guard granted else { return "CONTACTS · DENIED" }

        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: "Corinne")
        if let existing = try? store.unifiedContacts(matching: predicate, keysToFetch: keys), !existing.isEmpty {
            return "CONTACTS · SEEDED"
        }

        let contact = CNMutableContact()
        contact.givenName = "Corinne"
        contact.familyName = "Robertson"
        contact.organizationName = "West Shore Decks"
        contact.emailAddresses = [
            CNLabeledValue(label: CNLabelWork, value: "corinne@westshoredecks.test" as NSString)
        ]
        contact.phoneNumbers = [
            CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: "250-555-0142")
            )
        ]
        let postal = CNMutablePostalAddress()
        postal.street = "972 Lyall St"
        postal.city = "Esquimalt"
        postal.state = "BC"
        postal.postalCode = "V9A5G8"
        contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: postal as CNPostalAddress)]

        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do {
            try store.execute(request)
            return "CONTACTS · SEEDED"
        } catch {
            return "CONTACTS · SEED FAILED"
        }
    }
}
#endif
