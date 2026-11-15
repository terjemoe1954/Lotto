import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor struct LotteryOwnGamesResetTests {
    private var settings: LottoBackupSettings { .init(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false) }
    private func store() throws -> ModelContainer {
        try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
    private func row() -> Result {
        Result(dato: LotteryCalendar.date("2026-11-07")!, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 5, nr6: 6, nr7: 7, weekNr: 45)
    }
    @Test func backupRestoresResetRowsAndLedgerWhileDrawsSurvive() throws {
        let container = try store(), context = container.mainContext
        context.insert(row())
        context.insert(JackPot(dato: LotteryCalendar.date("2026-11-07")!, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 5, nr6: 6, nr7: 7, nr8: 8))
        let favorite = LotteryFavoriteRecord(gameID: "lotto", mainNumbers: [3,7], extraNumbers: [], enabled: true, changedAt: .now, changeID: "favorite")
        context.insert(LotteryFavoriteChange(record: favorite))
        for game in InternationalGame.allCases {
            context.insert(InternationalLotteryEntry(game: game, isDraw: false, date: LotteryCalendar.date(game == .vikinglotto ? "2026-11-04" : "2026-11-03")!, main: game == .vikinglotto ? [1,2,3,4,5,6] : [1,2,3,4,5], extra: game == .vikinglotto ? [1] : [1,2]))
            context.insert(InternationalLotteryEntry(game: game, isDraw: true, date: LotteryCalendar.date(game == .vikinglotto ? "2026-11-04" : "2026-11-03")!, main: game == .vikinglotto ? [1,2,3,4,5,6] : [1,2,3,4,5], extra: game == .vikinglotto ? [1] : [1,2]))
        }
        context.insert(LotteryLedgerEntry(record: .init(id: "manual", gameID: "lotto", date: .now, stakeOre: 10000, prizeOre: 5000, note: "test")))
        let old = LotteryDeliveryChange(rowKey: "deleted-row", registered: true)
        context.insert(old); try context.save()
        let oldRecord = old.record
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("old", forKey: WeeklyLotteryDelivery.storageKey)
        let prepared = try LotteryOwnGamesReset.prepare(context: context, settings: settings, backupDirectory: directory)
        #expect(prepared.ownRows == 3 && prepared.ledgerEntries == 1)
        // Preparing a backup must never delete data.
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 1)
        try LotteryOwnGamesReset.reset(prepared, context: context, settings: settings, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 0)
        #expect(try context.fetch(FetchDescriptor<InternationalLotteryEntry>()).allSatisfy(\.isDraw))
        #expect(try context.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<LotteryLedgerEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<JackPot>()) == 1)
        #expect(try context.fetch(FetchDescriptor<LotteryFavoriteChange>()).map(\.record) == [favorite])
        let changes = try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        #expect(LotteryDeliverySync.latest(changes + [oldRecord])["deleted-row"]?.registered == false)
        #expect(defaults.string(forKey: WeeklyLotteryDelivery.storageKey) == nil)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LottoBackupSnapshot.self, from: Data(contentsOf: prepared.backupURL))
        try LottoBackupStore.restoreEverything(backup, context: context)
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<LotteryLedgerEntry>()) == 1)
        #expect(LotteryDeliverySync.latest(try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))["deleted-row"]?.registered == true)
    }
    @Test func rejectsChangedStateMissingBackupAndPendingEdits() throws {
        let container = try store(), context = container.mainContext
        context.insert(row()); try context.save()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try LotteryOwnGamesReset.prepare(context: context, settings: settings, backupDirectory: directory)
        context.insert(row())
        #expect(throws: (any Error).self) { try LotteryOwnGamesReset.reset(prepared, context: context, settings: settings) }
        try context.save()
        #expect(throws: (any Error).self) { try LotteryOwnGamesReset.reset(prepared, context: context, settings: settings) }
        let fresh = try LotteryOwnGamesReset.prepare(context: context, settings: settings, backupDirectory: directory)
        try FileManager.default.removeItem(at: fresh.backupURL)
        #expect(throws: (any Error).self) { try LotteryOwnGamesReset.reset(fresh, context: context, settings: settings) }
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 2)
        #expect(!context.hasChanges)
    }
    @Test func failedBackupNeverChangesStore() throws {
        let container = try store(), context = container.mainContext
        context.insert(row()); try context.save()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("occupied".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(throws: (any Error).self) { try LotteryOwnGamesReset.prepare(context: context, settings: settings, backupDirectory: file) }
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 1)
    }
}
