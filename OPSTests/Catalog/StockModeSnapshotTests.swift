//
//  StockModeSnapshotTests.swift
//  OPSTests
//
//  Visual verification harness for the three purpose-specific Catalog Stock
//  modes at phone width. Attachments are retained for manual design review.
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class StockModeSnapshotTests: XCTestCase {
    private let frameSize = CGSize(width: 393, height: 700)

    private var outDir: URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-catalog-stock-mode-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testRenderListMode() {
        let fixture = makeFixture()
        snapshot("catalog_stock_list") {
            StockListView(
                rows: fixture.rows,
                categories: fixture.categories,
                groupByCategory: false
            )
        }
    }

    func testRenderGridMode() {
        let fixture = makeFixture()
        snapshot("catalog_stock_grid") {
            StockGridView(rows: fixture.rows)
        }
    }

    func testRenderCompactGridMode() {
        withPersistedCompactGridScale {
            let fixture = makeFixture()
            snapshot("catalog_stock_grid_compact") {
                StockGridView(rows: fixture.rows)
            }
        }
    }

    func testRenderListAndPersistedCompactGridAtAccessibilitySizes() {
        withPersistedCompactGridScale {
            let fixture = makeFixture()

            snapshot(
                "catalog_stock_grid_compact_accessibility3",
                size: CGSize(width: frameSize.width, height: 1_000)
            ) {
                StockGridView(rows: fixture.rows)
                    .environment(\.dynamicTypeSize, .accessibility3)
            }

            snapshot(
                "catalog_stock_list_accessibility3",
                size: CGSize(width: frameSize.width, height: 1_000)
            ) {
                StockListView(
                    rows: fixture.rows,
                    categories: fixture.categories,
                    groupByCategory: false
                )
                .environment(\.dynamicTypeSize, .accessibility3)
            }

            snapshot(
                "catalog_stock_grid_compact_accessibility5",
                size: CGSize(width: frameSize.width, height: 1_200)
            ) {
                StockGridView(rows: fixture.rows)
                    .environment(\.dynamicTypeSize, .accessibility5)
            }

            snapshot(
                "catalog_stock_list_accessibility5",
                size: CGSize(width: frameSize.width, height: 1_200)
            ) {
                StockListView(
                    rows: fixture.rows,
                    categories: fixture.categories,
                    groupByCategory: false
                )
                .environment(\.dynamicTypeSize, .accessibility5)
            }
        }
    }

    func testRenderTableMode() {
        let fixture = makeFixture()
        snapshot("catalog_stock_table") {
            StockTableView(rows: fixture.rows, allOptions: fixture.options)
        }
    }

    func testRenderScrollableTableMode() {
        let fixture = makeFixture(includesThirdOption: true)
        snapshot("catalog_stock_table_scrollable") {
            StockTableView(rows: fixture.rows, allOptions: fixture.options)
        }
    }

    func testRenderStockShellAndAccessibilityTable() {
        let fixture = makeFixture()
        snapshot("catalog_stock_shell_list") {
            VStack(spacing: 0) {
                StockModeWorkbar(
                    selectedMode: .list,
                    filteredCount: fixture.rows.count,
                    totalCount: fixture.rows.count,
                    isSearchActive: false,
                    onSelectMode: { _ in },
                    onToggleSearch: {}
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ChipLabel(text: "CATEGORY", isActive: false)
                        ChipLabel(text: "THRESHOLD", isActive: false)
                        ChipLabel(text: "SORT: FAMILY", isActive: false)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2)

                ThresholdBanner(rows: fixture.rows, opensSuggestedOrders: true, onTap: {})
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                StockListView(
                    rows: fixture.rows,
                    categories: fixture.categories,
                    groupByCategory: false
                )
            }
        }

        snapshot(
            "catalog_stock_table_accessibility3",
            size: CGSize(width: frameSize.width, height: 900)
        ) {
            VStack(spacing: 0) {
                StockModeWorkbar(
                    selectedMode: .table,
                    filteredCount: fixture.rows.count,
                    totalCount: fixture.rows.count,
                    isSearchActive: false,
                    onSelectMode: { _ in },
                    onToggleSearch: {}
                )
                .padding(OPSStyle.Layout.spacing3)

                StockTableView(rows: fixture.rows, allOptions: fixture.options)
            }
            .environment(\.dynamicTypeSize, .accessibility3)
        }
    }

    private func snapshot<V: View>(
        _ name: String,
        size: CGSize? = nil,
        @ViewBuilder content: () -> V
    ) {
        let renderSize = size ?? frameSize
        let root = content()
            .frame(width: renderSize.width, height: renderSize.height)
            .background(OPSStyle.Colors.background)
            .environment(\.colorScheme, .dark)

        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: renderSize)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: host.view.frame)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }

        XCTAssertGreaterThan(data.count, 10_000, "Snapshot must contain rendered UI, not a blank PNG")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
    }

    private func withPersistedCompactGridScale(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let key = "catalog.stock.cardScale"
        let previous = defaults.object(forKey: key)
        defaults.set(Double(OPSStyle.Inventory.CardScale.minScale), forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        body()
    }

    private struct Fixture {
        let rows: [EnrichedVariantRow]
        let categories: [CatalogCategory]
        let options: [CatalogOption]
    }

    private func makeFixture(includesThirdOption: Bool = false) -> Fixture {
        let companyId = "catalog-snapshot-company"
        let hardware = CatalogCategory(
            id: "category-hardware",
            companyId: companyId,
            name: "Hardware",
            sortOrder: 0
        )
        let fasteners = CatalogCategory(
            id: "category-fasteners",
            companyId: companyId,
            name: "Fasteners",
            sortOrder: 1
        )
        let each = CatalogUnit(
            id: "unit-each",
            companyId: companyId,
            display: "ea",
            abbreviation: "EA"
        )

        let bracket = CatalogItem(
            id: "family-bracket",
            companyId: companyId,
            name: "Surface Bracket",
            categoryId: hardware.id,
            defaultWarningThreshold: 20,
            defaultCriticalThreshold: 5,
            defaultUnitId: each.id
        )
        let screws = CatalogItem(
            id: "family-screws",
            companyId: companyId,
            name: "Tech Screws",
            categoryId: fasteners.id,
            defaultWarningThreshold: 500,
            defaultCriticalThreshold: 100,
            defaultUnitId: each.id
        )

        let color = CatalogOption(id: "option-color", catalogItemId: bracket.id, name: "Color", sortOrder: 0)
        let mount = CatalogOption(id: "option-mount", catalogItemId: bracket.id, name: "Mount", sortOrder: 1)
        let finish = CatalogOption(id: "option-finish", catalogItemId: bracket.id, name: "Finish", sortOrder: 2)
        let black = CatalogOptionValue(id: "value-black", optionId: color.id, value: "Black", sortOrder: 0)
        let white = CatalogOptionValue(id: "value-white", optionId: color.id, value: "White", sortOrder: 1)
        let top = CatalogOptionValue(id: "value-top", optionId: mount.id, value: "Topmount", sortOrder: 0)
        let fascia = CatalogOptionValue(id: "value-fascia", optionId: mount.id, value: "Fascia", sortOrder: 1)
        let satin = CatalogOptionValue(id: "value-satin", optionId: finish.id, value: "Satin", sortOrder: 0)

        func bracketPairs(
            _ pairs: [(CatalogOption, CatalogOptionValue)]
        ) -> [(CatalogOption, CatalogOptionValue)] {
            includesThirdOption ? pairs + [(finish, satin)] : pairs
        }

        func row(
            id: String,
            family: CatalogItem,
            category: CatalogCategory,
            sku: String,
            quantity: Double,
            pairs: [(CatalogOption, CatalogOptionValue)]
        ) -> EnrichedVariantRow {
            let variant = CatalogVariant(
                id: id,
                companyId: companyId,
                catalogItemId: family.id,
                sku: sku,
                quantity: quantity,
                unitId: each.id
            )
            return EnrichedVariantRow(
                variant: variant,
                family: family,
                category: category,
                unit: each,
                tagIds: [],
                optionPairs: pairs.map { (option: $0.0, value: $0.1) }
            )
        }

        return Fixture(
            rows: [
                row(id: "bracket-black-top", family: bracket, category: hardware, sku: "BR-BLK-T", quantity: 28, pairs: bracketPairs([(color, black), (mount, top)])),
                row(id: "bracket-white-top", family: bracket, category: hardware, sku: "BR-WHT-T", quantity: 11, pairs: bracketPairs([(color, white), (mount, top)])),
                row(id: "bracket-black-fascia", family: bracket, category: hardware, sku: "BR-BLK-F", quantity: 3, pairs: bracketPairs([(color, black), (mount, fascia)])),
                row(id: "screws-black", family: screws, category: fasteners, sku: "SCR-BLK", quantity: 5_000, pairs: []),
                row(id: "screws-white", family: screws, category: fasteners, sku: "SCR-WHT", quantity: 100, pairs: []),
                row(id: "screws-zinc", family: screws, category: fasteners, sku: "SCR-ZNC", quantity: 1_000, pairs: [])
            ],
            categories: [hardware, fasteners],
            options: includesThirdOption ? [color, mount, finish] : [color, mount]
        )
    }
}
#endif
