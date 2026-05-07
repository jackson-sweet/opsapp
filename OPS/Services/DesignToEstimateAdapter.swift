//
//  DesignToEstimateAdapter.swift
//  OPS
//
//  Walks a DeckDesign's drawing_data, finds the company's default Product
//  per component_type, auto-fills options from $design.<key> metadata,
//  computes resolved unit prices, and emits draft estimate line items.
//
//  Pure function: no I/O inside `generate(...)`. The caller fetches the
//  company defaults + product richness and passes them in. A `@MainActor`
//  convenience extension below wires SwiftData → pure call for callers
//  that already hold a ModelContext.
//

import Foundation
import SwiftData

struct DesignToEstimateAdapter {

    struct GeneratedLineItem: Equatable {
        let productId: String
        let quantity: Double
        let configuredOptions: [String: ProductConfigurationResolver.OptionValue]
        let resolvedUnitPrice: Double
        let resolvedOptionsLabel: String
        let lineTotal: Double

        static func == (lhs: GeneratedLineItem, rhs: GeneratedLineItem) -> Bool {
            return lhs.productId == rhs.productId
                && lhs.quantity == rhs.quantity
                && lhs.resolvedUnitPrice == rhs.resolvedUnitPrice
                && lhs.resolvedOptionsLabel == rhs.resolvedOptionsLabel
                && lhs.lineTotal == rhs.lineTotal
        }
    }

    let resolver = ProductConfigurationResolver()

    /// Walk the design's parsed components, look up the default Product per
    /// component_type, and emit one draft line item per component.
    ///
    /// Components without a configured default Product are skipped silently —
    /// missing defaults must not block estimate creation. If the drawing JSON
    /// has no `components` key (Deck Builder hasn't landed the vocabulary
    /// yet), returns `[]`.
    func generate(
        design: DeckDesign,
        defaults: [DesignComponentType: Product],
        productOptions: [String: [ProductOption]],            // productId → options
        productOptionValues: [String: [ProductOptionValue]],  // optionId → values
        productModifiers: [String: [ProductPricingModifier]]  // productId → modifiers
    ) -> [GeneratedLineItem] {
        guard let drawing = parseDrawingData(design.drawingDataJSON) else { return [] }

        var generated: [GeneratedLineItem] = []
        for component in drawing.components {
            guard let defaultProduct = defaults[component.type] else {
                // Skip components without a default — don't block estimate creation.
                continue
            }
            let options = productOptions[defaultProduct.id] ?? []
            let optionValues = options.flatMap { productOptionValues[$0.id] ?? [] }
            let modifiers = productModifiers[defaultProduct.id] ?? []

            // Build configured map from design metadata + default fallbacks.
            let configured = buildConfigured(
                options: options,
                optionValues: optionValues,
                metadata: component.metadata
            )

            // Compute quantity from geometry based on Product's pricing_unit.
            let quantity = computeQuantity(unit: defaultProduct.pricingUnit, metadata: component.metadata)

            let resolution = resolver.resolve(
                product: defaultProduct,
                options: options,
                optionValues: optionValues,
                modifiers: modifiers,
                configured: configured
            )

            generated.append(GeneratedLineItem(
                productId: defaultProduct.id,
                quantity: quantity,
                configuredOptions: configured,
                resolvedUnitPrice: resolution.unitPrice,
                resolvedOptionsLabel: resolution.label,
                lineTotal: resolution.unitPrice * quantity
            ))
        }
        return generated
    }

    // MARK: - Configured options

    private func buildConfigured(
        options: [ProductOption],
        optionValues: [ProductOptionValue],
        metadata: [String: Any]
    ) -> [String: ProductConfigurationResolver.OptionValue] {
        var result: [String: ProductConfigurationResolver.OptionValue] = [:]
        for opt in options {
            // Resolve via $design.<key> if option_default_source is set.
            var rawValue: Any? = nil
            if let source = opt.optionDefaultSource, source.hasPrefix("$design.") {
                let key = String(source.dropFirst("$design.".count))
                rawValue = metadata[key]
            }

            // Fall back to default_value
            if rawValue == nil {
                rawValue = opt.defaultValue
            }

            switch opt.kind {
            case .select:
                if let s = rawValue as? String,
                   let match = optionValues.first(where: { $0.optionId == opt.id && $0.value == s }) {
                    result[opt.id] = .selectId(match.id)
                }
                // If no match, leave option unset — resolver still computes a sensible label/price.
            case .integer:
                if let n = rawValue as? Int {
                    result[opt.id] = .integer(n)
                } else if let d = rawValue as? Double {
                    result[opt.id] = .integer(Int(d))
                } else if let s = rawValue as? String, let n = Int(s) {
                    result[opt.id] = .integer(n)
                } else {
                    result[opt.id] = .integer(0)
                }
            case .boolean:
                if let b = rawValue as? Bool {
                    result[opt.id] = .boolean(b)
                } else if let s = rawValue as? String {
                    result[opt.id] = .boolean(s.lowercased() == "true")
                } else {
                    result[opt.id] = .boolean(false)
                }
            }
        }
        return result
    }

    // MARK: - Quantity

    private func computeQuantity(unit: ProductPricingUnit, metadata: [String: Any]) -> Double {
        switch unit {
        case .flatRate:
            return 1.0
        case .each:
            if let n = metadata["count"] as? Int { return Double(n) }
            if let d = metadata["count"] as? Double { return d }
            return 1.0
        case .linearFoot:
            if let d = metadata["linear_feet"] as? Double { return d }
            if let n = metadata["linear_feet"] as? Int { return Double(n) }
            return 0
        case .sqft:
            if let d = metadata["sqft"] as? Double { return d }
            if let n = metadata["sqft"] as? Int { return Double(n) }
            return 0
        case .hour:
            if let d = metadata["hours"] as? Double { return d }
            if let n = metadata["hours"] as? Int { return Double(n) }
            return 0
        case .day:
            if let d = metadata["days"] as? Double { return d }
            if let n = metadata["days"] as? Int { return Double(n) }
            return 0
        }
    }

    // MARK: - Drawing data parsing
    //
    // The existing `DeckDrawingData` Codable struct does not yet carry a
    // `components: [{component_type, metadata}]` array — that's coming
    // from the Deck Builder agent in a separate session. For now we parse
    // the JSON manually with `JSONSerialization` looking for an optional
    // `"components"` key, and gracefully no-op if it's missing.

    private struct ParsedDrawing {
        let components: [ParsedComponent]
    }

    private struct ParsedComponent {
        let type: DesignComponentType
        let metadata: [String: Any]
    }

    private func parseDrawingData(_ json: String) -> ParsedDrawing? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // No components key, or wrong shape → empty result, no crash.
        guard let comps = dict["components"] as? [[String: Any]] else {
            return ParsedDrawing(components: [])
        }
        let parsed = comps.compactMap { c -> ParsedComponent? in
            guard let typeStr = c["component_type"] as? String,
                  let type = DesignComponentType(rawValue: typeStr) else {
                // Unknown component_type → skip silently per spec § 7.1.
                return nil
            }
            let meta = (c["metadata"] as? [String: Any]) ?? [:]
            return ParsedComponent(type: type, metadata: meta)
        }
        return ParsedDrawing(components: parsed)
    }
}

// MARK: - SwiftData convenience

@MainActor
extension DesignToEstimateAdapter {

    /// Convenience: fetch defaults + product richness from SwiftData and call
    /// the pure `generate(design:defaults:...)` overload.
    ///
    /// Returns `[]` if any required data is missing — caller should treat
    /// zero line items as "nothing to suggest yet" rather than an error.
    /// Future PR will wire a "Generate Estimate" action in DeckBuilder /
    /// EstimateFormSheet to this method.
    func generate(
        design: DeckDesign,
        companyId: String,
        modelContext: ModelContext
    ) -> [GeneratedLineItem] {
        // 1. Fetch CompanyDefaultProduct rows for this company.
        let defaultProductDescriptor = FetchDescriptor<CompanyDefaultProduct>(
            predicate: #Predicate { $0.companyId == companyId }
        )
        let defaultRows = (try? modelContext.fetch(defaultProductDescriptor)) ?? []
        guard !defaultRows.isEmpty else { return [] }

        // 2. Fetch the Products themselves (one per default).
        let productIds = Set(defaultRows.map(\.productId))
        let productDescriptor = FetchDescriptor<Product>(
            predicate: #Predicate { productIds.contains($0.id) }
        )
        let products = (try? modelContext.fetch(productDescriptor)) ?? []
        let productById = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        // 3. Build defaults map: [DesignComponentType: Product].
        var defaults: [DesignComponentType: Product] = [:]
        for row in defaultRows {
            if let product = productById[row.productId] {
                defaults[row.componentType] = product
            }
        }
        guard !defaults.isEmpty else { return [] }

        // 4. Fetch ProductOption / ProductOptionValue / ProductPricingModifier
        //    filtered to the default product ids.
        let optionDescriptor = FetchDescriptor<ProductOption>(
            predicate: #Predicate { productIds.contains($0.productId) }
        )
        let allOptions = (try? modelContext.fetch(optionDescriptor)) ?? []
        let productOptions = Dictionary(grouping: allOptions, by: \.productId)

        let optionIds = Set(allOptions.map(\.id))
        let optionValueDescriptor = FetchDescriptor<ProductOptionValue>(
            predicate: #Predicate { optionIds.contains($0.optionId) }
        )
        let allOptionValues = (try? modelContext.fetch(optionValueDescriptor)) ?? []
        let productOptionValues = Dictionary(grouping: allOptionValues, by: \.optionId)

        let modifierDescriptor = FetchDescriptor<ProductPricingModifier>(
            predicate: #Predicate { productIds.contains($0.productId) }
        )
        let allModifiers = (try? modelContext.fetch(modifierDescriptor)) ?? []
        let productModifiers = Dictionary(grouping: allModifiers, by: \.productId)

        // 5. Call the pure overload.
        return generate(
            design: design,
            defaults: defaults,
            productOptions: productOptions,
            productOptionValues: productOptionValues,
            productModifiers: productModifiers
        )
    }
}
