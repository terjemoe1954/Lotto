import Foundation
import SwiftData

/// Full systems are stored as their unique constituent rows. This deliberately
/// reuses delivery marks, backup, CloudKit and per-row prize calculations.
enum LotterySystem {
    static func mainCount(_ game: LotteryReportGame) -> Int { game == .lotto ? 7 : (game == .vikinglotto ? 6 : 5) }
    static func extraCount(_ game: LotteryReportGame) -> Int { game == .lotto ? 0 : (game == .vikinglotto ? 1 : 2) }
    static func combinations(_ values: [Int], choose count: Int) -> [[Int]] {
        guard count >= 0, count <= values.count else { return [] }
        if count == 0 { return [[]] }
        var result: [[Int]] = []
        func visit(_ start: Int, _ selected: [Int]) {
            if selected.count == count { result.append(selected); return }
            let end = values.count - (count - selected.count)
            guard start <= end else { return }
            for i in start...end { visit(i + 1, selected + [values[i]]) }
        }
        visit(0, [])
        return result
    }
    static func rowCount(game: LotteryReportGame, main: Int, extra: Int) -> Int {
        combinations(Array(1...max(1, main)), choose: mainCount(game)).count *
        combinations(extra == 0 ? [] : Array(1...extra), choose: extraCount(game)).count
    }
    static func validation(game: LotteryReportGame, main: [Int], extra: [Int], date: Date) -> String? {
        let minimum = mainCount(game), minimumExtra = extraCount(game)
        let maximumMain = game == .eurojackpot ? 10 : 12
        let maximumExtra = game == .lotto ? 0 : (game == .vikinglotto ? 5 : 12)
        guard (minimum...maximumMain).contains(main.count), (minimumExtra...maximumExtra).contains(extra.count),
              main.count > minimum || extra.count > minimumExtra else { return "Velg flere tall enn i en vanlig rekke, innenfor systemets grenser." }
        guard Set(main).count == main.count, Set(extra).count == extra.count,
              main.allSatisfy({ (1...(game == .lotto ? 34 : (game == .vikinglotto ? 48 : 50))).contains($0) }),
              extra.allSatisfy({ (1...max(1, maximumExtra)).contains($0) }) else { return "Velg ulike og gyldige tall i hver tallgruppe." }
        let weekdays: Set<Int> = game == .lotto ? [7] : (game == .vikinglotto ? [4] : [3,6])
        guard weekdays.contains(LotteryCalendar.calendar.component(.weekday, from: date)) else { return "Velg en gyldig trekningsdato for spillet." }
        guard rowCount(game: game, main: main.count, extra: extra.count) <= 2000 else { return "Denne appen støtter inntil 2000 enkeltrekker per system." }
        return nil
    }
    static func rows(game: LotteryReportGame, main: [Int], extra: [Int], date: Date) -> [LotteryReportRow] {
        guard validation(game: game, main: main, extra: extra, date: date) == nil else { return [] }
        return combinations(main.sorted(), choose: mainCount(game)).flatMap { numbers in
            combinations(extra.sorted(), choose: extraCount(game)).map {
                LotteryReportRow(game: game, date: LotteryCalendar.day(date), mainNumbers: numbers, extraNumbers: $0)
            }
        }
    }
    @MainActor static func save(_ rows: [LotteryReportRow], context: ModelContext) throws -> Int {
        let known = Set(WeeklyLotteryReport.rows(lotto: try context.fetch(FetchDescriptor<Result>()),
                     international: try context.fetch(FetchDescriptor<InternationalLotteryEntry>())).map(\.id))
        let additions = WeeklyLotteryReport.normalized(rows).filter { !known.contains($0.id) }
        do {
            for row in additions {
                if row.game == .lotto {
                    let n = row.mainNumbers
                    context.insert(Result(dato: row.date, nr1: n[0], nr2: n[1], nr3: n[2], nr4: n[3], nr5: n[4], nr6: n[5], nr7: n[6], weekNr: LottoDateSupport.weekNumber(for: row.date)))
                } else if let game = InternationalGame(rawValue: row.game.rawValue) {
                    context.insert(InternationalLotteryEntry(game: game, isDraw: false, date: row.date, main: row.mainNumbers, extra: row.extraNumbers))
                }
            }
            try context.save()
            return additions.count
        } catch { context.rollback(); throw error }
    }
}
