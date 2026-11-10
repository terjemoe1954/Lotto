import Foundation

enum LotteryReportGame: String, CaseIterable, Identifiable {
    case lotto, vikinglotto, eurojackpot
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lotto: return "Lotto"
        case .vikinglotto: return "Vikinglotto"
        case .eurojackpot: return "Eurojackpot"
        }
    }
    var position: Int { Self.allCases.firstIndex(of: self)! }
}

struct LotteryReportWeek: Hashable {
    let year: Int
    let number: Int
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }
    init(year: Int, number: Int) { self.year = year; self.number = number }
    init(date: Date) {
        year = Self.calendar.component(.yearForWeekOfYear, from: date)
        number = Self.calendar.component(.weekOfYear, from: date)
    }
    static func weeks(in year: Int) -> Int {
        let date = calendar.date(from: DateComponents(year: year, month: 12, day: 28))!
        return calendar.component(.weekOfYear, from: date)
    }
    var start: Date {
        Self.calendar.date(from: DateComponents(weekday: 2, weekOfYear: number, yearForWeekOfYear: year))!
    }
    var end: Date { Self.calendar.date(byAdding: .day, value: 6, to: start)! }
    var title: String { "Uke \(number), \(year)" }
    var dateRange: String { "\(WeeklyLotteryReport.dateText(start)) - \(WeeklyLotteryReport.dateText(end))" }
    var filename: String { String(format: "Lottorekker-%04d-uke-%02d", year, number) }
}

struct LotteryReportRow: Identifiable, Equatable {
    let game: LotteryReportGame
    let date: Date
    let mainNumbers: [Int]
    let extraNumbers: [Int]
    var isRegistered = false
    var legacyDeliveryKey: String? = nil
    var week: LotteryReportWeek { LotteryReportWeek(date: date) }
    var id: String { "\(game.rawValue)|\(LotteryCalendar.text(date))|\(mainNumbers.sorted())|\(extraNumbers.sorted())" }
    var mainText: String { mainNumbers.sorted().map { String(format: "%02d", $0) }.joined(separator: "  ") }
    var extraText: String { extraNumbers.sorted().map { String(format: "%02d", $0) }.joined(separator: "  ") }
}

enum WeeklyLotteryReport {
    static let rowsPerPage = 26
    static func dateText(_ date: Date) -> String {
        let c = LotteryReportWeek.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", c.day!, c.month!, c.year!)
    }
    static func rows(lotto: [Result], international: [InternationalLotteryEntry]) -> [LotteryReportRow] {
        let national = lotto.map {
            LotteryReportRow(game: .lotto, date: LotteryCalendar.day($0.dato),
                mainNumbers: [$0.nr1,$0.nr2,$0.nr3,$0.nr4,$0.nr5,$0.nr6,$0.nr7].sorted(), extraNumbers: [],
                legacyDeliveryKey: "\(LottoDateSupport.normalize($0.dato).timeIntervalSince1970)-" + [$0.nr1,$0.nr2,$0.nr3,$0.nr4,$0.nr5,$0.nr6,$0.nr7].map(String.init).joined(separator: "-"))
        }
        let other = international.filter { !$0.isDraw }.compactMap { entry -> LotteryReportRow? in
            guard let game = LotteryReportGame(rawValue: entry.gameID), game != .lotto else { return nil }
            return LotteryReportRow(game: game, date: LotteryCalendar.day(entry.date),
                                    mainNumbers: entry.mainNumbers.sorted(), extraNumbers: entry.extraNumbers.sorted())
        }
        return normalized(national + other)
    }
    static func normalized(_ rows: [LotteryReportRow]) -> [LotteryReportRow] {
        var known = Set<String>()
        return rows.sorted {
            if $0.game != $1.game { return $0.game.position < $1.game.position }
            if $0.date != $1.date { return $0.date < $1.date }
            let left = $0.mainNumbers.sorted(), right = $1.mainNumbers.sorted()
            if left != right { return left.lexicographicallyPrecedes(right) }
            return $0.extraNumbers.sorted().lexicographicallyPrecedes($1.extraNumbers.sorted())
        }.filter { known.insert($0.id).inserted }
    }
    static func filtered(_ rows: [LotteryReportRow], week: LotteryReportWeek,
                         games: Set<LotteryReportGame>, selection: Set<String>? = nil) -> [LotteryReportRow] {
        normalized(rows).filter {
            $0.week == week && games.contains($0.game) && (selection == nil || selection!.contains($0.id))
        }
    }
    static func pages(_ rows: [LotteryReportRow]) -> [[LotteryReportRow]] {
        stride(from: 0, to: rows.count, by: rowsPerPage).map {
            Array(rows[$0..<min(rows.count, $0 + rowsPerPage)])
        }
    }
}

/// Stable row keys keep delivery marks separate from the current export selection.
enum WeeklyLotteryDelivery {
    static let storageKey = "weeklyReport.registeredRows"
    static func keys(_ raw: String) -> Set<String> { Set(raw.split(separator: "\n").map(String.init)) }
    static func encoded(_ keys: Set<String>) -> String { keys.sorted().joined(separator: "\n") }
    static func applying(_ rows: [LotteryReportRow], registered: Set<String>, legacy: Set<String>) -> [LotteryReportRow] {
        rows.map { row in
            var copy = row
            copy.isRegistered = registered.contains(row.id) || row.legacyDeliveryKey.map { legacy.contains($0) } == true
            return copy
        }
    }
}
