import Foundation

enum LotterySpending {
    struct Month: Identifiable {
        let date: Date
        let stakeOre: Int
        var id: Date { date }
    }
    struct Scenario {
        let monthlyOre: Int
        let yearlyOre: Int
        let monthlySavingOre: Int
        let yearlySavingOre: Int
    }
    static func months(records: [LotteryLedgerRecord], ending month: Date, now: Date = .now) -> [Month] {
        let calendar = LotteryCalendar.calendar
        let end = calendar.dateInterval(of: .month, for: month)!.start
        let recorded = records.filter { $0.isValid && $0.date <= now }
        return (-11...0).map { offset in
            let start = calendar.date(byAdding: .month, value: offset, to: end)!
            let stop = calendar.date(byAdding: .month, value: 1, to: start)!
            return Month(date: start, stakeOre: recorded.filter { $0.date >= start && $0.date < stop }.reduce(0) { $0 + $1.stakeOre })
        }
    }
    static func yearStake(records: [LotteryLedgerRecord], selected month: Date, now: Date = .now) -> Int {
        let interval = LotteryCalendar.calendar.dateInterval(of: .year, for: month)!
        return records.filter { $0.isValid && $0.date >= interval.start && $0.date < interval.end && $0.date <= now }.reduce(0) { $0 + $1.stakeOre }
    }
    static func scenario(monthlyOre: Int, reductionPercent: Int) -> Scenario {
        let baseline = max(0, monthlyOre), percent = min(100, max(0, reductionPercent))
        let reduced = baseline * (100 - percent) / 100
        return Scenario(monthlyOre: reduced, yearlyOre: reduced * 12,
                        monthlySavingOre: baseline - reduced, yearlySavingOre: (baseline - reduced) * 12)
    }
}
