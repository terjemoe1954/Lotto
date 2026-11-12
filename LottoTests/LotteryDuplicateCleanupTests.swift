import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor struct LotteryDuplicateCleanupTests {
    private func store() throws -> ModelContainer {
        try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
    private var settings: LottoBackupSettings { LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false) }
    private func lotto(_ date: String, numbers: [Int] = [1,2,3,4,5,6,7], seconds: TimeInterval = 0) -> Result {
        Result(dato: LotteryCalendar.date(date)!.addingTimeInterval(seconds), nr1: numbers[0], nr2: numbers[1], nr3: numbers[2], nr4: numbers[3], nr5: numbers[4], nr6: numbers[5], nr7: numbers[6], weekNr: 45)
    }
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    @Test func keepsOneOriginalCopyAndPreservesDatesGamesAndExtraPools() throws {
        let container = try store(), context = container.mainContext
        let original = lotto("2026-11-07")
        context.insert(original)
        context.insert(lotto("2026-11-07", numbers: [7,6,5,4,3,2,1], seconds: 3600))
        context.insert(lotto("2026-11-14"))
        context.insert(lotto("2025-11-08")) // Same ISO week in a different year.
        let main = [1,2,3,4,5,6]
        for _ in 0..<2 { context.insert(InternationalLotteryEntry(game: .vikinglotto, isDraw: false, date: LotteryCalendar.date("2026-11-04")!, main: main, extra: [1])) }
        context.insert(InternationalLotteryEntry(game: .vikinglotto, isDraw: false, date: LotteryCalendar.date("2026-11-04")!, main: main, extra: [2]))
        // Draws with identical numbers must never be included in this own-row cleanup.
        for _ in 0..<2 { context.insert(InternationalLotteryEntry(game: .vikinglotto, isDraw: true, date: LotteryCalendar.date("2026-11-04")!, main: main, extra: [1])) }
        for day in ["2026-11-03","2026-11-06"] {
            context.insert(InternationalLotteryEntry(game: .eurojackpot, isDraw: false, date: LotteryCalendar.date(day)!, main: [1,2,3,4,5], extra: [1,3]))
        }
        context.insert(InternationalLotteryEntry(game: .eurojackpot, isDraw: false, date: LotteryCalendar.date("2026-11-03")!, main: [5,4,3,2,1], extra: [3,1]))
        context.insert(InternationalLotteryEntry(game: .eurojackpot, isDraw: false, date: LotteryCalendar.date("2026-11-03")!, main: [1,2,3,4,5], extra: [1,4]))
        try context.save()
        let originalID = original.persistentModelID
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let result = try LotteryDuplicateCleanup.clean(context: context, settings: settings, backupDirectory: directory)
        #expect(result.removed == .init(lotto: 1, vikinglotto: 1, eurojackpot: 1))
        let remaining = try context.fetch(FetchDescriptor<Result>())
        #expect(remaining.count == 3)
        #expect(remaining.contains { $0.persistentModelID == originalID && $0.dato == LotteryCalendar.date("2026-11-07")! && $0.nr1 == 1 && $0.nr7 == 7 })
        let international = try context.fetch(FetchDescriptor<InternationalLotteryEntry>())
        #expect(international.filter(\.isDraw).count == 2)
        #expect(international.filter { !$0.isDraw && $0.gameID == "eurojackpot" }.count == 3)
        #expect(try LotteryDuplicateCleanup.plan(context: context).counts.total == 0)
    }

    @Test func backupContainsOriginalDuplicatesAndLedgerWhileRegnskapStaysUnchanged() throws {
        let container = try store(), context = container.mainContext
        context.insert(lotto("2026-11-07")); context.insert(lotto("2026-11-07"))
        let key = WeeklyLotteryReport.rows(lotto: try context.fetch(FetchDescriptor<Result>()), international: [])[0].id
        context.insert(LotteryDeliveryChange(rowKey: key, registered: true))
        let manual = LotteryLedgerRecord(id: "actual", gameID: "lotto", date: LotteryCalendar.date("2026-11-07")!, stakeOre: 10000, prizeOre: 5000, note: "Behold")
        context.insert(LotteryLedgerEntry(record: manual))
        try context.save()
        let marksBefore = try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        let before = AutomaticLotteryLedger.items(rows: AutomaticLotteryLedger.deliveredRows(marksBefore), tables: []).map(\.record)
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let result = try LotteryDuplicateCleanup.clean(context: context, settings: settings, backupDirectory: directory)
        let file = try #require(result.backupURL)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LottoBackupSnapshot.self, from: Data(contentsOf: file))
        #expect(backup.content == .everything)
        #expect(backup.results.count == 2)
        #expect(backup.ledger == [manual])
        #expect(try LottoBackupStore.check(backup).lottoRows == 1)
        let marksAfter = try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        #expect(marksBefore == marksAfter)
        #expect(try context.fetch(FetchDescriptor<LotteryLedgerEntry>()).map(\.record) == [manual])
        #expect(AutomaticLotteryLedger.items(rows: AutomaticLotteryLedger.deliveredRows(marksAfter), tables: []).map(\.record) == before)
        let fileBytes = try Data(contentsOf: file)
        let repeated = try LotteryDuplicateCleanup.clean(context: context, settings: settings, backupDirectory: directory)
        #expect(repeated.removed.total == 0 && repeated.backupURL == nil)
        #expect(try Data(contentsOf: file) == fileBytes)
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count == 1)
    }

    @Test func failedBackupCannotDeleteAnything() throws {
        let container = try store(), context = container.mainContext
        context.insert(lotto("2026-11-07")); context.insert(lotto("2026-11-07")); try context.save()
        let occupied = folder(); try Data("occupied".utf8).write(to: occupied)
        defer { try? FileManager.default.removeItem(at: occupied) }
        #expect(throws: (any Error).self) { try LotteryDuplicateCleanup.clean(context: context, settings: settings, backupDirectory: occupied) }
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 2)
        #expect(!context.hasChanges)
    }

    @Test func refusesPendingUserEditsAndDoesNotSanitizeDifferentInvalidRows() throws {
        let container = try store(), context = container.mainContext
        context.insert(lotto("2026-11-07"))
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: (any Error).self) { try LotteryDuplicateCleanup.clean(context: context, settings: settings, backupDirectory: directory) }
        #expect(context.hasChanges)
        try context.save()
        context.insert(lotto("2026-11-07", numbers: [1,2,3,4,5,6,128]))
        context.insert(lotto("2026-11-07", numbers: [1,2,3,4,5,6,129]))
        try context.save()
        #expect(try LotteryDuplicateCleanup.plan(context: context).counts.total == 0)
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 3)
    }
}
