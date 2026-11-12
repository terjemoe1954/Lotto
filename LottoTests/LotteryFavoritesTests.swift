import Foundation
import SwiftData
import Testing
@testable import Lotto

private struct FixedFavoriteRandom: RandomNumberGenerator { mutating func next() -> UInt64 { 0 } }

@MainActor
struct LotteryFavoritesTests {
    private func container(url: URL? = nil) throws -> ModelContainer {
        let config = url.map { ModelConfiguration(url: $0, cloudKitDatabase: .none) } ?? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self, configurations: config)
    }
    @Test func gameSpecificRangesLimitsAndSeparatePoolsAreValidated() {
        #expect(LotteryFavoriteSelection(mainNumbers: [1,34]).validation(for: .lotto) == nil)
        #expect(LotteryFavoriteSelection(mainNumbers: [35]).validation(for: .lotto) != nil)
        #expect(LotteryFavoriteSelection(mainNumbers: [3], extraNumbers: [3]).validation(for: .vikinglotto) == nil)
        #expect(LotteryFavoriteSelection(mainNumbers: [1,1]).validation(for: .eurojackpot) != nil)
        #expect(LotteryFavoriteSelection(extraNumbers: [1]).validation(for: .lotto) != nil)
        #expect(LotteryFavoriteSelection(mainNumbers: Array(1...6)).validation(for: .eurojackpot) != nil)
        #expect(LotteryFavoriteSelection(extraNumbers: [13]).validation(for: .eurojackpot) != nil)
        let bad = LotteryFavoriteSelection(mainNumbers: [0,2,2,90], extraNumbers: [3,90])
        #expect(bad.effective(for: .vikinglotto).mainNumbers == [2])
        #expect(bad.effective(for: .vikinglotto).extraNumbers == [3])
    }
    @Test func lottoUsesOneFavoriteRowAndStillGeneratesUniqueRows() {
        for mode in SuggestionMode.allCases {
            let rows = LottoSuggestionEngine.makeSuggestedRows(for: LotteryCalendar.date("2026-11-14")!, predictedNumbers: [7,8,9], jackpots: [], mode: mode, rowCount: 20, favoriteNumbers: [1,34])
            #expect(rows.count == 20)
            #expect(Set(rows.map(\.id)).count == 20)
            #expect(rows[0].numbers.contains(1) && rows[0].numbers.contains(34))
            #expect(rows.dropFirst().contains { !$0.numbers.contains(1) || !$0.numbers.contains(34) })
            #expect(rows.allSatisfy { $0.numbers.count == 7 && Set($0.numbers).count == 7 })
        }
        let fixed = LottoSuggestionEngine.makeSuggestedRows(for: .now, predictedNumbers: [], jackpots: [], rowCount: 20, favoriteNumbers: Array(1...7))
        #expect(fixed.count == 20)
        #expect(fixed[0].numbers == Array(1...7))
    }
    @Test func internationalFavoritesOnlyLockTheFirstRow() {
        for game in InternationalGame.allCases {
            for mode in InternationalSuggestionMode.allCases {
                let extra = game == .vikinglotto ? [3] : [12]
                let selection = LotteryFavoriteSelection(mainNumbers: [2,17], extraNumbers: extra)
                let batch = InternationalSuggestionEngine.makeRows(game: game, date: LotteryCalendar.date("2026-11-10")!, records: [], mode: mode, count: 20, favorites: selection)
                #expect(batch.rows.count == 20)
                #expect(batch.rows[0].mainNumbers.contains(2) && batch.rows[0].mainNumbers.contains(17) && Set(extra).isSubset(of: batch.rows[0].extraNumbers))
                #expect(batch.rows.dropFirst().contains { !$0.mainNumbers.contains(2) || !$0.mainNumbers.contains(17) })
                #expect(batch.rows.allSatisfy { game.validation(main: $0.mainNumbers, extra: $0.extraNumbers, date: batch.date) == nil })
            }
        }
    }
    @Test func limitedCombinationsAndFallbackNeverInventDuplicates() {
        let favorites = LotteryFavoriteSelection(mainNumbers: Array(1...6))
        #expect(favorites.combinations(for: .vikinglotto) == 5)
        var rng = FixedFavoriteRandom()
        let batch = InternationalSuggestionEngine.makeRows(game: .vikinglotto, date: .now, records: [], count: 20, favorites: favorites, using: &rng)
        #expect(batch.rows.count == 20)
        #expect(Set(batch.rows.map(\.id)).count == 20)
        let all = LotteryFavoriteSelection(mainNumbers: [1,2,3,4,5], extraNumbers: [1,12])
        #expect(all.combinations(for: .eurojackpot) == 1)
        let full = InternationalSuggestionEngine.makeRows(game: .eurojackpot, date: .now, records: [], count: 20, favorites: all)
        #expect(full.rows.count == 20)
        #expect(full.rows[0].extraNumbers == [1,12])
        #expect(LotteryFavoriteSelection(mainNumbers: Array(1...7)).completions(for: .lotto, limit: 20).count == 1)
    }
    @Test func disabledFavoritesUseTheSameRandomStreamAsNoFavorites() {
        var a = FixedFavoriteRandom(), b = FixedFavoriteRandom()
        let withDisabled = InternationalSuggestionEngine.makeRows(game: .eurojackpot, date: .now, records: [], mode: .random, count: 5,
            favorites: LotteryFavoriteSelection(mainNumbers: [50], extraNumbers: [12], enabled: false), using: &a)
        let without = InternationalSuggestionEngine.makeRows(game: .eurojackpot, date: .now, records: [], mode: .random, count: 5, using: &b)
        #expect(withDisabled.rows == without.rows)
    }
    @Test func clearAndDisablePersistAndResolveOldCloudCopies() throws {
        let c = try container(), context = c.mainContext
        try LotteryFavorites.save([.lotto: LotteryFavoriteSelection(mainNumbers: [2,9])], context: context, now: Date(timeIntervalSince1970: 10))
        let old = try context.fetch(FetchDescriptor<LotteryFavoriteChange>()).map(\.record)
        try LotteryFavorites.save([.lotto: LotteryFavoriteSelection(mainNumbers: [2,9], enabled: false)], context: context, now: Date(timeIntervalSince1970: 20))
        let disabled = try context.fetch(FetchDescriptor<LotteryFavoriteChange>()).map(\.record)
        #expect(!LotteryFavorites.selection(for: .lotto, records: old + disabled).enabled)
        try LotteryFavorites.save([.lotto: LotteryFavoriteSelection()], context: context, now: Date(timeIntervalSince1970: 30))
        let cleared = try context.fetch(FetchDescriptor<LotteryFavoriteChange>()).map(\.record)
        #expect(LotteryFavorites.selection(for: .lotto, records: cleared + old).mainNumbers.isEmpty)
        #expect(LotteryFavorites.latest(cleared + old) == LotteryFavorites.latest(old + cleared))
        let before = cleared.count
        #expect(throws: (any Error).self) { try LotteryFavorites.save([.lotto: LotteryFavoriteSelection(mainNumbers: [128])], context: context) }
        #expect(try context.fetchCount(FetchDescriptor<LotteryFavoriteChange>()) == before)
    }
    @Test func fullBackupAndLegacyRestorePreserveFavoritesWhileDrawsOnlyExcludesThem() throws {
        let source = try container(), target = try container()
        let settings = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        let value = LotteryFavoriteSelection(mainNumbers: [2,9], extraNumbers: [3])
        try LotteryFavorites.save([.vikinglotto: value], context: source.mainContext)
        let snapshot = try LottoBackupStore.snapshot(context: source.mainContext, content: .everything, settings: settings)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LottoBackupSnapshot.self, from: encoder.encode(snapshot))
        _ = try LottoBackupStore.check(decoded)
        try LottoBackupStore.restoreEverything(decoded, context: target.mainContext)
        var saved = try target.mainContext.fetch(FetchDescriptor<LotteryFavoriteChange>()).map(\.record)
        #expect(LotteryFavorites.selection(for: .vikinglotto, records: saved) == value)
        let legacy = LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: [], results: [])
        try LottoBackupStore.restoreEverything(legacy, context: target.mainContext)
        saved = try target.mainContext.fetch(FetchDescriptor<LotteryFavoriteChange>()).map(\.record)
        #expect(LotteryFavorites.selection(for: .vikinglotto, records: saved) == value)
        let draws = try LottoBackupStore.snapshot(context: source.mainContext, content: .drawsOnly, settings: settings)
        #expect(draws.favorites == nil)
    }
    @Test func addingFavoriteModelPreservesExistingDiskRowsAndDeliveryState() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("migration.store")
        func seedOld() throws {
            let c = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = c.mainContext
            context.insert(Result(dato: .now,nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7))
            try LotteryDeliverySync.set(true, keys: ["existing"], context: context)
        }
        try seedOld()
        let upgraded = try container(url: url)
        #expect(try upgraded.mainContext.fetchCount(FetchDescriptor<Result>()) == 1)
        #expect(try upgraded.mainContext.fetchCount(FetchDescriptor<LotteryDeliveryChange>()) == 1)
        try LotteryFavorites.save([.lotto: LotteryFavoriteSelection(mainNumbers: [1])], context: upgraded.mainContext)
        #expect(try upgraded.mainContext.fetchCount(FetchDescriptor<LotteryFavoriteChange>()) == 1)
    }
}
