import Foundation
import SwiftData

/// One index per render. Never rebuild the archive inside a row filter or sort.
@MainActor struct InternationalHomeSnapshot {
    struct Match {
        let main: Int
        let extra: Int
        let prize: Bool
    }
    let draws: [InternationalLotteryEntry]
    let rows: [InternationalLotteryEntry]
    let dates: [Date]
    let activeDate: Date?
    let selectedRows: [InternationalLotteryEntry]
    let matches: [PersistentIdentifier: Match]
    init(entries: [InternationalLotteryEntry], game: InternationalGame, selectedDate: Date?) {
        var drawIndex: [Date: InternationalLotteryEntry] = [:]
        var own: [InternationalLotteryEntry] = []
        var dates = Set<Date>()
        for entry in entries where entry.gameID == game.rawValue {
            let day = LotteryCalendar.day(entry.date)
            dates.insert(day)
            if entry.isDraw {
                if drawIndex[day] == nil { drawIndex[day] = entry }
            } else { own.append(entry) }
        }
        self.draws = drawIndex.keys.sorted(by: >).compactMap { drawIndex[$0] }
        self.rows = own
        self.dates = dates.sorted(by: >)
        let day = selectedDate.map { LotteryCalendar.day($0) } ?? self.draws.first.map { LotteryCalendar.day($0.date) } ?? self.dates.first
        self.activeDate = day
        let selected = own.filter { LotteryCalendar.day($0.date) == day }
        var matches: [PersistentIdentifier: Match] = [:]
        if let day, let draw = drawIndex[day], let reportGame = LotteryReportGame(rawValue: game.rawValue) {
            let main = Set(draw.mainNumbers), extra = Set(draw.extraNumbers)
            for row in selected {
                let m = Set(row.mainNumbers).intersection(main).count
                let e = Set(row.extraNumbers).intersection(extra).count
                matches[row.persistentModelID] = Match(main: m, extra: e,
                    prize: LotteryPrizeRules.qualifies(game: reportGame, main: m, extra: e, date: row.date))
            }
        }
        self.matches = matches
        self.selectedRows = selected.sorted {
            let a = matches[$0.persistentModelID], b = matches[$1.persistentModelID]
            if (a?.main ?? -1) != (b?.main ?? -1) { return (a?.main ?? -1) > (b?.main ?? -1) }
            if (a?.extra ?? -1) != (b?.extra ?? -1) { return (a?.extra ?? -1) > (b?.extra ?? -1) }
            return $0.numbersText < $1.numbersText
        }
    }
}

@MainActor struct LottoHomeSnapshot {
    let draws: [JackPot]
    let dates: [Date]
    let activeDate: Date?
    let selectedRows: [Result]
    let comparisons: [PersistentIdentifier: ResultComparison]
    init(draws: [JackPot], rows: [Result], selectedDate: Date?) {
        var index: [Date: JackPot] = [:]
        var dates = Set<Date>()
        for draw in draws {
            let day = LotteryCalendar.day(draw.dato)
            dates.insert(day)
            if index[day] == nil { index[day] = draw }
        }
        for row in rows { dates.insert(LotteryCalendar.day(row.dato)) }
        self.draws = index.keys.sorted(by: >).compactMap { index[$0] }
        self.dates = dates.sorted(by: >)
        let day = selectedDate.map { LotteryCalendar.day($0) } ?? self.draws.first.map { LotteryCalendar.day($0.dato) } ?? self.dates.first
        self.activeDate = day
        let selected = rows.filter { LotteryCalendar.day($0.dato) == day }
        var comparisons: [PersistentIdentifier: ResultComparison] = [:]
        if let day, let draw = index[day] {
            let winning = JackpotRow(date: draw.dato, numbers: [draw.nr1,draw.nr2,draw.nr3,draw.nr4,draw.nr5,draw.nr6,draw.nr7], extraNumber: draw.nr8)
            for row in selected {
                comparisons[row.persistentModelID] = LottoWinnerLogic.comparison(
                    for: ResultRow(id: String(describing: row.persistentModelID), date: row.dato,
                                   numbers: [row.nr1,row.nr2,row.nr3,row.nr4,row.nr5,row.nr6,row.nr7]), against: winning)
            }
        }
        self.comparisons = comparisons
        self.selectedRows = selected.sorted {
            let a = comparisons[$0.persistentModelID], b = comparisons[$1.persistentModelID]
            if (a?.matchCount ?? -1) != (b?.matchCount ?? -1) { return (a?.matchCount ?? -1) > (b?.matchCount ?? -1) }
            if (a?.matchedExtraNumber != nil) != (b?.matchedExtraNumber != nil) { return a?.matchedExtraNumber != nil }
            return [ $0.nr1,$0.nr2,$0.nr3,$0.nr4,$0.nr5,$0.nr6,$0.nr7 ].lexicographicallyPrecedes([ $1.nr1,$1.nr2,$1.nr3,$1.nr4,$1.nr5,$1.nr6,$1.nr7 ])
        }
    }
}

@MainActor enum LotteryArchivePreparation {
    static func prepare(context: ModelContext) throws {
        guard let url = Bundle.main.url(forResource: "lotto", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let archive = try JSONDecoder().decode([JackPot].self, from: Data(contentsOf: url))
        let existing = try context.fetch(FetchDescriptor<JackPot>())
        let plan = LottoRules.jackpotImportPlan(bundledJackpots: archive, existingJackpots: existing)
        for draw in plan.missing {
            draw.weekNr = LottoDateSupport.weekNumber(for: draw.dato)
            context.insert(draw)
        }
        for duplicate in LottoRules.duplicateJackpots(in: existing) { context.delete(duplicate) }
        try context.save()
        try InternationalLotteryUpdater.seed(context: context)
        if !plan.conflicts.isEmpty {
            throw InternationalLotteryError.conflict(plan.conflicts.map { LotteryCalendar.text($0.dato) }.joined(separator: ", "))
        }
    }
}
