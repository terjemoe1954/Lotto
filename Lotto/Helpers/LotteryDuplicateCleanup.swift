import Foundation
import SwiftData

@MainActor enum LotteryDuplicateCleanup {
    struct Counts: Equatable {
        var lotto = 0
        var vikinglotto = 0
        var eurojackpot = 0
        var total: Int { lotto + vikinglotto + eurojackpot }
        var text: String { "Lotto: \(lotto) · Vikinglotto: \(vikinglotto) · Eurojackpot: \(eurojackpot)" }
    }
    struct Plan {
        let lotto: [Result]
        let international: [InternationalLotteryEntry]
        var counts: Counts {
            Counts(lotto: lotto.count,
                   vikinglotto: international.filter { $0.gameID == "vikinglotto" }.count,
                   eurojackpot: international.filter { $0.gameID == "eurojackpot" }.count)
        }
    }
    struct Outcome {
        let removed: Counts
        let backupURL: URL?
    }
    private struct Key: Hashable {
        let game: String
        let day: Date
        let main: [Int]
        let extra: [Int]
        init(game: String, date: Date, main: [Int], extra: [Int] = []) {
            self.game = game; day = LotteryCalendar.day(date)
            self.main = main.sorted(); self.extra = extra.sorted()
        }
    }
    static func plan(context: ModelContext) throws -> Plan {
        let rows = try context.fetch(FetchDescriptor<Result>()).sorted {
            if $0.dato != $1.dato { return $0.dato < $1.dato }
            return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
        }
        let international = try context.fetch(FetchDescriptor<InternationalLotteryEntry>()).filter {
            !$0.isDraw && InternationalGame(rawValue: $0.gameID) != nil
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
        }
        var seen = Set<Key>()
        let extraLotto = rows.filter { row in
            !seen.insert(Key(game: "lotto", date: row.dato,
                             main: [row.nr1,row.nr2,row.nr3,row.nr4,row.nr5,row.nr6,row.nr7])).inserted
        }
        let extraInternational = international.filter { row in
            !seen.insert(Key(game: row.gameID, date: row.date, main: row.mainNumbers, extra: row.extraNumbers)).inserted
        }
        return Plan(lotto: extraLotto, international: extraInternational)
    }

    /// Invoke on one device, then allow its CloudKit deletions to propagate before another cleanup.
    /// No batch SQL delete: individual ModelContext deletions preserve CloudKit's change tracking.
    static func clean(context: ModelContext, settings: LottoBackupSettings,
                      backupDirectory: URL = URL.documentsDirectory.appendingPathComponent("Lotto-backups", isDirectory: true)) throws -> Outcome {
        guard !context.hasChanges else {
            throw LottoBackupValidationError.invalid("Vent til andre endringer er lagret før oppryddingen.")
        }
        let plan = try plan(context: context)
        guard plan.counts.total > 0 else { return Outcome(removed: plan.counts, backupURL: nil) }

        // Everything through the final save is synchronous on MainActor: the backup and plan
        // describe the same local state. Existing rows and delivery/favorite/ledger events stay intact.
        let snapshot = try LottoBackupStore.snapshot(context: context, content: .everything, settings: settings)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(snapshot)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        _ = try LottoBackupStore.check(decoder.decode(LottoBackupSnapshot.self, from: bytes))
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let file = backupDirectory.appendingPathComponent("Lotto-for-dublettrydding-\(UUID().uuidString).json")
        try bytes.write(to: file, options: .atomic)
        guard try Data(contentsOf: file) == bytes else { throw CocoaError(.fileReadCorruptFile) }

        do {
            for row in plan.lotto { context.delete(row) }
            for row in plan.international { context.delete(row) }
            try context.save()
        } catch { context.rollback(); throw error }
        return Outcome(removed: plan.counts, backupURL: file)
    }
}
