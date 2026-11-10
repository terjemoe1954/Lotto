import Foundation
import Testing
@testable import Lotto

@MainActor
struct InternationalStatisticsTests {
    private func record(_ date: String, main: [Int] = [1,2,3,4,5,6], extra: [Int] = [1],
                        game: InternationalGame = .vikinglotto, isDraw: Bool = true) -> InternationalLotteryRecord {
        InternationalLotteryRecord(gameID: game.rawValue, isDraw: isDraw, date: LotteryCalendar.date(date)!,
                                   mainNumbers: main, extraNumbers: extra)
    }

    @Test func poolsHaveIndependentFrequenciesAndIntervals() {
        let records = [record("2026-10-07"), record("2026-10-14", main: [7,8,9,10,11,12]),
                       record("2026-10-21", extra: [2]), record("2026-10-28", main: [7,8,9,10,11,12], extra: [2]),
                       record("2026-11-04", extra: [2])]
        let today = LotteryCalendar.date("2026-11-10")!
        let main = InternationalLotteryStatistics.report(records: records, game: .vikinglotto, extraPool: false, asOf: today)
        let extra = InternationalLotteryStatistics.report(records: records, game: .vikinglotto, extraPool: true, asOf: today)
        #expect(main.drawCount == 5)
        #expect(main.rows.count == 48)
        #expect(extra.rows.count == 5)
        let one = main.rows[0]
        #expect(one.count == 3)
        #expect(one.share == 0.6)
        #expect(one.averageDays == 14)
        #expect(one.averageDraws == 2)
        #expect(one.daysSinceLast == 6)
        #expect(one.drawsSinceLast == 0)
        #expect(one.longestGapDays == 14)
        #expect(extra.rows[0].count == 2)
        #expect(extra.rows[0].averageDays == 7)
        #expect(extra.rows[0].averageDraws == 1)
        #expect(extra.rows[0].drawsSinceLast == 3)
        #expect(main.missingDrawCount == 0)
    }

    @Test func eurojackpotUsesActualThreeAndFourDaySpacing() {
        let records = [record("2026-10-02", main: [1,2,3,4,5], extra: [1,12], game: .eurojackpot),
                       record("2026-10-06", main: [6,7,8,9,10], extra: [1,11], game: .eurojackpot),
                       record("2026-10-09", main: [1,2,3,4,5], extra: [2,10], game: .eurojackpot),
                       record("2026-10-13", main: [6,7,8,9,10], extra: [3,9], game: .eurojackpot)]
        let today = LotteryCalendar.date("2026-10-14")!
        let main = InternationalLotteryStatistics.report(records: records, game: .eurojackpot, extraPool: false, asOf: today)
        let extra = InternationalLotteryStatistics.report(records: records, game: .eurojackpot, extraPool: true, asOf: today)
        #expect(main.rows[0].averageDays == 7)
        #expect(main.rows[0].averageDraws == 2)
        #expect(main.rows[0].drawsSinceLast == 1)
        #expect(main.rows[0].daysSinceLast == 5)
        #expect(extra.rows[0].averageDays == 4)
        #expect(extra.rows[0].averageDraws == 1)
        #expect(main.missingDrawCount == 0)
    }

    @Test func duplicatesOwnRowsOtherGamesInvalidAndFutureDrawsAreIgnored() {
        let original = record("2026-10-07")
        let records = [original, original, record("2026-10-14", isDraw: false),
                       record("2026-10-09", main: [1,2,3,4,5], extra: [1,2], game: .eurojackpot),
                       record("2026-10-21", main: [1,1,2,3,4,5]), record("2026-11-11")]
        let report = InternationalLotteryStatistics.report(records: records, game: .vikinglotto,
                                                           extraPool: false, asOf: LotteryCalendar.date("2026-11-10")!)
        #expect(report.drawCount == 1)
        #expect(report.rows[0].count == 1)
        #expect(report.rows[0].averageDays == nil)
        #expect(report.rows[0].averageDraws == nil)
        #expect(report.rows[0].longestGapDays == nil)
        #expect(report.rows[47].lastDate == nil)
        #expect(report.rows[47].drawsSinceLast == nil)
        #expect(report.sorted(by: .longestAbsence).first?.number == 7)
    }

    @Test func emptyHistoryAndEmptyPeriodHaveNoInventedIntervals() {
        let empty = InternationalLotteryStatistics.report(records: [], game: .eurojackpot, extraPool: true)
        #expect(empty.drawCount == 0)
        #expect(empty.rows.count == 12)
        #expect(empty.rows.allSatisfy { $0.count == 0 && $0.share == 0 && $0.lastDate == nil && $0.averageDays == nil })
        let report = InternationalLotteryStatistics.report(records: [record("2025-01-01")], game: .vikinglotto,
                                                           extraPool: false, period: .thisYear,
                                                           asOf: LotteryCalendar.date("2026-11-10")!)
        #expect(report.drawCount == 0)
        #expect(report.firstDate == nil)
    }

    @Test func periodsUseCalendarBoundariesAndLatestHundredDraws() {
        let records = [record("2025-11-05"), record("2025-11-12"), record("2025-12-31"), record("2026-01-07")]
        let today = LotteryCalendar.date("2026-11-10")!
        let annual = InternationalLotteryStatistics.report(records: records, game: .vikinglotto, extraPool: false, period: .thisYear, asOf: today)
        let rolling = InternationalLotteryStatistics.report(records: records, game: .vikinglotto, extraPool: false, period: .last12Months, asOf: today)
        #expect(annual.drawCount == 1)
        #expect(rolling.drawCount == 3)
        let start = LotteryCalendar.date("2023-01-04")!
        let many = (0..<120).map { offset in
            InternationalLotteryRecord(gameID: "vikinglotto", isDraw: true,
                date: LotteryCalendar.calendar.date(byAdding: .day, value: offset * 7, to: start)!,
                mainNumbers: [1,2,3,4,5,6], extraNumbers: [1])
        }
        let hundred = InternationalLotteryStatistics.report(records: Array(many.reversed()), game: .vikinglotto,
                                                            extraPool: false, period: .last100Draws, asOf: today)
        #expect(hundred.drawCount == 100)
        #expect(hundred.firstDate == many[20].date)
        #expect(hundred.rows[0].count == 100)
        #expect(hundred.rows[0].share == 1)
    }

    @Test func longestGapOptionChangesOnlyAverages() {
        let records = ["2026-10-07", "2026-10-14", "2026-10-21", "2026-11-11", "2026-11-18"].map { record($0) }
        let today = LotteryCalendar.date("2026-11-20")!
        let normal = InternationalLotteryStatistics.report(records: records, game: .vikinglotto, extraPool: false, asOf: today)
        let trimmed = InternationalLotteryStatistics.report(records: records, game: .vikinglotto, extraPool: false,
                                                            excludeHighestGap: true, asOf: today)
        #expect(normal.rows[0].averageDays == 10.5)
        #expect(trimmed.rows[0].averageDays == 7)
        #expect(trimmed.rows[0].longestGapDays == 21)
        #expect(trimmed.rows[0].count == 5)
        #expect(trimmed.rows[0].lastDate == normal.rows[0].lastDate)
        #expect(trimmed.missingDrawCount == 2)
        let singleGap = InternationalLotteryStatistics.report(records: Array(records.prefix(2)), game: .vikinglotto,
                                                              extraPool: false, excludeHighestGap: true, asOf: today)
        #expect(singleGap.rows[0].averageDays == 7)
    }

    @Test func daylightSavingUsesCalendarDaysAndSortingIsStable() {
        let records = [record("2026-10-21"), record("2026-10-28", main: [1,7,8,9,10,11])]
        let report = InternationalLotteryStatistics.report(records: records, game: .vikinglotto,
                                                           extraPool: false, asOf: LotteryCalendar.date("2026-10-29")!)
        #expect(report.rows[0].averageDays == 7)
        #expect(report.rows[0].daysSinceLast == 1)
        #expect(report.sorted(by: .mostFrequent).first?.number == 1)
        #expect(report.sorted(by: .leastFrequent).first?.number == 12)
        #expect(report.sorted(by: .number).map(\.number) == Array(1...48))
    }
}

@MainActor
struct InternationalArchiveStatisticsTests {
    @Test func archiveTotalsMatchNumberOfBallsAndDraws() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Lotto/Helpers/international-draws.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([InternationalLotteryRecord].self, from: Data(contentsOf: path))
        let today = LotteryCalendar.date("2026-11-10")!
        for game in InternationalGame.allCases {
            let main = InternationalLotteryStatistics.report(records: records, game: game, extraPool: false, asOf: today)
            let extra = InternationalLotteryStatistics.report(records: records, game: game, extraPool: true, asOf: today)
            #expect(main.drawCount == (game == .vikinglotto ? 201 : 402))
            #expect(main.rows.reduce(0) { $0 + $1.count } == main.drawCount * game.mainCount)
            #expect(extra.rows.reduce(0) { $0 + $1.count } == main.drawCount * game.extraCount)
            #expect(main.missingDrawCount == 0)
            #expect(extra.missingDrawCount == 0)
            #expect(main.rows.allSatisfy { (0...1).contains($0.share) })
        }
    }
}
