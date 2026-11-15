import Foundation
import Testing
@testable import Lotto

@MainActor struct LotterySpendingTests {
    private func record(_ id: String, _ date: String, _ stake: Int, prize: Int = 0) -> LotteryLedgerRecord {
        LotteryLedgerRecord(id: id, gameID: "lotto", date: LotteryCalendar.date(date)!, stakeOre: stake, prizeOre: prize, note: "")
    }
    @Test func historyUsesOsloMonthsAndDoesNotCountFutureOrPrizes() {
        let now = LotteryCalendar.date("2026-11-14")!
        let rows = [record("lastyear", "2025-11-30", 999), record("dec", "2025-12-01", 1200), record("oct", "2026-10-31", 2000), record("nov", "2026-11-01", 3000, prize: 50000), record("future", "2026-11-21", 9000)]
        let months = LotterySpending.months(records: rows, ending: now, now: now)
        #expect(months.count == 12)
        #expect(LotteryCalendar.text(months.first!.date) == "2025-12-01")
        #expect(months.first!.stakeOre == 1200)
        #expect(months[10].stakeOre == 2000)
        #expect(months[11].stakeOre == 3000)
        #expect(months[1].stakeOre == 0)
        #expect(LotterySpending.yearStake(records: rows, selected: now, now: now) == 5000)
        #expect(LotterySpending.months(records: [], ending: now, now: now).allSatisfy { $0.stakeOre == 0 })
    }
    @Test func reducedScenarioIsArithmeticAndDoesNotMutateHistory() {
        let original = [record("nov", "2026-11-01", 100000)]
        let snapshot = original
        let reduced = LotterySpending.scenario(monthlyOre: original[0].stakeOre, reductionPercent: 25)
        #expect(reduced.monthlyOre == 75000)
        #expect(reduced.yearlyOre == 900000)
        #expect(reduced.monthlySavingOre == 25000)
        #expect(reduced.yearlySavingOre == 300000)
        #expect(original == snapshot)
        #expect(LotterySpending.scenario(monthlyOre: 100000, reductionPercent: 100).yearlyOre == 0)
        #expect(LotterySpending.scenario(monthlyOre: 100000, reductionPercent: 0).yearlyOre == 1200000)
        #expect(LotterySpending.scenario(monthlyOre: 0, reductionPercent: 25).monthlyOre == 0)
    }
    @Test func correctionImmediatelyChangesTotals() {
        let now = LotteryCalendar.date("2026-11-14")!
        let values = [record("a", "2026-11-01", 5000), record("b", "2026-11-02", 2500)]
        #expect(LotterySpending.months(records: values, ending: now, now: now).last!.stakeOre == 7500)
        #expect(LotterySpending.months(records: Array(values.dropLast()), ending: now, now: now).last!.stakeOre == 5000)
    }
}
