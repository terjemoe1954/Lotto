import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor struct AutomaticLotteryLedgerTests {
    private func row(_ game: LotteryReportGame = .lotto, date: String = "2026-11-07", main: [Int] = [1,2,3,4,5,6,7], extra: [Int] = []) -> LotteryReportRow {
        LotteryReportRow(game: game, date: LotteryCalendar.date(date)!, mainNumbers: main, extraNumbers: extra, isRegistered: true)
    }
    @Test func deliveryConvergesAndUnmarkRemovesExpense() throws {
        let played = row(), time = Date()
        let a = LotteryDeliveryRecord(rowKey: played.id, registered: true, changedAt: time, changeID: "a")
        let b = LotteryDeliveryRecord(rowKey: played.id, registered: true, changedAt: time, changeID: "b")
        let duplicateRows = AutomaticLotteryLedger.deliveredRows([a,b,a])
        #expect(duplicateRows.count == 1)
        #expect(AutomaticLotteryLedger.items(rows: duplicateRows + duplicateRows, tables: []).map(\.record.stakeOre) == [500])
        let undo = LotteryDeliveryRecord(rowKey: played.id, registered: false, changedAt: time.addingTimeInterval(1), changeID: "c")
        #expect(AutomaticLotteryLedger.deliveredRows([undo,a,b]).isEmpty)
        let again = LotteryDeliveryRecord(rowKey: played.id, registered: true, changedAt: time.addingTimeInterval(2), changeID: "d")
        #expect(AutomaticLotteryLedger.deliveredRows([again,undo,a]).count == 1)
        // No saved Result is needed to retain the historical delivered expense.
        #expect(AutomaticLotteryLedger.parse(played.id)?.id == played.id)
    }
    @Test func priceAndDateIsolation() {
        let lotto = row(), viking = row(.vikinglotto, date: "2026-11-04", main: [1,2,3,4,5,6], extra: [1])
        let euro = row(.eurojackpot, date: "2026-11-03", main: [1,2,3,4,5], extra: [1,2])
        let items = AutomaticLotteryLedger.items(rows: [lotto,viking,euro], tables: [])
        #expect(items.map(\.record.stakeOre) == [500,800,2500])
        #expect(LotteryLedger.totals(items.map(\.record)).stake == 3800)
        #expect(items.allSatisfy { $0.prizeOre == nil })
        #expect(LotteryLedger.shouldPause(stake: LotteryLedger.totals(items.map(\.record)).stake, budget: 3800))
        var unplayed = lotto; unplayed.isRegistered = false
        #expect(AutomaticLotteryLedger.items(rows: [unplayed], tables: []).isEmpty)
        let wrongDate = LotteryPrizeTable(gameID: "lotto", date: LotteryCalendar.date("2026-10-31")!, main: lotto.mainNumbers, extra: [8], payouts: [1:100000])
        #expect(AutomaticLotteryLedger.items(rows: [lotto], tables: [wrongDate])[0].prizeOre == nil)
    }
    @Test func invalidLegacyKeysCannotCreateExpenses() {
        let valid = row().id
        for bad in ["", "old-legacy-key", valid.replacingOccurrences(of: "2026-11-07", with: "2026-11-08"), valid.replacingOccurrences(of: "2026-11-07", with: "2026-02-31"), row(main: [2,4,7,8,15,128,25]).id, row(main: [1,1,2,3,4,5,6]).id, row(main: [1,2,3,4,5,6]).id, valid.replacingOccurrences(of: "2026-11-07", with: "2022-11-05")] {
            #expect(AutomaticLotteryLedger.parse(bad) == nil)
        }
    }
    @Test func allPrizeGroupsUseOnlyTheHighestApplicableTier() {
        let cases: [(LotteryReportGame,Int,Int,Int?)] = [
            (.lotto,7,0,1),(.lotto,6,1,2),(.lotto,6,0,3),(.lotto,5,1,4),(.lotto,4,1,5),(.lotto,3,1,nil),
            (.vikinglotto,6,1,1),(.vikinglotto,6,0,2),(.vikinglotto,5,1,3),(.vikinglotto,5,0,4),(.vikinglotto,4,1,5),(.vikinglotto,3,0,6),(.vikinglotto,2,1,nil),
            (.eurojackpot,5,2,1),(.eurojackpot,5,1,2),(.eurojackpot,5,0,3),(.eurojackpot,4,2,4),(.eurojackpot,4,1,5),(.eurojackpot,3,2,6),(.eurojackpot,4,0,7),(.eurojackpot,2,2,8),(.eurojackpot,3,1,9),(.eurojackpot,3,0,10),(.eurojackpot,1,2,11),(.eurojackpot,2,1,12),(.eurojackpot,2,0,nil),(.eurojackpot,0,2,nil)]
        for (game,main,extra,expected) in cases { #expect(AutomaticLotteryLedger.tier(game: game, main: main, extra: extra) == expected) }
    }
    @Test func lottoExtraNumberAndPendingJackpotAreHandled() {
        let draw = LotteryPrizeTable(gameID: "lotto", date: row().date, main: [1,2,3,4,5,6,7], extra: [8], payouts: [2:10000,3:4000,4:11000,5:5000])
        let rows = [row(), row(main: [1,2,3,4,5,6,8]), row(main: [1,2,3,4,5,6,9]), row(main: [1,2,3,4,9,10,11]), row(main: [9,10,11,12,13,14,15])]
        let results = rows.map { AutomaticLotteryLedger.items(rows: [$0], tables: [draw])[0].prizeOre }
        #expect(results == [nil,10000,4000,5000,0])
    }
    @Test func apiFixturesDecodeOrdinaryAmountsWithoutNationalRaffles() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for (game,file) in [(LotteryReportGame.vikinglotto,"vikinglotto-response"),(.eurojackpot,"eurojackpot-response")] {
            let data = try Data(contentsOf: folder.appendingPathComponent(file + ".json"))
            let tables = try LotteryPrizeAPI.decode(data, game: game)
            let table = try #require(tables.first)
            #expect(table.payouts[1] == nil) // Published jackpot with zero winners is not a payout.
            let pending = row(game, date: LotteryCalendar.text(table.date), main: table.main, extra: table.extra)
            #expect(AutomaticLotteryLedger.items(rows: [pending], tables: tables)[0].prizeOre == nil)
            #expect(table.payouts[21] == nil) // National raffle cannot be inferred from numbers.
            if game == .vikinglotto {
                let played = row(game, date: LotteryCalendar.text(table.date), main: [1,11,31,2,3,4], extra: [1])
                #expect(AutomaticLotteryLedger.items(rows: [played], tables: tables)[0].prizeOre == 9000)
            } else {
                let played = row(game, date: LotteryCalendar.text(table.date), main: [50,2,3,4,5], extra: [1,6])
                #expect(AutomaticLotteryLedger.items(rows: [played], tables: tables)[0].prizeOre == 14500)
            }
        }
    }
    @Test func unfinishedOrMissingAmountsNeverBecomeZeroWins() throws {
        let numbers = (1...7).map { ["number":String($0),"type":1] as [String:Any] } + [["number":"8","type":2]]
        func payload(final: Bool, prizes: [[String:Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["gameResult":[["drawDate":"2026-11-07T17:30:00Z","isFinalized":final,"winnerNumber":numbers,"prize":prizes]]])
        }
        let prizes: [[String:Any]] = [["id":1,"name":"7 rette","value":"1400000000","winners":"1"], ["id":5,"name":"4 rette","value":"50","winners":"100"]]
        #expect(try LotteryPrizeAPI.decode(payload(final: false, prizes: prizes), game: .lotto).isEmpty)
        let table = try #require(LotteryPrizeAPI.decode(payload(final: true, prizes: prizes), game: .lotto).first)
        #expect(table.payouts[1] == 140_000_000_000)
        #expect(table.payouts[5] == 5000)
        let missing = try #require(LotteryPrizeAPI.decode(payload(final: true, prizes: []), game: .lotto).first)
        #expect(AutomaticLotteryLedger.items(rows: [row()], tables: [missing])[0].prizeOre == nil)
        let mismatch = try #require(LotteryPrizeAPI.decode(payload(final: true, prizes: [["id":1,"name":"4 rette","value":"50","winners":"100"]]), game: .lotto).first)
        #expect(mismatch.payouts.isEmpty)
    }
    @Test func automaticAmountsSurviveDeliveryBackupWithoutCreatingManualPosts() throws {
        let store = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = store.mainContext
        try LotteryDeliverySync.set(true, keys: [row().id], context: context)
        #expect(try context.fetchCount(FetchDescriptor<LotteryLedgerEntry>()) == 0)
        let settings = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        let snapshot = try LottoBackupStore.snapshot(context: context, content: .everything, settings: settings)
        try LottoBackupStore.restoreEverything(snapshot, context: context)
        let rows = AutomaticLotteryLedger.deliveredRows(try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
        #expect(AutomaticLotteryLedger.items(rows: rows, tables: []).map(\.record.stakeOre) == [500])
        #expect(try context.fetchCount(FetchDescriptor<LotteryLedgerEntry>()) == 0)
    }
    @Test func cachePersistsAmountsAndKeepsThemOnNetworkFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("prizes.json")
        let cache = LotteryPrizeCache(file: file)
        let played = row()
        let table = LotteryPrizeTable(gameID: "lotto", date: played.date, main: [1,2,3,4,5,6,7], extra: [8], payouts: [1:150000])
        var requests = 0
        await cache.refresh(rows: [played,played], now: LotteryCalendar.date("2026-11-12")!) { game, from, to in
            requests += 1
            #expect(game == .lotto)
            #expect(LotteryCalendar.text(from) == "2026-11-07")
            #expect(LotteryCalendar.text(to) == "2026-11-13")
            return [table]
        }
        #expect(requests == 1)
        #expect(cache.error == nil)
        #expect(LotteryPrizeCache(file: file).tables == [table])
        await cache.refresh(rows: [played]) { _,_,_ in throw URLError(.notConnectedToInternet) }
        #expect(cache.tables == [table])
        #expect(cache.error != nil)
        #expect(!cache.updating)
        #expect(AutomaticLotteryLedger.items(rows: [played], tables: cache.tables)[0].prizeOre == 150000)
        requests = 0
        await cache.refresh(rows: [row(date: "2026-11-14")], now: LotteryCalendar.date("2026-11-12")!) { _,_,_ in
            requests += 1; return []
        }
        #expect(requests == 0)
    }

}
