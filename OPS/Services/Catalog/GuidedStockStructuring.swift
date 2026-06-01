import Foundation

// MARK: - Guided stock structuring engine
//
// Deterministic, UI-free. Proposes merges from a raw GuidedCapturedItem list.
// It NEVER auto-commits — the operator always confirms before anything is persisted.

enum GuidedStockStructuring {

    // MARK: - Types

    /// A proposed merge: 2+ captured items that look like the same product family.
    struct Cluster: Equatable {
        /// Shared family-name candidate derived from the leading token run, e.g. "vinyl".
        let stem: String
        /// The GuidedCapturedItem ids in this cluster (>= 2), in input order.
        let memberItemIds: [String]
        /// One entry per token position where members differ.
        /// Each entry is the distinct differing tokens at that position, in first-seen order.
        /// e.g. for ["Vinyl black 6ft","Vinyl white 8ft"] → [["black","white"],["6ft","8ft"]]
        let differingTokenSets: [[String]]
    }

    // MARK: - Normalize

    /// Lowercases, trims, and splits on whitespace. Returns all tokens, including
    /// dimension tokens like "6ft"/"2in". Singular/plural forms are kept distinct.
    static func normalize(_ name: String) -> [String] {
        name.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }

    // MARK: - Cluster

    /// Groups captured items into proposed merges.
    ///
    /// Only multi-member clusters (>= 2) are returned; singletons are intentionally
    /// omitted — they fall through to the per-item "one thing / versions" path.
    ///
    /// Similarity metric: `sharedLeadingTokenCount / minMemberTokenCount`
    /// where `sharedLeadingTokenCount` is the length of the longest common token
    /// prefix across all members in the group, and `minMemberTokenCount` is the
    /// smallest token count among those members.
    /// A cluster is proposed when this ratio >= `threshold`.
    ///
    /// - Parameters:
    ///   - items: Raw captured items from the CAPTURE stage.
    ///   - threshold: Minimum similarity score [0, 1] required to propose a merge.
    static func cluster(_ items: [GuidedCapturedItem], threshold: Double) -> [Cluster] {
        // 1. Tokenize every item once.
        let tokenized: [(item: GuidedCapturedItem, tokens: [String])] = items.map { item in
            (item, normalize(item.name))
        }

        // 2. Group by first token. Items with an empty name (no tokens) are dropped.
        var buckets: [String: [(item: GuidedCapturedItem, tokens: [String])]] = [:]
        for entry in tokenized {
            guard let first = entry.tokens.first else { continue }
            buckets[first, default: []].append(entry)
        }

        // 3. For each bucket with >= 2 members, compute similarity and decide.
        var clusters: [Cluster] = []

        for (_, members) in buckets {
            guard members.count >= 2 else { continue }

            // Shared leading token run length.
            let sharedLen = sharedLeadingTokenCount(members.map(\.tokens))
            let minLen = members.map(\.tokens.count).min() ?? 1
            let similarity = Double(sharedLen) / Double(max(minLen, 1))

            guard similarity >= threshold else { continue }

            // Build stem from the shared prefix.
            let stemTokens = Array(members[0].tokens.prefix(sharedLen))
            let stem = stemTokens.joined(separator: " ")

            // Build differingTokenSets: positions after the shared prefix where members differ.
            let memberIds = members.map(\.item.id)
            let remainders = members.map { Array($0.tokens.dropFirst(sharedLen)) }
            let diffSets = differingTokenSets(from: remainders)

            clusters.append(Cluster(stem: stem, memberItemIds: memberIds, differingTokenSets: diffSets))
        }

        return clusters
    }

    // MARK: - Propose values

    /// The candidate attribute values for a cluster's PRIMARY differing dimension
    /// (the first differing token position) — e.g. ["black","white","grey"].
    static func proposeValues(for cluster: Cluster) -> [String] {
        cluster.differingTokenSets.first ?? []
    }

    // MARK: - Private helpers

    /// Length of the longest common leading token run across all token arrays.
    private static func sharedLeadingTokenCount(_ tokenArrays: [[String]]) -> Int {
        guard let first = tokenArrays.first, !first.isEmpty else { return 0 }
        var count = 0
        for position in 0 ..< first.count {
            let token = first[position]
            let allMatch = tokenArrays.dropFirst().allSatisfy { arr in
                arr.indices.contains(position) && arr[position] == token
            }
            if allMatch {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Computes per-position differing token sets from the remainder arrays (post-stem).
    ///
    /// For each position, collect the distinct tokens across all members at that index.
    /// Only positions where members actually differ are included.
    /// Members that are shorter than the current position contribute no token.
    private static func differingTokenSets(from remainders: [[String]]) -> [[String]] {
        guard !remainders.isEmpty else { return [] }

        // Maximum depth to scan is the length of the longest remainder.
        let maxLen = remainders.map(\.count).max() ?? 0
        var result: [[String]] = []

        for position in 0 ..< maxLen {
            var seenOrder: [String] = []
            var seenSet: Set<String> = []

            for remainder in remainders {
                guard remainder.indices.contains(position) else { continue }
                let token = remainder[position]
                if seenSet.insert(token).inserted {
                    seenOrder.append(token)
                }
            }

            // Only include positions where values actually differ.
            if seenOrder.count > 1 {
                result.append(seenOrder)
            }
        }

        return result
    }
}
