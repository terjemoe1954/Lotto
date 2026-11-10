import Foundation
import SwiftData
import Testing
@testable import Lotto

private struct SuggestionTestRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@MainActor
struct InternationalSuggestionTests {
    private let today = LotteryCalendar.date("2026-11-10")!
    private func record(_ date: String, main: [Int] = [1,2,3,4,5,6], extra: [Int] = [1],
                        game: InternationalGame = .vikinglotto, isDraw: Bool = true) -> InternationalLotteryRecord {
        InternationalLotteryRecord(gameID: game.rawValue, isDraw: isDraw, date: LotteryCalendar.date(date)!, mainNumbers: main, extraNumbers: extra)
    }
    private func archive() throws -> [InternationalLotteryRecord] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Lotto/Helpers/international-draws.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([InternationalLotteryRecord].self, from: Data(contentsOf: url))
    }

    @Test func allModesProduceTwentyUniqueValidRowsForBothGames() throws {
        let records = try archive()
        for game in InternationalGame.allCases {
            for mode in InternationalSuggestionMode.allCases {
                var random = SuggestionTestRandom(state: 42)
                let batch = InternationalSuggestionEngine.makeRows(game: game, date: today, records: records,
                    mode: mode, count: 20, asOf: today, using: &random)
                #expect(batch.rows.count == 20)
                #expect(Set(batch.rows.map(\.id)).count == 20)
                for row in batch.rows {
                    #expect(game.validation(main: row.mainNumbers, extra: row.extraNumbers, date: batch.date) == nil)
                    #expect(row.mainNumbers == row.mainNumbers.sorted())
                    #expect(row.extraNumbers == row.extraNumbers.sorted())
                }
                #expect(batch.historyDrawCount == (game == .vikinglotto ? 201 : 402))
            }
        }
    }

    @Test func sameDrawAndLaterResultsCannotInfluenceHistoricalSuggestions() {
        let target = LotteryCalendar.date("2026-10-07")!
        let before = [record("2026-09-23"), record("2026-09-30")]
        let after = before + [record("2026-10-07", main: [30,31,32,33,34,35], extra: [5]),
                              record("2026-10-14", main: [40,41,42,43,44,45], extra: [4])]
        var firstRandom = SuggestionTestRandom(state: 31)
        var secondRandom = SuggestionTestRandom(state: 31)
        let first = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: target, records: before,
            mode: .history, asOf: today, using: &firstRandom)
        let second = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: target, records: after,
            mode: .history, asOf: today, using: &secondRandom)
        #expect(first.rows == second.rows)
        #expect(second.historyDrawCount == 2)
        #expect(first.mainCandidates == second.mainCandidates)
    }

    @Test func sameWeekUsesPreviousISOWeekYearsOnly() {
        let records = [record("2025-10-08"), record("2026-09-30"), record("2026-10-07")]
        var random = SuggestionTestRandom(state: 17)
        let batch = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: LotteryCalendar.date("2026-10-07")!,
            records: records, asOf: today, using: &random)
        #expect(batch.historyDrawCount == 2)
        #expect(batch.sameWeekDrawCount == 1)
    }

    @Test func intervalCandidatesKeepPoolsSeparate() {
        let records = [record("2026-10-07", extra: [5]), record("2026-10-14", extra: [5]), record("2026-10-21", extra: [5])]
        var random = SuggestionTestRandom(state: 19)
        let batch = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: LotteryCalendar.date("2026-10-28")!,
            records: records, mode: .history, toleranceDays: 0, asOf: today, using: &random)
        #expect(batch.mainCandidates == [1,2,3,4,5,6])
        #expect(batch.extraCandidates == [5])
        let crossPool = InternationalSuggestedRow(mainNumbers: [1,2,3,4,5,6], extraNumbers: [5])
        #expect(InternationalGame.vikinglotto.validation(main: crossPool.mainNumbers, extra: crossPool.extraNumbers, date: batch.date) == nil)
    }

    @Test func randomModeIgnoresHistoryAndMissingHistoryFallsBackToEqualWeights() {
        var first = SuggestionTestRandom(state: 100)
        var second = SuggestionTestRandom(state: 100)
        var third = SuggestionTestRandom(state: 100)
        let randomWithHistory = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: today,
            records: [record("2026-10-07")], mode: .random, asOf: today, using: &first)
        let randomWithoutHistory = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: today,
            records: [], mode: .random, asOf: today, using: &second)
        let historicalWithoutHistory = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: today,
            records: [], mode: .history, asOf: today, using: &third)
        #expect(randomWithHistory.rows == randomWithoutHistory.rows)
        #expect(randomWithHistory.rows == historicalWithoutHistory.rows)
        #expect(randomWithHistory.mainCandidates.isEmpty)
        #expect(randomWithHistory.extraCandidates.isEmpty)
    }

    @Test func inputsAreBoundedAndUnplayableDatesAdvance() {
        var random = SuggestionTestRandom(state: 11)
        let empty = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: today, records: [], count: -1, using: &random)
        #expect(empty.rows.isEmpty)
        let bounded = InternationalSuggestionEngine.makeRows(game: .eurojackpot, date: LotteryCalendar.date("2026-11-07")!,
            records: [], count: 1000, toleranceDays: .nan, asOf: today, using: &random)
        #expect(bounded.rows.count == 20)
        #expect(LotteryCalendar.text(bounded.date) == "2026-11-10")
    }

    @Test func bulkSavingIsIdempotentAndDateSpecific() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: InternationalLotteryEntry.self, configurations: config)
        let context = container.mainContext
        let date = LotteryCalendar.date("2026-10-07")!
        let row = InternationalSuggestedRow(mainNumbers: [1,2,3,4,5,6], extraNumbers: [1])
        let second = InternationalSuggestedRow(mainNumbers: [7,8,9,10,11,12], extraNumbers: [2])
        #expect(try InternationalSuggestedRowSaver.save([row], game: .vikinglotto, date: date, context: context) == 1)
        #expect(try InternationalSuggestedRowSaver.save([row,second,row], game: .vikinglotto, date: date, context: context) == 1)
        #expect(try InternationalSuggestedRowSaver.save([row,second], game: .vikinglotto, date: date, context: context) == 0)
        #expect(try InternationalSuggestedRowSaver.save([row], game: .vikinglotto, date: LotteryCalendar.date("2026-10-14")!, context: context) == 1)
        let saved = try context.fetch(FetchDescriptor<InternationalLotteryEntry>())
        #expect(saved.count == 3)
        #expect(saved.allSatisfy { !$0.isDraw })
    }

    @Test func invalidBatchLeavesDatabaseUnchanged() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: InternationalLotteryEntry.self, configurations: config)
        let context = container.mainContext
        let good = InternationalSuggestedRow(mainNumbers: [1,2,3,4,5,6], extraNumbers: [1])
        let bad = InternationalSuggestedRow(mainNumbers: [1,1,3,4,5,6], extraNumbers: [1])
        #expect(throws: (any Error).self) {
            try InternationalSuggestedRowSaver.save([good,bad], game: .vikinglotto, date: LotteryCalendar.date("2026-10-07")!, context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 0)
    }
}
