import Foundation
import SwiftData

extension LotteryReportGame {
    var mainCount: Int { self == .lotto ? 7 : self == .vikinglotto ? 6 : 5 }
    var mainMaximum: Int { self == .lotto ? 34 : self == .vikinglotto ? 48 : 50 }
    var extraCount: Int { self == .lotto ? 0 : self == .vikinglotto ? 1 : 2 }
    var extraMaximum: Int { self == .lotto ? 0 : self == .vikinglotto ? 5 : 12 }
    var extraTitle: String { self == .vikinglotto ? "Vikingtall" : "Stjernetall" }
}

nonisolated struct LotteryFavoriteSelection: Equatable, Codable {
    var mainNumbers: [Int] = []
    var extraNumbers: [Int] = []
    var enabled = true
    @MainActor func effective(for game: LotteryReportGame) -> LotteryFavoriteSelection {
        guard enabled else { return LotteryFavoriteSelection() }
        return LotteryFavoriteSelection(
            mainNumbers: Array(Set(mainNumbers.filter { (1...game.mainMaximum).contains($0) })).sorted().prefixArray(game.mainCount),
            extraNumbers: Array(Set(extraNumbers.filter { $0 >= 1 && $0 <= game.extraMaximum })).sorted().prefixArray(game.extraCount))
    }
    @MainActor func validation(for game: LotteryReportGame) -> String? {
        if mainNumbers.count > game.mainCount || Set(mainNumbers).count != mainNumbers.count ||
            mainNumbers.contains(where: { $0 < 1 || $0 > game.mainMaximum }) {
            return "Velg høyst \(game.mainCount) ulike hovedtall mellom 1 og \(game.mainMaximum)."
        }
        if extraNumbers.count > game.extraCount || Set(extraNumbers).count != extraNumbers.count ||
            extraNumbers.contains(where: { $0 < 1 || $0 > game.extraMaximum }) {
            return game == .lotto ? "Lotto har ikke egne favoritter for tilleggstall." : "Velg høyst \(game.extraCount) ulike \(game.extraTitle.lowercased()) mellom 1 og \(game.extraMaximum)."
        }
        return nil
    }
    @MainActor func combinations(for game: LotteryReportGame) -> Int {
        let active = effective(for: game)
        return Self.choose(game.mainMaximum - active.mainNumbers.count, game.mainCount - active.mainNumbers.count) *
            Self.choose(game.extraMaximum - active.extraNumbers.count, game.extraCount - active.extraNumbers.count)
    }
    private static func choose(_ n: Int, _ k: Int) -> Int {
        guard k >= 0, n >= k else { return 0 }
        guard k > 0 else { return 1 }
        let r = min(k, n-k)
        guard r > 0 else { return 1 }
        return (1...r).reduce(1) { value, i in value * (n - r + i) / i }
    }
}
private extension Array { func prefixArray(_ count: Int) -> [Element] { Array(prefix(count)) } }

@Model
final class LotteryFavoriteChange {
    var gameID: String = ""
    var mainNumbers: [Int] = []
    var extraNumbers: [Int] = []
    var enabled: Bool = true
    var changedAt: Date = Date()
    var changeID: String = UUID().uuidString
    init(record: LotteryFavoriteRecord) {
        gameID = record.gameID; mainNumbers = record.mainNumbers; extraNumbers = record.extraNumbers
        enabled = record.enabled; changedAt = record.changedAt; changeID = record.changeID
    }
    var record: LotteryFavoriteRecord {
        LotteryFavoriteRecord(gameID: gameID, mainNumbers: mainNumbers, extraNumbers: extraNumbers,
                              enabled: enabled, changedAt: changedAt, changeID: changeID)
    }
}
nonisolated struct LotteryFavoriteRecord: Codable, Equatable, Sendable {
    var gameID: String
    var mainNumbers: [Int]
    var extraNumbers: [Int]
    var enabled: Bool
    var changedAt: Date
    var changeID: String
    var selection: LotteryFavoriteSelection { LotteryFavoriteSelection(mainNumbers: mainNumbers, extraNumbers: extraNumbers, enabled: enabled) }
}

@MainActor
enum LotteryFavorites {
    static func latest(_ records: [LotteryFavoriteRecord]) -> [String: LotteryFavoriteRecord] {
        records.reduce(into: [:]) { state, record in
            guard LotteryReportGame(rawValue: record.gameID) != nil else { return }
            if let previous = state[record.gameID], previous.changedAt > record.changedAt ||
                (previous.changedAt == record.changedAt && previous.changeID >= record.changeID) { return }
            state[record.gameID] = record
        }
    }
    static func selection(for game: LotteryReportGame, records: [LotteryFavoriteRecord]) -> LotteryFavoriteSelection {
        latest(records)[game.rawValue]?.selection ?? LotteryFavoriteSelection()
    }
    static func save(_ values: [LotteryReportGame: LotteryFavoriteSelection], context: ModelContext, now: Date = .now, saveImmediately: Bool = true) throws {
        for (game, value) in values {
            if let error = value.validation(for: game) { throw LottoBackupValidationError.invalid(error) }
        }
        let existing = latest(try context.fetch(FetchDescriptor<LotteryFavoriteChange>()).map(\.record))
        for (game, raw) in values {
            var value = raw
            value.mainNumbers.sort(); value.extraNumbers.sort()
            if existing[game.rawValue]?.selection == value { continue }
            let time = max(now, (existing[game.rawValue]?.changedAt ?? .distantPast).addingTimeInterval(0.001))
            context.insert(LotteryFavoriteChange(record: LotteryFavoriteRecord(gameID: game.rawValue,
                mainNumbers: value.mainNumbers, extraNumbers: value.extraNumbers, enabled: value.enabled,
                changedAt: time, changeID: UUID().uuidString)))
        }
        if saveImmediately {
            do { try context.save() } catch { context.rollback(); throw error }
        }
    }
    static func restore(_ records: [LotteryFavoriteRecord], context: ModelContext) throws {
        var values = Dictionary(uniqueKeysWithValues: LotteryReportGame.allCases.map { ($0, LotteryFavoriteSelection()) })
        for (id, record) in latest(records) {
            if let game = LotteryReportGame(rawValue: id) { values[game] = record.selection }
        }
        try save(values, context: context, saveImmediately: false)
    }
}

extension LotteryFavoriteSelection {
    /// Small bounded fallback ensures skewed weights cannot prevent filling a requested batch.
    @MainActor func completions(for game: LotteryReportGame, limit: Int) -> [(main: [Int], extra: [Int])] {
        let value = effective(for: game)
        let bound = min(500, max(0, limit))
        guard bound > 0 else { return [] }
        func subsets(_ numbers: [Int], take: Int) -> [[Int]] {
            if take == 0 { return [[]] }
            var result: [[Int]] = []
            func visit(_ start: Int, _ picked: [Int]) {
                guard result.count < bound else { return }
                if picked.count == take { result.append(picked); return }
                guard start < numbers.count, numbers.count - start >= take - picked.count else { return }
                for index in start...numbers.count - (take - picked.count) {
                    visit(index + 1, picked + [numbers[index]])
                    if result.count >= bound { break }
                }
            }
            visit(0, [])
            return result
        }
        let main = subsets((1...game.mainMaximum).filter { !value.mainNumbers.contains($0) }, take: game.mainCount - value.mainNumbers.count)
        let extraPool = game.extraMaximum > 0 ? Array(1...game.extraMaximum) : []
        let extra = subsets(extraPool.filter { !value.extraNumbers.contains($0) }, take: game.extraCount - value.extraNumbers.count)
        var result: [(main: [Int], extra: [Int])] = []
        for m in main {
            for e in extra {
                result.append(((value.mainNumbers + m).sorted(), (value.extraNumbers + e).sorted()))
                if result.count >= bound { return result }
            }
        }
        return result
    }
}
