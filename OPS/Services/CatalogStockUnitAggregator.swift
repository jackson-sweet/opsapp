//
//  CatalogStockUnitAggregator.swift
//  OPS
//

import Foundation

struct CatalogStockUnitVariantAggregate: Equatable {
    var activeUnitCount: Int = 0
    var quantityValue: Double = 0
    var remainingLengthByUnit: [String: Double] = [:]
    var remainingAreaByUnit: [String: Double] = [:]

    var effectiveQuantity: Double {
        if remainingAreaByUnit.count == 1, let areaTotal = remainingAreaByUnit.values.first {
            return areaTotal
        }

        if remainingAreaByUnit.isEmpty,
           remainingLengthByUnit.count == 1,
           let lengthTotal = remainingLengthByUnit.values.first {
            return lengthTotal
        }

        return quantityValue
    }

    var effectiveQuantityBasis: String {
        if remainingAreaByUnit.count == 1, let unit = remainingAreaByUnit.keys.first {
            return "AREA · \(unit)"
        }

        if remainingAreaByUnit.isEmpty,
           remainingLengthByUnit.count == 1,
           let unit = remainingLengthByUnit.keys.first {
            return "LENGTH · \(unit)"
        }

        return "COUNT"
    }

    mutating func addAvailableMeasurement(
        unitKind: CatalogStockUnitKind,
        quantityValue: Double,
        remainingLengthValue: Double?,
        lengthUnit: String?,
        widthValue: Double?,
        widthUnit: String?
    ) {
        activeUnitCount += 1
        self.quantityValue += max(0, quantityValue)

        guard let remainingLengthValue, remainingLengthValue > 0 else { return }

        let lengthKey = Self.normalizedUnit(lengthUnit)
        remainingLengthByUnit[lengthKey, default: 0] += remainingLengthValue

        guard unitKind.isDimensionalAreaStock,
              let widthValue,
              widthValue > 0,
              let areaKey = Self.areaUnitKey(lengthUnit: lengthUnit, widthUnit: widthUnit)
        else { return }

        remainingAreaByUnit[areaKey, default: 0] += remainingLengthValue * widthValue
    }

    private static func normalizedUnit(_ unit: String?) -> String {
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? "unit" : trimmed
    }

    private static func areaUnitKey(lengthUnit: String?, widthUnit: String?) -> String? {
        let length = normalizedUnit(lengthUnit)
        let width = normalizedUnit(widthUnit)
        guard length != "unit", length == width else { return nil }
        return "sq \(length)"
    }
}

struct CatalogStockUnitAggregation: Equatable {
    var byVariantId: [String: CatalogStockUnitVariantAggregate]
}

enum CatalogStockQuantityPolicyMode: String {
    case mirroredVariantQuantity
}

enum CatalogStockQuantityPolicy {
    /// `catalog_variants.quantity` remains the operational count used by the
    /// current stock UI and order flows. Stock-unit writes must mirror their
    /// available aggregate back to the variant quantity.
    static let mode: CatalogStockQuantityPolicyMode = .mirroredVariantQuantity

    static func quantityToMirror(_ aggregate: CatalogStockUnitVariantAggregate) -> Double {
        aggregate.effectiveQuantity
    }

    static func quantityBasis(for aggregate: CatalogStockUnitVariantAggregate) -> String {
        aggregate.effectiveQuantityBasis
    }
}

enum CatalogStockUnitAggregator {
    static func aggregate(units: [CatalogStockUnit]) -> CatalogStockUnitAggregation {
        var byVariantId: [String: CatalogStockUnitVariantAggregate] = [:]

        for unit in units where unit.deletedAt == nil && unit.status.countsAsAvailable {
            var aggregate = byVariantId[unit.catalogVariantId] ?? CatalogStockUnitVariantAggregate()
            aggregate.addAvailableMeasurement(
                unitKind: unit.unitKind,
                quantityValue: unit.quantityValue,
                remainingLengthValue: unit.remainingLengthValue,
                lengthUnit: unit.lengthUnit,
                widthValue: unit.widthValue,
                widthUnit: unit.widthUnit
            )
            byVariantId[unit.catalogVariantId] = aggregate
        }

        return CatalogStockUnitAggregation(byVariantId: byVariantId)
    }
}

extension CatalogStockUnitKind {
    var isDimensionalAreaStock: Bool {
        switch self {
        case .roll, .offcut:
            return true
        case .box, .each, .lot, .pallet, .length:
            return false
        }
    }
}
