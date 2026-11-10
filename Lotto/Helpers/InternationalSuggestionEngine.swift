import Foundation
import SwiftData

enum InternationalSuggestionMode: String, CaseIterable, Identifiable {
    case history, mixed, random
    var id: String { rawValue }
    var title: String {
        switch self {
        case .history: return "Historikk"
        case .mixed: return "Blandet"
        case .random: return "Tilfeldig"
        }
    }
    var description: String {
        switch self {
        case .history: return "Legger mest vekt på historiske intervaller og samme ukenummer i tidligere år."
        case .mixed: return "Blander historiske mønstre med et større innslag av tilfeldighet."
        case .random: return "Trekker alle tall med lik vekt, uten å bruke historikken."
        }
    }
}

struct InternationalSuggestedRow: Identifiable, Equatable {
    let mainNumbers: [Int]
    let extraNumbers: [Int]
    var id: String { "\(mainNumbers)|\(extraNumbers)" }
    var text: String {
        mainNumbers.map(String.init).joined(separator: " – ") + "  +  " + extraNumbers.map(String.init).joined(separator: " – ")
    }
}

struct InternationalSuggestionBatch {
    let date: Date
    let mode: InternationalSuggestionMode
    let rows: [InternationalSuggestedRow]
    let mainCandidates: [Int]
    let extraCandidates: [Int]
    let historyDrawCount: Int
    let sameWeekDrawCount: Int
}

enum InternationalSuggestionEngine {
    static func makeRows(game: InternationalGame, date: Date, records: [InternationalLotteryRecord],
                         mode: InternationalSuggestionMode = .mixed, count: Int = 5,
                         toleranceDays: Double = 3, excludeHighestGap: Bool = false,
                         asOf: Date = .now, favorites: LotteryFavoriteSelection = LotteryFavoriteSelection()) -> InternationalSuggestionBatch {
        var generator = SystemRandomNumberGenerator()
        return makeRows(game: game, date: date, records: records, mode: mode, count: count,
                        toleranceDays: toleranceDays, excludeHighestGap: excludeHighestGap,
                        asOf: asOf, favorites: favorites, using: &generator)
    }

    static func makeRows<R: RandomNumberGenerator>(game: InternationalGame, date: Date,
                         records: [InternationalLotteryRecord], mode: InternationalSuggestionMode = .mixed,
                         count: Int = 5, toleranceDays: Double = 3, excludeHighestGap: Bool = false,
                         asOf: Date = .now, favorites: LotteryFavoriteSelection = LotteryFavoriteSelection(), using generator: inout R) -> InternationalSuggestionBatch {
        let target = game.nextDraw(onOrAfter: date)
        // Historical inspection must not use the target draw or any later result.
        let cutoff = min(LotteryCalendar.day(asOf), LotteryCalendar.calendar.date(byAdding: .day, value: -1, to: target)!)
        let main = InternationalLotteryStatistics.report(records: records, game: game, extraPool: false,
                                                          excludeHighestGap: excludeHighestGap, asOf: cutoff)
        let extra = InternationalLotteryStatistics.report(records: records, game: game, extraPool: true,
                                                           excludeHighestGap: excludeHighestGap, asOf: cutoff)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = LotteryCalendar.calendar.timeZone
        let week = iso.component(.weekOfYear, from: target)
        let year = iso.component(.yearForWeekOfYear, from: target)
        let sameWeek = records.filter {
            iso.component(.weekOfYear, from: $0.date) == week && iso.component(.yearForWeekOfYear, from: $0.date) < year
        }
        let mainWeek = InternationalLotteryStatistics.report(records: sameWeek, game: game, extraPool: false, asOf: cutoff)
        let extraWeek = InternationalLotteryStatistics.report(records: sameWeek, game: game, extraPool: true, asOf: cutoff)
        let tolerance = toleranceDays.isFinite ? min(30, max(0, toleranceDays)) : 3
        let mainCandidates = candidates(main.rows, target: target, tolerance: tolerance)
        let extraCandidates = candidates(extra.rows, target: target, tolerance: tolerance)
        let mainWeights = weights(main.rows, sameWeek: mainWeek.rows, candidates: Set(mainCandidates), mode: mode)
        let extraWeights = weights(extra.rows, sameWeek: extraWeek.rows, candidates: Set(extraCandidates), mode: mode)
        let reportGame = LotteryReportGame(rawValue: game.rawValue)!
        let locked = favorites.effective(for: reportGame)
        let wanted = min(20, max(0, count), locked.combinations(for: reportGame))
        var seen = Set<String>()
        var rows: [InternationalSuggestedRow] = []
        for _ in 0..<(wanted * 50) {
            guard rows.count < wanted else { break }
            let row = InternationalSuggestedRow(
                mainNumbers: (locked.mainNumbers + sample(mainWeights.filter { !locked.mainNumbers.contains($0.number) }, count: game.mainCount - locked.mainNumbers.count, using: &generator)).sorted(),
                extraNumbers: (locked.extraNumbers + sample(extraWeights.filter { !locked.extraNumbers.contains($0.number) }, count: game.extraCount - locked.extraNumbers.count, using: &generator)).sorted()
            )
            if seen.insert(row.id).inserted { rows.append(row) }
        }
        if rows.count < wanted {
            for values in locked.completions(for: reportGame, limit: wanted) {
                let row = InternationalSuggestedRow(mainNumbers: values.main, extraNumbers: values.extra)
                if seen.insert(row.id).inserted { rows.append(row) }
                if rows.count == wanted { break }
            }
        }
        return InternationalSuggestionBatch(date: target, mode: mode, rows: rows,
            mainCandidates: mode == .random ? [] : mainCandidates,
            extraCandidates: mode == .random ? [] : extraCandidates,
            historyDrawCount: main.drawCount, sameWeekDrawCount: mainWeek.drawCount)
    }

    private static func candidates(_ rows: [LotteryNumberStatistics], target: Date, tolerance: Double) -> [Int] {
        rows.compactMap { row in
            guard let last = row.lastDate, let interval = row.averageDays, interval > 0 else { return nil }
            let days = Double(LotteryCalendar.calendar.dateComponents([.day], from: last, to: target).day!)
            let cycles = max(1, (days / interval).rounded())
            return abs(days - cycles * interval) <= tolerance ? row.number : nil
        }
    }

    private static func weights(_ rows: [LotteryNumberStatistics], sameWeek: [LotteryNumberStatistics],
                                candidates: Set<Int>, mode: InternationalSuggestionMode) -> [(number: Int, weight: Double)] {
        let largest = max(1, rows.map(\.count).max() ?? 0)
        let largestWeek = max(1, sameWeek.map(\.count).max() ?? 0)
        let weekCounts = Dictionary(uniqueKeysWithValues: sameWeek.map { ($0.number, $0.count) })
        return rows.map { row in
            guard mode != .random else { return (row.number, 1) }
            let frequency = Double(row.count) / Double(largest)
            let week = Double(weekCounts[row.number] ?? 0) / Double(largestWeek)
            let candidate = candidates.contains(row.number) ? 1.0 : 0.0
            let weight = mode == .history ? 1 + 4 * candidate + 2 * frequency + 3 * week
                                         : 1 + 1.5 * candidate + frequency + week
            return (row.number, weight)
        }
    }

    private static func sample<R: RandomNumberGenerator>(_ weights: [(number: Int, weight: Double)],
                                                         count: Int, using generator: inout R) -> [Int] {
        var remaining = weights
        var numbers: [Int] = []
        for _ in 0..<count {
            let total = remaining.reduce(0) { $0 + $1.weight }
            let ticket = Double.random(in: 0..<total, using: &generator)
            var cumulative = 0.0
            var chosen = remaining.count - 1
            for index in remaining.indices {
                cumulative += remaining[index].weight
                if ticket < cumulative { chosen = index; break }
            }
            numbers.append(remaining.remove(at: chosen).number)
        }
        return numbers.sorted()
    }
}

@MainActor
enum InternationalSuggestedRowSaver {
    static func save(_ rows: [InternationalSuggestedRow], game: InternationalGame,
                     date: Date, context: ModelContext) throws -> Int {
        let day = LotteryCalendar.day(date)
        // Validate the entire selection before changing the database.
        for row in rows {
            if game.validation(main: row.mainNumbers, extra: row.extraNumbers, date: day) != nil {
                throw InternationalLotteryError.invalidDraw(LotteryCalendar.text(day))
            }
        }
        let existing = try context.fetch(FetchDescriptor<InternationalLotteryEntry>()).filter {
            !$0.isDraw && $0.gameID == game.rawValue && LotteryCalendar.day($0.date) == day
        }
        var known = Set(existing.map { InternationalSuggestedRow(mainNumbers: $0.mainNumbers.sorted(), extraNumbers: $0.extraNumbers.sorted()).id })
        var added = 0
        for row in rows {
            let normalized = InternationalSuggestedRow(mainNumbers: row.mainNumbers.sorted(), extraNumbers: row.extraNumbers.sorted())
            if known.insert(normalized.id).inserted {
                context.insert(InternationalLotteryEntry(game: game, isDraw: false, date: day,
                                                        main: normalized.mainNumbers, extra: normalized.extraNumbers))
                added += 1
            }
        }
        do { if added > 0 { try context.save() } }
        catch { context.rollback(); throw error }
        return added
    }
}
