import CoreGraphics
import Foundation

enum PermitBOMEmitter {
    private static let concreteBagSizeLb = 80
    private static let cubicFeetPerConcreteBag = 0.6

    static func emit(_ data: DeckDrawingData) -> [DesignComponentRow] {
        var rows: [DesignComponentRow] = []

        if let framing = data.framing {
            rows.append(contentsOf: emitFramingComponents(
                framing,
                scaleFactor: data.effectiveScaleFactor
            ))
            rows.append(contentsOf: emitFramingFasteners(framing))
        }

        if let footings = data.footings {
            rows.append(contentsOf: emitFootingComponents(footings))
            rows.append(contentsOf: emitFootingFasteners(footings))
            rows.append(contentsOf: emitConcreteComponents(footings))
        }

        return rows
    }

    private static func emitFramingComponents(
        _ framing: FramingPlan,
        scaleFactor: Double
    ) -> [DesignComponentRow] {
        var rows: [DesignComponentRow] = []
        let safeScaleFactor = scaleFactor > 0 ? scaleFactor : 1

        for set in framing.members {
            for member in set.members {
                guard let componentType = framingComponentType(for: member.role) else { continue }

                let linearFeet = roundToTwo(memberLinearFeet(member, scaleFactor: safeScaleFactor))
                let meta: [String: AnyCodable] = [
                    "linear_feet": AnyCodable(linearFeet),
                    "nominal_size": nullableString(member.nominalSize?.rawValue),
                    "ply_count": AnyCodable(max(1, member.plyCount)),
                    "count": AnyCodable(1),
                    "species": nullableString(member.species?.rawValue ?? framing.loadPreset?.species.rawValue),
                    "grade": nullableString(member.grade?.rawValue ?? framing.loadPreset?.grade.rawValue),
                    "level_id": AnyCodable(set.levelId),
                    "member_id": AnyCodable(member.id),
                ]
                rows.append(DesignComponentRow(componentType: componentType, metadata: meta))
            }
        }

        return rows
    }

    private static func emitFramingFasteners(_ framing: FramingPlan) -> [DesignComponentRow] {
        let joistCount = framing.members
            .flatMap(\.members)
            .filter { $0.role == .joist }
            .count
        guard joistCount > 0 else { return [] }

        return [
            DesignComponentRow(
                componentType: "fastener",
                metadata: [
                    "kind": AnyCodable("joist_hanger"),
                    "count": AnyCodable(joistCount * 2),
                    "basis": AnyCodable("framing_members"),
                    "schedule": AnyCodable("structural_framing"),
                    "member_role": AnyCodable(FramingRole.joist.rawValue),
                ]
            )
        ]
    }

    private static func emitFootingComponents(_ plan: FootingPlan) -> [DesignComponentRow] {
        plan.footings.map { footing in
            var meta: [String: AnyCodable] = [
                "footing_id": AnyCodable(footing.id),
                "type": AnyCodable(footing.type.rawValue),
                "count": AnyCodable(1),
                "position_x": AnyCodable(roundToTwo(Double(footing.position.x))),
                "position_y": AnyCodable(roundToTwo(Double(footing.position.y))),
            ]
            if let vertexId = footing.vertexId {
                meta["vertex_id"] = AnyCodable(vertexId)
            }
            if let diameter = effectiveDiameterInches(footing) {
                meta["diameter_inches"] = AnyCodable(roundToTwo(diameter))
            }
            if let depth = effectiveDepthInches(footing) {
                meta["depth_inches"] = AnyCodable(roundToTwo(depth))
            }
            if let torque = footing.helicalTorqueFtLb {
                meta["helical_torque_ft_lb"] = AnyCodable(roundToTwo(torque))
            }
            if let soil = plan.soil {
                meta["soil_bearing_psf"] = AnyCodable(roundToTwo(soil.bearingCapacityPSF))
                meta["soil_source"] = AnyCodable(soil.source.rawValue)
            }
            if let frost = plan.frost {
                if let depth = frost.depthInches {
                    meta["frost_depth_inches"] = AnyCodable(roundToTwo(depth))
                }
                meta["frost_source"] = AnyCodable(frost.source.rawValue)
            }
            if let sizing = footing.sizing {
                meta["bearing_area_sq_in"] = AnyCodable(roundToTwo(sizing.bearingAreaSqIn))
                meta["required_frost_depth_inches"] = AnyCodable(roundToTwo(sizing.requiredFrostDepthInches))
                meta["code_section"] = AnyCodable(sizing.citation.codeSection)
            }
            if let connection = footing.connection {
                if let hardwareModel = connection.hardwareModel, !hardwareModel.isEmpty {
                    meta["hardware_model"] = AnyCodable(hardwareModel)
                }
                meta["uplift_rated"] = AnyCodable(connection.upliftRated)
            }
            return DesignComponentRow(componentType: "footing", metadata: meta)
        }
    }

    private static func emitFootingFasteners(_ plan: FootingPlan) -> [DesignComponentRow] {
        struct HardwareKey: Hashable {
            let model: String
            let upliftRated: Bool
        }

        let grouped = Dictionary(grouping: plan.footings.compactMap { footing -> HardwareKey? in
            guard let connection = footing.connection,
                  let model = connection.hardwareModel,
                  !model.isEmpty else {
                return nil
            }
            return HardwareKey(model: model, upliftRated: connection.upliftRated)
        }) { $0 }

        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs.model != rhs.model { return lhs.model < rhs.model }
            return !lhs.upliftRated && rhs.upliftRated
        }

        return sortedKeys.compactMap { key in
            guard let values = grouped[key] else { return nil }
            return DesignComponentRow(
                componentType: "fastener",
                metadata: [
                    "kind": AnyCodable("post_base"),
                    "hardware_model": AnyCodable(key.model),
                    "count": AnyCodable(values.count),
                    "basis": AnyCodable("footing_connections"),
                    "schedule": AnyCodable("structural_framing"),
                    "uplift_rated": AnyCodable(key.upliftRated),
                ]
            )
        }
    }

    private static func emitConcreteComponents(_ plan: FootingPlan) -> [DesignComponentRow] {
        let concreteFootingVolumes = plan.footings.compactMap(concreteVolumeCubicFeet)
        let cubicFeet = concreteFootingVolumes.reduce(0, +)
        guard cubicFeet > 0 else { return [] }

        let roundedCubicFeet = roundToTwo(cubicFeet)
        let bagCount = Int(ceil(cubicFeet / cubicFeetPerConcreteBag))
        return [
            DesignComponentRow(
                componentType: "concrete",
                metadata: [
                    "cubic_feet": AnyCodable(roundedCubicFeet),
                    "bag_count": AnyCodable(bagCount),
                    "bag_size_lb": AnyCodable(concreteBagSizeLb),
                    "footing_count": AnyCodable(concreteFootingVolumes.count),
                    "basis": AnyCodable("footing_dimensions"),
                ]
            )
        ]
    }

    private static func concreteVolumeCubicFeet(_ footing: Footing) -> Double? {
        guard footing.type != .helicalPile,
              let diameter = effectiveDiameterInches(footing),
              let depth = effectiveDepthInches(footing),
              diameter > 0,
              depth > 0 else {
            return nil
        }

        let radius = diameter / 2
        let cubicInches = Double.pi * radius * radius * depth
        return cubicInches / 1_728
    }

    private static func effectiveDiameterInches(_ footing: Footing) -> Double? {
        if let diameter = footing.diameterInches, diameter > 0 { return diameter }
        if let diameter = footing.sizing?.diameterInches, diameter > 0 { return diameter }
        return nil
    }

    private static func effectiveDepthInches(_ footing: Footing) -> Double? {
        if let depth = footing.depthInches, depth > 0 { return depth }
        if let depth = footing.sizing?.depthInches, depth > 0 { return depth }
        return nil
    }

    private static func framingComponentType(for role: FramingRole) -> String? {
        switch role {
        case .joist:
            return "joist"
        case .beam:
            return "beam"
        case .post:
            return "post"
        case .rimBand:
            return "rim_joist"
        case .blocking:
            return "blocking"
        case .ledger, .bridging, .cantilever:
            return nil
        }
    }

    private static func memberLinearFeet(_ member: FramingMember, scaleFactor: Double) -> Double {
        let dx = member.end.x - member.start.x
        let dy = member.end.y - member.start.y
        return Double(hypot(dx, dy)) / scaleFactor / 12
    }

    private static func roundToTwo(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func nullableString(_ value: String?) -> AnyCodable {
        if let value { return AnyCodable(value) }
        return AnyCodable(NSNull())
    }
}
