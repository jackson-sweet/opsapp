//
//  FinancialSheetSnapshotTests.swift
//  OPSTests
//
//  Proof harness for the two Pete Mitchell EstimateDetail reports (2026-07-14):
//
//  Bug a8e156a2 — "line items displayed properly": estimate rows showed no
//  quantity × unit-price math, all money was rounded to whole dollars, and
//  fractional tax rates (7.5%) displayed rounded (8%). Fixtures below include
//  an exact replica of the estimate Pete was looking at (QB-220: 2 × $250),
//  a cents + fractional-tax + discount + optional-item document, bundle
//  parent/child documents in both BUNDLED and BREAKDOWN states, and the
//  empty case — for both the estimate and invoice sheets.
//
//  Bug ce6da104 — "FAB hidden on estimate/invoice/expense sheets": asserts
//  that mounting each of the three financial detail screens flips the shared
//  TabBarVisibilityController to hidden (the screens' `.hidesGlobalTabBar()`
//  contract), and pins MainTabView's extracted `fabVisible` rule so a hidden
//  tab bar always hides the FAB with it.
//
//  Renders via UIHostingController + scene-adopting UIWindow + drawHierarchy
//  (ImageRenderer skips onAppear and leaves ScrollView content unresolved).
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/FinancialSheetSnapshotTests
//  Shots land in NSTemporaryDirectory()/ops-financial-sheets-shots.
//

#if DEBUG
import XCTest
import SwiftUI
import SwiftData
@testable import OPS

@MainActor
final class FinancialSheetSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-financial-sheets-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Window harness

    private func makeWindow(size: CGSize) -> UIWindow {
        // The window MUST adopt the app host's scene — an unsceened window is
        // never picked up by the render server, so drawHierarchy silently
        // produces a blank image.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window: UIWindow
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        return window
    }

    private func snapshot<V: View>(
        _ name: String,
        height: CGFloat = 852,
        settle: TimeInterval = 0.4,
        @ViewBuilder _ content: () -> V
    ) {
        let size = CGSize(width: deviceWidth, height: height)
        let host = UIHostingController(
            rootView: content()
                .frame(width: deviceWidth)
                .background(OPSStyle.Colors.background)
                .environment(\.colorScheme, .dark)
        )
        host.view.backgroundColor = .black

        let window = makeWindow(size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@3x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name)@3x.png"))
        window.isHidden = true
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    // MARK: - SwiftData fixtures

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Estimate.self, EstimateLineItem.self,
                 Invoice.self, InvoiceLineItem.self,
                 Payment.self, TaskType.self,
            configurations: config
        )
    }

    @discardableResult
    private func estimateItem(
        _ ctx: ModelContext,
        estimateId: String,
        name: String,
        type: LineItemType,
        quantity: Double,
        unit: String?,
        unitPrice: Double,
        lineTotal: Double,
        order: Int,
        optional: Bool = false,
        parentId: String? = nil,
        resolvedUnitPrice: Double? = nil,
        resolvedOptionsLabel: String? = nil
    ) -> EstimateLineItem {
        let item = EstimateLineItem(
            estimateId: estimateId, name: name, type: type,
            quantity: quantity, unitPrice: unitPrice, displayOrder: order
        )
        item.unit = unit
        item.lineTotal = lineTotal // server-generated column value
        item.optional = optional
        item.parentLineItemId = parentId
        item.resolvedUnitPrice = resolvedUnitPrice
        item.resolvedOptionsLabel = resolvedOptionsLabel
        ctx.insert(item)
        return item
    }

    @discardableResult
    private func invoiceItem(
        _ ctx: ModelContext,
        invoiceId: String,
        name: String,
        type: LineItemType,
        quantity: Double,
        unit: String?,
        unitPrice: Double,
        lineTotal: Double,
        order: Int,
        parentId: String? = nil,
        resolvedUnitPrice: Double? = nil,
        resolvedOptionsLabel: String? = nil
    ) -> InvoiceLineItem {
        let item = InvoiceLineItem(
            invoiceId: invoiceId, name: name, type: type,
            quantity: quantity, unitPrice: unitPrice, displayOrder: order
        )
        item.unit = unit
        item.lineTotal = lineTotal
        item.parentLineItemId = parentId
        item.resolvedUnitPrice = resolvedUnitPrice
        item.resolvedOptionsLabel = resolvedOptionsLabel
        ctx.insert(item)
        return item
    }

    /// Exact replica of the estimate Pete Mitchell had open when he filed
    /// a8e156a2 — QB-220: one LABOR line, 2 each × $250.00, 13% tax, $565.00.
    /// Before the fix this row rendered as name + "$500" with no math at all.
    private func seedQB220(_ ctx: ModelContext) -> Estimate {
        let est = Estimate(companyId: "co", estimateNumber: "QB-220", status: .approved, taxRate: 13)
        est.subtotal = 500.00
        est.taxAmount = 65.00
        est.total = 565.00
        est.createdAt = Date(timeIntervalSinceNow: -86_400 * 38)
        ctx.insert(est)
        estimateItem(ctx, estimateId: est.id,
                     name: "LIVE-QBO-MAP-mq4anho6 mapped install",
                     type: .labor, quantity: 2, unit: "each",
                     unitPrice: 250.00, lineTotal: 500.00, order: 1)
        return est
    }

    /// Cents on every amount, a 7.5% tax rate, a 10% document discount, an
    /// OPTIONAL line, and a fractional quantity — the precision cases the old
    /// whole-dollar / %.0f rendering misdisplayed. Inserted out of order to
    /// prove displayOrder sorting.
    private func seedCentsEstimate(_ ctx: ModelContext) -> Estimate {
        let est = Estimate(companyId: "co", estimateNumber: "EST-0142", status: .sent, taxRate: 7.5, discountPercent: 10)
        est.title = "Back deck refresh"
        est.subtotal = 1_776.08
        est.taxAmount = 119.89
        est.total = 1_718.36
        est.createdAt = Date(timeIntervalSinceNow: -86_400 * 2)
        ctx.insert(est)
        estimateItem(ctx, estimateId: est.id, name: "Stain + seal",
                     type: .other, quantity: 1, unit: "each",
                     unitPrice: 224.00, lineTotal: 224.00, order: 3, optional: true)
        estimateItem(ctx, estimateId: est.id, name: "Cedar decking boards",
                     type: .material, quantity: 42.5, unit: "sq ft",
                     unitPrice: 28.79, lineTotal: 1_223.58, order: 1)
        estimateItem(ctx, estimateId: est.id, name: "Install labor",
                     type: .labor, quantity: 6.5, unit: "hr",
                     unitPrice: 85.00, lineTotal: 552.50, order: 2)
        return est
    }

    /// Deck-flow bundle: parent carries the money (1 × sum of children),
    /// children are the material breakdown — including a configured product
    /// whose resolved snapshot price differs from its base price.
    private func seedBundleEstimate(_ ctx: ModelContext) -> Estimate {
        let est = Estimate(companyId: "co", estimateNumber: "EST-0143", status: .draft, taxRate: 5)
        est.title = "Dock rebuild — bundled scope"
        est.subtotal = 1_001.50
        est.taxAmount = 50.08
        est.total = 1_051.58
        ctx.insert(est)
        let parent = estimateItem(ctx, estimateId: est.id, name: "Deck Installation",
                                  type: .labor, quantity: 1, unit: nil,
                                  unitPrice: 1_001.50, lineTotal: 1_001.50, order: 0)
        estimateItem(ctx, estimateId: est.id, name: "Composite boards 20ft",
                     type: .material, quantity: 38, unit: "sq ft",
                     unitPrice: 12.50, lineTotal: 475.00, order: 1, parentId: parent.id)
        estimateItem(ctx, estimateId: est.id, name: "Fascia board",
                     type: .material, quantity: 12, unit: "each",
                     unitPrice: 7.50, lineTotal: 99.00, order: 2, parentId: parent.id,
                     resolvedUnitPrice: 8.25, resolvedOptionsLabel: "Black")
        estimateItem(ctx, estimateId: est.id, name: "Joist tape",
                     type: .material, quantity: 150, unit: "lin ft",
                     unitPrice: 2.85, lineTotal: 427.50, order: 3, parentId: parent.id)
        return est
    }

    private func seedEmptyEstimate(_ ctx: ModelContext) -> Estimate {
        let est = Estimate(companyId: "co", estimateNumber: "EST-0144", status: .draft)
        ctx.insert(est)
        return est
    }

    /// Cents + partial payment — PAID and BALANCE DUE rows live.
    private func seedPaymentsInvoice(_ ctx: ModelContext) -> Invoice {
        let inv = Invoice(companyId: "co", invoiceNumber: "INV-0087", status: .partiallyPaid, taxRate: 13)
        inv.title = "Furnace service"
        inv.subtotal = 264.54
        inv.taxAmount = 34.39
        inv.total = 298.93
        inv.amountPaid = 150.00
        inv.balanceDue = 148.93
        inv.dueDate = Date(timeIntervalSinceNow: 86_400 * 12)
        ctx.insert(inv)
        invoiceItem(ctx, invoiceId: inv.id, name: "Service call",
                    type: .labor, quantity: 1, unit: "each",
                    unitPrice: 189.99, lineTotal: 189.99, order: 1)
        invoiceItem(ctx, invoiceId: inv.id, name: "Parts — copper fitting",
                    type: .material, quantity: 3, unit: "each",
                    unitPrice: 24.85, lineTotal: 74.55, order: 2)
        let payment = Payment(invoiceId: inv.id, companyId: "co", amount: 150.00, method: .check,
                              paidAt: Date(timeIntervalSinceNow: -86_400 * 3))
        ctx.insert(payment)
        return inv
    }

    /// A converted bundle — convert_estimate_to_invoice copies children with
    /// remapped parent ids, so the invoice sheet must group them exactly like
    /// the estimate sheet (flat rendering double-counted every bundle).
    private func seedBundleInvoice(_ ctx: ModelContext) -> Invoice {
        let inv = Invoice(companyId: "co", invoiceNumber: "INV-0088", status: .awaitingPayment, taxRate: 5)
        inv.title = "Dock rebuild — bundled scope"
        inv.subtotal = 1_001.50
        inv.taxAmount = 50.08
        inv.total = 1_051.58
        inv.balanceDue = 1_051.58
        inv.dueDate = Date(timeIntervalSinceNow: 86_400 * 30)
        ctx.insert(inv)
        let parent = invoiceItem(ctx, invoiceId: inv.id, name: "Deck Installation",
                                 type: .labor, quantity: 1, unit: nil,
                                 unitPrice: 1_001.50, lineTotal: 1_001.50, order: 0)
        invoiceItem(ctx, invoiceId: inv.id, name: "Composite boards 20ft",
                    type: .material, quantity: 38, unit: "sq ft",
                    unitPrice: 12.50, lineTotal: 475.00, order: 1, parentId: parent.id)
        invoiceItem(ctx, invoiceId: inv.id, name: "Fascia board",
                    type: .material, quantity: 12, unit: "each",
                    unitPrice: 7.50, lineTotal: 99.00, order: 2, parentId: parent.id,
                    resolvedUnitPrice: 8.25, resolvedOptionsLabel: "Black")
        invoiceItem(ctx, invoiceId: inv.id, name: "Joist tape",
                    type: .material, quantity: 150, unit: "lin ft",
                    unitPrice: 2.85, lineTotal: 427.50, order: 3, parentId: parent.id)
        return inv
    }

    private func seedEmptyInvoice(_ ctx: ModelContext) -> Invoice {
        let inv = Invoice(companyId: "co", invoiceNumber: "INV-0089", status: .draft)
        ctx.insert(inv)
        return inv
    }

    // MARK: - View mounting

    private func estimateDetail(
        _ estimate: Estimate,
        container: ModelContainer,
        breakdown: Bool = false
    ) -> some View {
        let vm = EstimateViewModel()
        vm.setup(companyId: "co", modelContext: container.mainContext)
        return NavigationStack {
            EstimateDetailView(estimate: estimate, viewModel: vm, initialShowBreakdown: breakdown)
        }
        .environmentObject(DataController())
        .environmentObject(PermissionStore())
        .modelContainer(container)
    }

    private func invoiceDetail(
        _ invoice: Invoice,
        container: ModelContainer,
        breakdown: Bool = false
    ) -> some View {
        let vm = InvoiceViewModel()
        vm.setup(companyId: "co", modelContext: container.mainContext)
        return NavigationStack {
            InvoiceDetailView(invoice: invoice, viewModel: vm, initialShowBreakdown: breakdown)
        }
        .environmentObject(DataController())
        .environmentObject(PermissionStore())
        .modelContainer(container)
    }

    // MARK: - Bug a8e156a2 — line-item rendering snapshots

    func testRenderEstimateSheets() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let qb220 = seedQB220(ctx)
        let cents = seedCentsEstimate(ctx)
        let bundle = seedBundleEstimate(ctx)
        let empty = seedEmptyEstimate(ctx)
        try ctx.save()

        snapshot("financial_est_qb220") {
            self.estimateDetail(qb220, container: container)
        }
        snapshot("financial_est_cents_discount_tax") {
            self.estimateDetail(cents, container: container)
        }
        snapshot("financial_est_bundle_bundled") {
            self.estimateDetail(bundle, container: container)
        }
        snapshot("financial_est_bundle_breakdown", height: 900) {
            self.estimateDetail(bundle, container: container, breakdown: true)
        }
        snapshot("financial_est_empty", height: 700) {
            self.estimateDetail(empty, container: container)
        }
    }

    func testRenderInvoiceSheets() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let payments = seedPaymentsInvoice(ctx)
        let bundle = seedBundleInvoice(ctx)
        let empty = seedEmptyInvoice(ctx)
        try ctx.save()

        snapshot("financial_inv_payments_cents") {
            self.invoiceDetail(payments, container: container)
        }
        snapshot("financial_inv_bundle_bundled") {
            self.invoiceDetail(bundle, container: container)
        }
        snapshot("financial_inv_bundle_breakdown", height: 900) {
            self.invoiceDetail(bundle, container: container, breakdown: true)
        }
        snapshot("financial_inv_empty", height: 700) {
            self.invoiceDetail(empty, container: container)
        }
    }

    // MARK: - Bug a8e156a2 — formatting rules pinned

    func testLineItemDisplayFormatting() {
        // Quantity trims trailing zeros, up to the column's 3-decimal scale.
        XCTAssertEqual(LineItemDisplay.quantityString(2), "2")
        XCTAssertEqual(LineItemDisplay.quantityString(2.5), "2.5")
        XCTAssertEqual(LineItemDisplay.quantityString(2.25), "2.25")
        XCTAssertEqual(LineItemDisplay.quantityString(0.125), "0.125")

        // Tax rates keep their real precision — 7.5% must never read as 8%.
        XCTAssertEqual(LineItemDisplay.taxRateString(13.0), "13")
        XCTAssertEqual(LineItemDisplay.taxRateString(7.5), "7.5")
        XCTAssertEqual(LineItemDisplay.taxRateString(8.25), "8.25")

        // The row math meta — unit, no-unit, and resolved-price forms.
        XCTAssertEqual(
            LineItemDisplay.quantityPriceMeta(quantity: 2, unit: "each", unitPrice: 250),
            "2 each × $250.00"
        )
        XCTAssertEqual(
            LineItemDisplay.quantityPriceMeta(quantity: 1.5, unit: nil, unitPrice: 99.5),
            "1.5 × $99.50"
        )
        XCTAssertEqual(
            LineItemDisplay.quantityPriceMeta(quantity: 12, unit: "each", unitPrice: 7.5, resolvedUnitPrice: 8.25),
            "12 each × $8.25"
        )

        // Discount derives from the stored totals; no gap → no row.
        XCTAssertEqual(
            LineItemDisplay.discountAmount(subtotal: 1_776.08, taxAmount: 119.89, total: 1_718.36).map { ($0 * 100).rounded() / 100 },
            177.61
        )
        XCTAssertNil(LineItemDisplay.discountAmount(subtotal: 500, taxAmount: 65, total: 565))
    }

    // MARK: - Bug ce6da104 — financial sheets own the bottom edge

    /// Mounting each financial detail screen must flip the shared
    /// TabBarVisibilityController to hidden — that is the contract MainTabView
    /// consumes to fade the tab bar AND (post-fix) the FAB.
    private func assertHidesTabBar<V: View>(_ name: String, @ViewBuilder _ content: () -> V) {
        let controller = TabBarVisibilityController()
        XCTAssertFalse(controller.isHidden, "\(name): controller must start visible")

        let size = CGSize(width: deviceWidth, height: 852)
        let host = UIHostingController(
            rootView: content()
                .environment(\.tabBarVisibility, controller)
                .frame(width: size.width, height: size.height)
        )
        let window = makeWindow(size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertTrue(controller.isHidden, "\(name) must hide the global tab bar while on screen")
        window.isHidden = true
    }

    func testEstimateDetailHidesTabBarAndFAB() throws {
        let container = try makeContainer()
        let est = seedQB220(container.mainContext)
        try container.mainContext.save()
        assertHidesTabBar("EstimateDetailView") {
            self.estimateDetail(est, container: container)
        }
    }

    func testInvoiceDetailHidesTabBarAndFAB() throws {
        let container = try makeContainer()
        let inv = seedPaymentsInvoice(container.mainContext)
        try container.mainContext.save()
        assertHidesTabBar("InvoiceDetailView") {
            self.invoiceDetail(inv, container: container)
        }
    }

    func testExpenseBatchDetailHidesTabBarAndFAB() throws {
        let container = try makeContainer()
        let batch = ExpenseBatchDTO(
            id: "b1",
            companyId: "co",
            batchNumber: "EXP-BATCH-0001",
            periodStart: "2026-07-01",
            periodEnd: "2026-07-07",
            status: "submitted",
            submittedBy: "11111111-1111-1111-1111-111111111111",
            reviewedBy: nil,
            reviewedAt: nil,
            totalAmount: 412.35,
            approvedAmount: nil,
            parentBatchId: nil,
            amendmentNumber: 0,
            reviewNotes: nil,
            createdAt: "2026-07-08T10:00:00+00:00",
            scopeProjectId: nil,
            paidAt: nil,
            paidBy: nil
        )
        let vm = ExpenseViewModel()
        let permissions = PermissionStore()
        permissions.permissions = ["expenses.approve": "all", "expenses.view": "all"]
        assertHidesTabBar("ExpenseBatchDetailView") {
            NavigationStack {
                ExpenseBatchDetailView(batch: batch, viewModel: vm)
            }
            .environmentObject(DataController())
            .environmentObject(permissions)
            .modelContainer(container)
        }
    }

    /// MainTabView's FAB rule: any hider of the tab bar hides the FAB with it.
    func testFABVisibilityRule() {
        // Baseline — nothing suppresses the FAB.
        XCTAssertTrue(MainTabView.fabVisible(
            isSettingsTab: false, isPerformingInitialSync: false, isLoadingProjects: false,
            isScheduleSelectionMode: false, isShowingMapOverlay: false, isInProjectMode: false,
            tabBarHidden: false
        ))

        // The fix: a financial detail screen hiding the tab bar hides the FAB.
        XCTAssertFalse(MainTabView.fabVisible(
            isSettingsTab: false, isPerformingInitialSync: false, isLoadingProjects: false,
            isScheduleSelectionMode: false, isShowingMapOverlay: false, isInProjectMode: false,
            tabBarHidden: true
        ))

        // Every pre-existing suppressor still holds.
        XCTAssertFalse(MainTabView.fabVisible(
            isSettingsTab: true, isPerformingInitialSync: false, isLoadingProjects: false,
            isScheduleSelectionMode: false, isShowingMapOverlay: false, isInProjectMode: false,
            tabBarHidden: false
        ))
        XCTAssertFalse(MainTabView.fabVisible(
            isSettingsTab: false, isPerformingInitialSync: true, isLoadingProjects: false,
            isScheduleSelectionMode: false, isShowingMapOverlay: false, isInProjectMode: false,
            tabBarHidden: false
        ))
        XCTAssertFalse(MainTabView.fabVisible(
            isSettingsTab: false, isPerformingInitialSync: false, isLoadingProjects: true,
            isScheduleSelectionMode: false, isShowingMapOverlay: false, isInProjectMode: false,
            tabBarHidden: false
        ))
        XCTAssertFalse(MainTabView.fabVisible(
            isSettingsTab: false, isPerformingInitialSync: false, isLoadingProjects: false,
            isScheduleSelectionMode: true, isShowingMapOverlay: false, isInProjectMode: false,
            tabBarHidden: false
        ))
        XCTAssertFalse(MainTabView.fabVisible(
            isSettingsTab: false, isPerformingInitialSync: false, isLoadingProjects: false,
            isScheduleSelectionMode: false, isShowingMapOverlay: true, isInProjectMode: false,
            tabBarHidden: false
        ))
        XCTAssertFalse(MainTabView.fabVisible(
            isSettingsTab: false, isPerformingInitialSync: false, isLoadingProjects: false,
            isScheduleSelectionMode: false, isShowingMapOverlay: false, isInProjectMode: true,
            tabBarHidden: false
        ))
    }

    /// The controller's token set is idempotent against SwiftUI's
    /// double-onAppear and balanced by onDisappear.
    func testTabBarVisibilityControllerBalance() {
        let controller = TabBarVisibilityController()
        controller.hide("a")
        controller.hide("a") // double-onAppear
        controller.hide("b")
        XCTAssertTrue(controller.isHidden)
        controller.reveal("a")
        XCTAssertTrue(controller.isHidden, "second hider still active")
        controller.reveal("b")
        XCTAssertFalse(controller.isHidden, "all hiders released → bar returns")
    }
}
#endif
