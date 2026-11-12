import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor struct LotteryLedgerTests {
    @Test func parsesNorwegianAmountsWithoutRoundingOrNegativeExpenses() {
        #expect(LotteryLedger.ore("100,25") == 10025)
        #expect(LotteryLedger.ore("0.01") == 1)
        for invalid in ["", "-5", "1,001", "nan", "1e3", "1.000,00", "1000000001"] {
            #expect(LotteryLedger.ore(invalid) == nil)
        }
        #expect(LotteryLedger.shouldPause(stake: 10000, budget: 10000))
        #expect(!LotteryLedger.shouldPause(stake: 9999, budget: 10000))
        #expect(!LotteryLedger.shouldPause(stake: 10000, budget: nil))
        let records = [LotteryLedgerRecord(id: "a", gameID: "lotto", date: .now, stakeOre: 10000, prizeOre: 2000, note: "")]
        #expect(LotteryLedger.totals(records).stake == 10000)
        #expect(LotteryLedger.totals(records).prize == 2000)
    }
    @Test func ledgerRoundTripsBackupAndLegacyBackupsPreserveIt() throws {
        func store() throws -> ModelContainer {
            try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
                               configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
        let source = try store(), target = try store()
        let record = LotteryLedgerRecord(id: "manual", gameID: "lotto", date: LotteryCalendar.date("2026-11-07")!, stakeOre: 10000, prizeOre: 4500, note: "Faktisk spilt")
        source.mainContext.insert(LotteryLedgerEntry(record: record)); try source.mainContext.save()
        let settings = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        let snapshot = try LottoBackupStore.snapshot(context: source.mainContext, content: .everything, settings: settings)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(LottoBackupSnapshot.self, from: encoder.encode(snapshot))
        _ = try LottoBackupStore.check(restored)
        try LottoBackupStore.restoreEverything(restored, context: target.mainContext)
        #expect(try target.mainContext.fetch(FetchDescriptor<LotteryLedgerEntry>()).map(\.record) == [record])
        let legacy = LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: [], results: [])
        try LottoBackupStore.restoreEverything(legacy, context: target.mainContext)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<LotteryLedgerEntry>()) == 1)
        #expect(try LottoBackupStore.snapshot(context: source.mainContext, content: .drawsOnly, settings: settings).ledger == nil)
        var bad = restored
        bad.ledger![0].stakeOre = -1
        #expect(throws: (any Error).self) { try LottoBackupStore.restoreEverything(bad, context: target.mainContext) }
        #expect(try target.mainContext.fetch(FetchDescriptor<LotteryLedgerEntry>()).map(\.record) == [record])
        var empty = restored; empty.ledger = []
        try LottoBackupStore.restoreEverything(empty, context: target.mainContext)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<LotteryLedgerEntry>()) == 0)
    }
    @Test func ordinaryPrizeThresholdsHandleSeparatePools() {
        let date = Date()
        #expect(LotteryPrizeRules.qualifies(game: .lotto, main: 4, extra: 0, date: date))
        #expect(!LotteryPrizeRules.qualifies(game: .lotto, main: 3, extra: 1, date: date))
        #expect(LotteryPrizeRules.qualifies(game: .vikinglotto, main: 3, extra: 0, date: date))
        #expect(!LotteryPrizeRules.qualifies(game: .vikinglotto, main: 2, extra: 1, date: date))
        #expect(LotteryPrizeRules.qualifies(game: .eurojackpot, main: 1, extra: 2, date: date))
        #expect(LotteryPrizeRules.qualifies(game: .eurojackpot, main: 2, extra: 1, date: date))
        #expect(LotteryPrizeRules.qualifies(game: .eurojackpot, main: 3, extra: 0, date: date))
        #expect(!LotteryPrizeRules.qualifies(game: .eurojackpot, main: 2, extra: 0, date: date))
        #expect(!LotteryPrizeRules.qualifies(game: .eurojackpot, main: -1, extra: -1, date: date))
    }
}
