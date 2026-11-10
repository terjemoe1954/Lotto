import Foundation

enum LotteryStatisticsPeriod: String, CaseIterable, Identifiable {
    case all, thisYear, last12Months, last100Draws
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Hele historikken"
        case .thisYear: return "Inneværende år"
        case .last12Months: return "Siste 12 måneder"
        case .last100Draws: return "Siste 100 trekninger"
        }
    }
}

enum LotteryStatisticsSort: String, CaseIterable, Identifiable {
    case number, mostFrequent, leastFrequent, longestAbsence
    var id: String { rawValue }
    var title: String {
        switch self {
        case .number: return "Tallrekkefølge"
        case .mostFrequent: return "Flest forekomster"
        case .leastFrequent: return "Færrest forekomster"
        case .longestAbsence: return "Lengst siden sist"
        }
    }
}

struct LotteryNumberStatistics: Identifiable {
    let number: Int
    let count: Int
    /// Fraction of selected draws containing this number, rather than fraction of all balls.
    let share: Double
    let lastDate: Date?
    let daysSinceLast: Int?
    /// Actual stored draws after the most recent occurrence in the selected period.
    let drawsSinceLast: Int?
    let averageDays: Double?
    let averageDraws: Double?
    let longestGapDays: Int?
    let longestGapDraws: Int?
    var id: Int { number }
}

struct LotteryStatisticsReport {
    let rows: [LotteryNumberStatistics]
    let drawCount: Int
    let firstDate: Date?
    let lastDate: Date?
    let missingDrawCount: Int

    func sorted(by order: LotteryStatisticsSort) -> [LotteryNumberStatistics] {
        rows.sorted { lhs, rhs in
            switch order {
            case .number: return lhs.number < rhs.number
            case .mostFrequent:
                return lhs.count == rhs.count ? lhs.number < rhs.number : lhs.count > rhs.count
            case .leastFrequent:
                return lhs.count == rhs.count ? lhs.number < rhs.number : lhs.count < rhs.count
            case .longestAbsence:
                // Never observed in this period comes first, without inventing a last date.
                let left = lhs.drawsSinceLast ?? Int.max
                let right = rhs.drawsSinceLast ?? Int.max
                return left == right ? lhs.number < rhs.number : left > right
            }
        }
    }
}

/// Descriptive statistics; no assumption that a number is "due" to be drawn.
enum InternationalLotteryStatistics {
    static func report(records: [InternationalLotteryRecord], game: InternationalGame,
                       extraPool: Bool, period: LotteryStatisticsPeriod = .all,
                       excludeHighestGap: Bool = false, asOf: Date = .now) -> LotteryStatisticsReport {
        let today = LotteryCalendar.day(asOf)
        let calendar = LotteryCalendar.calendar
        var dates = Set<Date>()
        let valid = records.filter {
            $0.isDraw && $0.gameID == game.rawValue && LotteryCalendar.day($0.date) <= today &&
            game.validation(main: $0.mainNumbers, extra: $0.extraNumbers, date: $0.date) == nil
        }.sorted { $0.date < $1.date }
        // Multiple synced copies of a draw must never inflate counts or create zero-day gaps.
        let unique = valid.filter { dates.insert(LotteryCalendar.day($0.date)).inserted }
        let selected: [InternationalLotteryRecord]
        switch period {
        case .all: selected = unique
        case .thisYear:
            let start = calendar.dateInterval(of: .year, for: today)!.start
            selected = unique.filter { $0.date >= start }
        case .last12Months:
            let start = calendar.date(byAdding: .month, value: -12, to: today)!
            selected = unique.filter { $0.date >= start }
        case .last100Draws: selected = Array(unique.suffix(100))
        }
        let maximum = extraPool ? game.extraMaximum : game.mainMaximum
        let rows = (1...maximum).map { number -> LotteryNumberStatistics in
            let occurrences = selected.enumerated().filter {
                (extraPool ? $0.element.extraNumbers : $0.element.mainNumbers).contains(number)
            }
            let last = occurrences.last
            let lastDate = last.map { LotteryCalendar.day($0.element.date) }
            let gaps: [(days: Int, draws: Int)] = zip(occurrences, occurrences.dropFirst()).map { previous, next in
                let days = calendar.dateComponents([.day], from: LotteryCalendar.day(previous.element.date),
                                                   to: LotteryCalendar.day(next.element.date)).day!
                return (days, next.offset - previous.offset)
            }
            var averageGaps = gaps
            if excludeHighestGap && gaps.count > 1,
               let index = gaps.indices.max(by: { gaps[$0].days < gaps[$1].days }) {
                averageGaps.remove(at: index)
            }
            let averageDays = averageGaps.isEmpty ? nil : Double(averageGaps.reduce(0) { $0 + $1.days }) / Double(averageGaps.count)
            let averageDraws = averageGaps.isEmpty ? nil : Double(averageGaps.reduce(0) { $0 + $1.draws }) / Double(averageGaps.count)
            return LotteryNumberStatistics(
                number: number, count: occurrences.count,
                share: selected.isEmpty ? 0 : Double(occurrences.count) / Double(selected.count),
                lastDate: lastDate,
                daysSinceLast: lastDate.flatMap { calendar.dateComponents([.day], from: $0, to: today).day },
                drawsSinceLast: last.map { selected.count - 1 - $0.offset },
                averageDays: averageDays, averageDraws: averageDraws,
                longestGapDays: gaps.map(\.days).max(), longestGapDraws: gaps.map(\.draws).max()
            )
        }
        let firstDate = selected.first.map { LotteryCalendar.day($0.date) }
        let lastDate = selected.last.map { LotteryCalendar.day($0.date) }
        var scheduled = 0
        if let firstDate, let lastDate {
            var date = firstDate
            while date <= lastDate {
                if game.weekdays.contains(calendar.component(.weekday, from: date)) { scheduled += 1 }
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
        }
        return LotteryStatisticsReport(rows: rows, drawCount: selected.count,
                                       firstDate: firstDate, lastDate: lastDate,
                                       missingDrawCount: max(0, scheduled - selected.count))
    }
}
