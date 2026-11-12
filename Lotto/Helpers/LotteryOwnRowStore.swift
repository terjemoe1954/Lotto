import Foundation
import SwiftData

/// A fresh context fetch immediately before insertion also sees unsaved inserts.
/// CloudKit does not support SwiftData uniqueness constraints: this guards local
/// saves, not two devices saving the same row while unaware of each other offline.
@MainActor enum LotteryOwnRowStore {
    struct Key: Hashable {
        let game: String
        let date: Date
        let main: [Int]
        let extra: [Int]
        init(game: String, date: Date, main: [Int], extra: [Int] = []) {
            self.game = game; self.date = LotteryCalendar.day(date)
            self.main = main.sorted(); self.extra = extra.sorted()
        }
        init(_ row: Result) {
            self.init(game: "lotto", date: row.dato,
                      main: [row.nr1,row.nr2,row.nr3,row.nr4,row.nr5,row.nr6,row.nr7])
        }
        init(_ row: InternationalLotteryEntry) {
            self.init(game: row.gameID, date: row.date, main: row.mainNumbers, extra: row.extraNumbers)
        }
    }
    enum SaveError: LocalizedError {
        case duplicate
        var errorDescription: String? { "Denne rekken er allerede lagret for denne trekningen." }
    }
    static func insert(_ row: Result, context: ModelContext) throws {
        let key = Key(row)
        guard try !context.fetch(FetchDescriptor<Result>()).contains(where: { Key($0) == key }) else {
            throw SaveError.duplicate
        }
        context.insert(row)
    }
    static func insert(_ row: InternationalLotteryEntry, context: ModelContext) throws {
        if !row.isDraw {
            let key = Key(row)
            guard try !context.fetch(FetchDescriptor<InternationalLotteryEntry>()).contains(where: { !$0.isDraw && Key($0) == key }) else {
                throw SaveError.duplicate
            }
        }
        context.insert(row)
    }
    /// Restoring an old backup must not reintroduce its extra own-row copies.
    /// Retain the first complete original record, without touching draws or marks.
    static func uniqueOwnRows(in source: LottoBackupSnapshot) -> LottoBackupSnapshot {
        var copy = source
        var seen = Set<Key>()
        copy.results = source.results.filter { seen.insert(Key($0.makeModel())).inserted }
        copy.internationalEntries = source.internationalEntries.map { entries in
            entries.filter { row in
                row.isDraw || seen.insert(Key(game: row.gameID, date: row.date, main: row.mainNumbers, extra: row.extraNumbers)).inserted
            }
        }
        return copy
    }
}
