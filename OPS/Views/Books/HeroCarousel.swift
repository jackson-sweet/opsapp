//
//  HeroCarousel.swift
//  OPS
//
//  Books — the shared lens identifier. The swipeable hero carousel this file
//  was named for is gone (Money & Leads redesign 2026-06-30 replaced it with
//  `BooksCommandGrid`), but its `CardID` survives as the currency between the
//  command grid's tiles and the drill-down half-sheet: a tile hands a CardID
//  to `BooksTabView`, which presents `ExpandedCardSheet` for that lens.
//

/// Namespace kept under the `HeroCarousel` name so the `HeroCarousel.CardID`
/// spelling used across the Books tab (`BooksTabView` / `BooksCommandGrid` /
/// `ExpandedCardSheet`) survives the carousel's removal unchanged.
enum HeroCarousel {
    /// One case per Books lens. `cashForecast` (RUNWAY) deep-links to its own
    /// full screen instead of the shared expand sheet.
    enum CardID: String, CaseIterable, Identifiable {
        case pl, cashFlow, cashForecast, ar, forecast, jobs
        var id: String { rawValue }
    }
}
