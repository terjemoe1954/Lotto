import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor struct LotteryHomeSnapshotTests {
    @Test func internationalLargeArchiveAndOwnRowsUseOnlySelectedDrawAndGame() throws {
        let date = LotteryCalendar.date("2026-11-04")!
        var entries: [InternationalLotteryEntry] = []
        for week in 0..<200 {
            let day = LotteryCalendar.calendar.date(byAdding: .day, value: -7 * week, to: date)!
            entries.append(InternationalLotteryEntry(game: .vikinglotto, isDraw: true, date: day, main: [1,2,3,4,5,6], extra: [1]))
        }
        for i in 0..<2000 {
            entries.append(InternationalLotteryEntry(game: .vikinglotto, isDraw: false, date: i % 2 == 0 ? date : date.addingTimeInterval(-604800), main: [1,2,3,4,5,7], extra: [2]))
        }
        entries.append(InternationalLotteryEntry(game: .vikinglotto, isDraw: false, date: date, main: [1,2,3,4,5,6], extra: [1]))
        entries.append(InternationalLotteryEntry(game: .eurojackpot, isDraw: true, date: date, main: [1,2,3,4,5], extra: [1,2]))
        let started = ContinuousClock.now
        let state = InternationalHomeSnapshot(entries: entries, game: .vikinglotto, selectedDate: nil)
        print("International home: 200 draws / 2001 own rows: \(started.duration(to: .now))")
        #expect(state.draws.count == 200)
        #expect(state.rows.count == 2001)
        #expect(state.selectedRows.count == 1001)
        #expect(state.matches.count == 1001)
        #expect(state.activeDate == date)
        #expect(state.matches[state.selectedRows[0].persistentModelID]?.main == 6)
        #expect(state.matches[state.selectedRows[0].persistentModelID]?.extra == 1)
        let prior = InternationalHomeSnapshot(entries: entries, game: .vikinglotto, selectedDate: date.addingTimeInterval(-604800))
        #expect(prior.selectedRows.count == 1000)
    }
    @Test func lottoSnapshotPreservesDateFilteringMatchingAndMissingDraws() {
        let date = LotteryCalendar.date("2026-11-07")!
        let draw = JackPot(dato: date, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7,nr8: 8)
        var rows: [Result] = []
        for i in 0..<2000 {
            rows.append(Result(dato: i % 2 == 0 ? date : date.addingTimeInterval(604800), nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 8))
        }
        rows.append(Result(dato: date, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7))
        let start = ContinuousClock.now
        let state = LottoHomeSnapshot(draws: [draw, draw], rows: rows, selectedDate: nil)
        print("Lotto home: 2001 own rows: \(start.duration(to: .now))")
        #expect(state.draws.count == 1)
        #expect(state.selectedRows.count == 1001)
        #expect(state.comparisons.count == 1001)
        #expect(state.comparisons[state.selectedRows[0].persistentModelID]?.matchCount == 7)
        let future = LottoHomeSnapshot(draws: [draw], rows: rows, selectedDate: date.addingTimeInterval(604800))
        #expect(future.selectedRows.count == 1000)
        #expect(future.comparisons.isEmpty)
        #expect(future.dates.count == 2)
    }
    @Test func emptyArchiveAndDifferentYearCannotMatchByWeekNumber() {
        let date = LotteryCalendar.date("2026-11-07")!
        let row = Result(dato: date, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7)
        let empty = LottoHomeSnapshot(draws: [], rows: [row], selectedDate: nil)
        #expect(empty.activeDate == date)
        #expect(empty.selectedRows.count == 1)
        #expect(empty.comparisons.isEmpty)
        let old = JackPot(dato: LotteryCalendar.date("2025-11-08")!, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7,nr8: 8)
        let state = LottoHomeSnapshot(draws: [old], rows: [row], selectedDate: date)
        #expect(state.selectedRows.count == 1)
        #expect(state.comparisons.isEmpty)
    }
    @Test func cancelledUpdatesDoNotFetchOrMutateData() async throws {
        let container = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self,
            LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let lotto = Task { @MainActor in try await LottoDrawUpdater.update(modelContext: context) }
        lotto.cancel()
        do { _ = try await lotto.value; Issue.record("Cancelled Lotto update should stop before networking") }
        catch is CancellationError { }
        let international = Task { @MainActor in
            try await InternationalLotteryUpdater.update(game: .vikinglotto, context: context) { _ in
                Issue.record("Cancelled international update should not start a request")
            }
        }
        international.cancel()
        do { _ = try await international.value; Issue.record("Cancelled international update should stop") }
        catch is CancellationError { }
        #expect(try context.fetchCount(FetchDescriptor<JackPot>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 0)
        #expect(!context.hasChanges)
    }

}
