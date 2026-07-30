//
//  ComparableJobLength.swift
//  OPS
//
//  How long a job should take, argued from the operator's own finished work.
//
//  The schedule sheet already answers WHEN to start. This answers HOW LONG,
//  and it answers it the only way that survives contact with a job site: by
//  reading what this company actually did, on decks about this size, doing
//  this exact kind of work. No industry rate, no per-square-foot table, no
//  model — the operator's own history or nothing.
//
//  Four rules keep that honest, and every one of them can veto the answer:
//
//    · SAME TASK TYPE. Framing days say nothing about railing days.
//    · SAME SIZE CLASS. A 200 sqft job is not evidence about an 800 sqft
//      deck. Out-of-band jobs are not weak evidence — they are not evidence,
//      and a type-median without size would be a different, worse feature
//      wearing this one's chip.
//    · ALREADY RUN. A job still sitting on the calendar is somebody's guess.
//      Feeding guesses back in would let one optimistic estimate quietly
//      become the company's standard.
//    · THREE OR MORE. Two jobs is an anecdote, and stating an anecdote as a
//      number is worse than saying nothing. Below the floor the chip drops
//      the length and keeps the date it can stand behind.
//
//  The core is pure arithmetic over plain numbers. The gather beneath it is
//  the single place that reads the store; it lives here, next to the rules it
//  feeds, and is called by `CalendarSchedulerSheet`. It is never called by
//  `SchedulerDayContext` — that engine stays free of SwiftData and simply
//  carries whatever number the sheet hands it.
//

import Foundation
import SwiftData

struct ComparableJobLength {

    // MARK: - Behaviour constants

    /// How far apart two decks may be in size and still say anything about
    /// each other: the larger area over the smaller, capped here. At 1.3 a
    /// 400 sqft deck learns from roughly 308–520 sqft jobs and is deaf to
    /// everything else — wide enough to find comps in a small company's
    /// history, tight enough that it is still the same kind of deck.
    static let sizeBandRatio: Double = 1.3

    /// Fewer in-band jobs than this and there is no pattern to report, only a
    /// coincidence. The chip says nothing about length rather than dress two
    /// jobs up as experience.
    static let minimumComparables = 3

    // MARK: - Pure core

    /// The number of days worth proposing, or nil when the history cannot
    /// support one. Each comparable is a finished job of the same task type:
    /// the deck area it was worked on, and the inclusive days it took.
    static func suggestedDays(
        targetAreaSqFt: Double,
        comparables: [(areaSqFt: Double, days: Int)]
    ) -> Int? {
        guard targetAreaSqFt > 0 else { return nil }

        let inBand = comparables.filter {
            $0.days > 0 && isComparable(targetAreaSqFt: targetAreaSqFt, compAreaSqFt: $0.areaSqFt)
        }
        guard inBand.count >= minimumComparables else { return nil }

        return roundedMedian(of: inBand.map { $0.days })
    }

    /// Whether two deck areas are close enough in size to inform each other.
    /// Symmetric: a comp being the larger or the smaller of the pair is the
    /// same fact about how alike the two decks are.
    static func isComparable(targetAreaSqFt: Double, compAreaSqFt: Double) -> Bool {
        guard targetAreaSqFt > 0, compAreaSqFt > 0 else { return false }
        let larger = max(targetAreaSqFt, compAreaSqFt)
        let smaller = min(targetAreaSqFt, compAreaSqFt)
        return larger / smaller <= sizeBandRatio
    }

    /// The middle job's length, rounding a split decision UP. With an even
    /// number of comps the middle falls between two jobs, and the longer of
    /// the two is the one to promise: a crew over-runs far more often than it
    /// under-runs, and a day of slack costs less than a day of apology.
    static func roundedMedian(of days: [Int]) -> Int? {
        guard !days.isEmpty else { return nil }
        let sorted = days.sorted()
        let middle = sorted.count / 2
        guard sorted.count.isMultiple(of: 2) else { return sorted[middle] }
        // Integer ceiling of the two middles' mean. Day counts are always
        // positive, so this never has to reason about negative rounding.
        return (sorted[middle - 1] + sorted[middle] + 1) / 2
    }
}

// MARK: - Store resolution

extension ComparableJobLength {

    /// Resolves one job's proposed length from the local store: the target's
    /// deck size, every finished job of the same type this company has run,
    /// and the deck size each of those ran on. Returns nil the moment any
    /// honesty gate closes — no deck on this project, a drawing with nothing
    /// measurable in it, or too few finished jobs inside the size band.
    ///
    /// This is the feature's only contact with SwiftData. The sheet calls it
    /// once per context load, exactly as it resolves prerequisites and crew
    /// names once, and hands the plain number down to the pure engine.
    static func resolveSuggestedDays(
        taskTypeId: String,
        projectId: String,
        companyId: String,
        in context: ModelContext,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int? {
        guard !taskTypeId.isEmpty, !projectId.isEmpty, !companyId.isEmpty else { return nil }

        // Drawings are read once and measured on demand. A company's finished
        // work of one type routinely piles onto a handful of projects, so
        // decoding per comp would re-parse the same JSON — and re-run the
        // same surface detection — several times inside a single load.
        guard let designs = try? context.fetch(FetchDescriptor<DeckDesign>()) else { return nil }
        var measured: [String: Double] = [:]

        func areaSqFt(ofProject id: String) -> Double {
            let key = DeckDesign.canonicalUUIDString(id)
            if let cached = measured[key] { return cached }
            // The latest drawing wins outright: a deck that was redrawn was
            // redrawn because the earlier one was wrong about the deck.
            let attached: [DeckDesign] = designs.filter {
                $0.deletedAt == nil && $0.isAttached(toProjectId: key)
            }
            let latest: DeckDesign? = attached.max { left, right in
                let leftStamp: Date = left.updatedAt ?? Date.distantPast
                let rightStamp: Date = right.updatedAt ?? Date.distantPast
                return leftStamp < rightStamp
            }
            var area = 0.0
            if let drawing = latest?.drawingData {
                area = drawing.totalRealWorldArea(scaleFactor: drawing.effectiveScaleFactor) / 144.0
            }
            measured[key] = area
            return area
        }

        // No deck on this job, or a drawing with no closed shape to measure.
        // The whole premise is "decks this size take this long"; without a
        // size there is no premise, and inventing one would be a guess with a
        // number on it.
        let targetArea = areaSqFt(ofProject: projectId)
        guard targetArea > 0 else { return nil }

        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> {
                $0.companyId == companyId && $0.taskTypeId == taskTypeId && $0.deletedAt == nil
            }
        )
        guard let candidates = try? context.fetch(descriptor) else { return nil }

        let today = calendar.startOfDay(for: now)
        var comparables: [(areaSqFt: Double, days: Int)] = []
        for task in candidates {
            // A cancelled job never happened; its dates are a plan nobody ran.
            guard task.status != .cancelled,
                  let start = task.startDate,
                  let end = task.endDate else { continue }
            let firstDay = calendar.startOfDay(for: start)
            let lastDay = calendar.startOfDay(for: end)
            // Only work that is genuinely behind us.
            guard lastDay < today else { continue }
            let area = areaSqFt(ofProject: task.projectId)
            guard area > 0 else { continue }
            let span = calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0
            // Inclusive, and never zero: a job that started and finished on
            // one day took a day.
            comparables.append((areaSqFt: area, days: max(1, span + 1)))
        }

        return suggestedDays(targetAreaSqFt: targetArea, comparables: comparables)
    }
}
