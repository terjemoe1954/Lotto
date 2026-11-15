import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor struct LotterySystemTests {
    private let saturday = LotteryCalendar.date("2026-11-14")!
    @Test func officialSystemSizesAndLimits() {
        #expect([8,9,10,11,12].map { LotterySystem.rowCount(game: .lotto, main: $0, extra: 0) } == [8,36,120,330,792])
        #expect(LotterySystem.rowCount(game: .vikinglotto, main: 8, extra: 3) == 84)
        #expect(LotterySystem.rowCount(game: .eurojackpot, main: 7, extra: 2) == 21)
        #expect(LotterySystem.validation(game: .vikinglotto, main: Array(1...12), extra: [1,2,3], date: LotteryCalendar.date("2026-11-18")!) != nil)
        #expect(LotterySystem.rows(game: .lotto, main: [1,1,2,3,4,5,6,7], extra: [], date: saturday).isEmpty)
        #expect(LotterySystem.rows(game: .lotto, main: Array(1...8), extra: [], date: LotteryCalendar.date("2026-11-15")!).isEmpty)
    }
    @Test func officialLottoNineNumberPrizeDistribution() {
        // Official table: 9 selected, 6 main + bonus -> 1 second, 2 third,
        // 18 fourth and 15 fifth prizes. No overlap between prize tiers.
        let rows = LotterySystem.rows(game: .lotto, main: [1,2,3,4,5,6,8,9,10], extra: [], date: saturday)
        var distribution: [Int:Int] = [:]
        for row in rows {
            let main = Set(row.mainNumbers).intersection([1,2,3,4,5,6,7]).count
            let extra = row.mainNumbers.contains(8) ? 1 : 0
            if let tier = AutomaticLotteryLedger.tier(game: .lotto, main: main, extra: extra) { distribution[tier, default: 0] += 1 }
        }
        #expect(distribution == [2:1,3:2,4:18,5:15])
        #expect(Set(rows.map(\.id)).count == 36)
        #expect(rows.count * AutomaticLotteryLedger.priceOre(.lotto) == 18000)
    }
    @Test func officialEuroSystemPrizesAndDrawIsolation() {
        let date = LotteryCalendar.date("2026-11-13")!
        var rows = LotterySystem.rows(game: .eurojackpot, main: Array(1...7), extra: [1,2], date: date)
        rows = rows.map { var row = $0; row.isRegistered = true; return row }
        let table = LotteryPrizeTable(gameID: "eurojackpot", date: date, main: [1,2,3,4,5], extra: [1,2], payouts: [1:10000,4:100,6:10])
        let items = AutomaticLotteryLedger.items(rows: rows, tables: [table])
        #expect(items.reduce(0) { $0 + ($1.prizeOre ?? 0) } == 11100)
        let wrong = LotteryPrizeTable(gameID: "eurojackpot", date: saturday, main: table.main, extra: table.extra, payouts: table.payouts)
        #expect(AutomaticLotteryLedger.items(rows: rows, tables: [wrong]).allSatisfy { $0.prizeOre == nil })
    }
    @Test func savesAdditivelyAndAvoidsDuplicates() throws {
        let container = try ModelContainer(for: Result.self, InternationalLotteryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let rows = LotterySystem.rows(game: .lotto, main: Array(1...8), extra: [], date: saturday)
        #expect(try LotterySystem.save(rows, context: container.mainContext) == 8)
        #expect(try LotterySystem.save(rows, context: container.mainContext) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Result>()) == 8)
    }
}
