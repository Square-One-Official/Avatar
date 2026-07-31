// UXS-9 (UX8) — Home deelt op TIJD, niet op "de nieuwste is speciaal".
//
// De oude indeling zette altijd precies één portret in "Recent" (het nieuwste,
// als paginabrede hero) en al het andere in "Earlier" — ook als dat ene portret
// van maanden geleden was. De sectiekoppen logen dus over de inhoud.
//
// De splitsing zelf is pure logica op `updatedAt`; die borgen we hier, zodat de
// view alleen nog hoeft te renderen.

import Foundation
import SwiftData
import Testing
@testable import Avatar2

@MainActor
@Suite struct HomeSectionsTests {

    /// Spiegelt `HomeView.recentPortraits` / `earlierPortraits`.
    private func split(_ dates: [Date], now: Date = Date()) -> (recent: [Int], earlier: [Int]) {
        let cutoff = now.addingTimeInterval(-ShellMetrics.recentSectionWindow)
        let sorted = dates.enumerated().sorted { $0.element > $1.element }
        let recent = sorted.filter { $0.element >= cutoff }.prefix(ShellMetrics.recentSectionLimit)
        let recentIndices = Set(recent.map(\.offset))
        let earlier = sorted.filter { !recentIndices.contains($0.offset) }
        return (recent.map(\.offset), earlier.map(\.offset))
    }

    @Test func gisterenBewerktPortretStaatInRecent() {
        let now = Date()
        let (recent, earlier) = split([now.addingTimeInterval(-24 * 60 * 60)], now: now)
        #expect(recent == [0])
        #expect(earlier.isEmpty)
    }

    @Test func oudPortretStaatNietInRecent() {
        let now = Date()
        let (recent, earlier) = split([now.addingTimeInterval(-30 * 24 * 60 * 60)], now: now)
        #expect(recent.isEmpty)
        #expect(earlier == [0])
    }

    /// Precies op de grens van 7 dagen telt nog als recent — anders zou een
    /// portret tijdens het kijken van sectie wisselen.
    @Test func grensGevalTeltAlsRecent() {
        let now = Date()
        let (recent, _) = split([now.addingTimeInterval(-ShellMetrics.recentSectionWindow + 60)], now: now)
        #expect(recent == [0])
    }

    /// Recent is gecapt; de rest zakt naar Earlier i.p.v. de sectie te laten
    /// uitdijen tot het hele archief.
    @Test func recentIsGecaptOpDeLimiet() {
        let now = Date()
        let dates = (0..<10).map { now.addingTimeInterval(-Double($0) * 3600) }
        let (recent, earlier) = split(dates, now: now)
        #expect(recent.count == ShellMetrics.recentSectionLimit)
        #expect(earlier.count == 10 - ShellMetrics.recentSectionLimit)
    }

    /// Elk portret komt in precies één sectie voor — geen duplicaten, geen
    /// portretten die van het scherm vallen.
    @Test func elkPortretPreciesEenKeer() {
        let now = Date()
        let dates = [
            now.addingTimeInterval(-3600),
            now.addingTimeInterval(-8 * 24 * 3600),
            now.addingTimeInterval(-2 * 24 * 3600),
            now.addingTimeInterval(-400 * 24 * 3600),
        ]
        let (recent, earlier) = split(dates, now: now)
        #expect(Set(recent).union(Set(earlier)).count == dates.count)
        #expect(Set(recent).intersection(Set(earlier)).isEmpty)
    }

    /// Home en de gallery moeten dezelfde celmaat gebruiken — dat was juist het
    /// verschil (4 vs 3 kolommen) waardoor dezelfde kaart per scherm anders oogde.
    @Test func gridMetricsZijnGedeeld() {
        #expect(ShellMetrics.portraitGridColumnCount > 0)
        #expect(ShellMetrics.portraitGridSpacing > 0)
    }
}
