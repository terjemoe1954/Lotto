import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor
struct OfflineBackupIntegrationTests {
    private var settings: LottoBackupSettings {
        LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
    }
    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let config = url.map { ModelConfiguration(url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
                                  configurations: config)
    }
    private func seed(_ context: ModelContext) throws {
        context.insert(JackPot(dato: LotteryCalendar.date("2026-11-07")!, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7,nr8: 8))
        context.insert(Result(dato: LotteryCalendar.date("2026-11-14")!, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7))
        context.insert(InternationalLotteryEntry(game: .vikinglotto, isDraw: true, date: LotteryCalendar.date("2026-11-04")!, main: [1,2,3,4,5,6], extra: [3]))
        context.insert(InternationalLotteryEntry(game: .vikinglotto, isDraw: false, date: LotteryCalendar.date("2026-11-11")!, main: [2,9,17,26,35,44], extra: [3]))
        context.insert(InternationalLotteryEntry(game: .eurojackpot, isDraw: true, date: LotteryCalendar.date("2026-11-06")!, main: [1,2,3,4,5], extra: [1,12]))
        context.insert(InternationalLotteryEntry(game: .eurojackpot, isDraw: false, date: LotteryCalendar.date("2026-11-10")!, main: [6,7,8,9,10], extra: [2,11]))
        try context.save()
        let rows = WeeklyLotteryReport.rows(lotto: try context.fetch(FetchDescriptor<Result>()), international: try context.fetch(FetchDescriptor<InternationalLotteryEntry>()))
        try LotteryDeliverySync.set(true, keys: Set(rows.filter { $0.game != .eurojackpot }.map(\.id)), context: context)
        try LotteryDeliverySync.set(false, keys: Set(rows.filter { $0.game == .eurojackpot }.map(\.id)), context: context)
    }
    private func encode(_ snapshot: LottoBackupSnapshot) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }
    private func decode(_ data: Data) throws -> LottoBackupSnapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LottoBackupSnapshot.self, from: data)
    }
    private func rows(_ context: ModelContext) throws -> [LotteryReportRow] {
        LotteryDeliverySync.applying(WeeklyLotteryReport.rows(lotto: try context.fetch(FetchDescriptor<Result>()),
            international: try context.fetch(FetchDescriptor<InternationalLotteryEntry>())),
            records: try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
    }

    @Test func offlineDiskStoreSurvivesCloseAndReopenForAllGames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("offline.store")
        func write() throws { let c = try makeContainer(url: url); try seed(c.mainContext) }
        try write()
        let reopened = try makeContainer(url: url)
        let saved = try rows(reopened.mainContext)
        #expect(saved.count == 3)
        #expect(saved.filter(\.isRegistered).count == 2)
        #expect(saved.first { $0.game == .eurojackpot }?.isRegistered == false)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<JackPot>()) == 1)
    }

    @Test func fullBackupFileRestoresAllGamesAndPositiveAndRemovedMarksIntoAnotherDiskStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try makeContainer()
        try seed(source.mainContext)
        let original = try LottoBackupStore.snapshot(context: source.mainContext, content: .everything, settings: settings)
        let file = folder.appendingPathComponent("backup.json")
        try encode(original).write(to: file)
        let snapshot = try decode(Data(contentsOf: file))
        #expect(snapshot.deliveryChanges?.contains { !$0.registered } == true)
        let targetURL = folder.appendingPathComponent("restored.store")
        func restore() throws {
            let target = try makeContainer(url: targetURL)
            try LottoBackupStore.restoreEverything(snapshot, context: target.mainContext)
        }
        try restore()
        let reopened = try makeContainer(url: targetURL)
        let expected = try rows(source.mainContext), actual = try rows(reopened.mainContext)
        #expect(actual.map(\.id) == expected.map(\.id))
        #expect(actual.map(\.isRegistered) == expected.map(\.isRegistered))
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<JackPot>()) == 1)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<InternationalLotteryEntry>()).filter(\.isDraw).count == 2)
    }

    @Test func unreadableDateRejectsRestoreBeforeReplacingExistingData() throws {
        let c = try makeContainer(); try seed(c.mainContext)
        var snapshot = try LottoBackupStore.snapshot(context: c.mainContext, content: .everything, settings: settings)
        let before = try rows(c.mainContext)
        snapshot.results[0].dato = Date(timeIntervalSince1970: .nan)
        #expect(throws: (any Error).self) { try LottoBackupStore.restoreEverything(snapshot, context: c.mainContext) }
        #expect(try rows(c.mainContext).map(\.id) == before.map(\.id))
        #expect(try rows(c.mainContext).map(\.isRegistered) == before.map(\.isRegistered))
        #expect(try c.mainContext.fetchCount(FetchDescriptor<JackPot>()) == 1)
    }

    @Test func invalidInternationalDrawDoesNotPartiallyImportNationalDraws() throws {
        let source = try makeContainer(); try seed(source.mainContext)
        var snapshot = try LottoBackupStore.snapshot(context: source.mainContext, content: .drawsOnly, settings: settings)
        snapshot.internationalEntries?[0].mainNumbers = [99]
        let target = try makeContainer()
        #expect(throws: (any Error).self) { try LottoBackupStore.importDraws(snapshot, context: target.mainContext) }
        #expect(try target.mainContext.fetchCount(FetchDescriptor<JackPot>()) == 0)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 0)
    }

    @Test func drawsOnlyImportPreservesOwnRowsAndStatusAndIsIdempotent() throws {
        let source = try makeContainer(); try seed(source.mainContext)
        let snapshot = try LottoBackupStore.snapshot(context: source.mainContext, content: .drawsOnly, settings: settings)
        #expect(snapshot.results.isEmpty)
        #expect(snapshot.deliveryChanges == nil)
        #expect(snapshot.internationalEntries?.allSatisfy(\.isDraw) == true)
        let target = try makeContainer()
        target.mainContext.insert(Result(dato: LotteryCalendar.date("2026-11-14")!,nr1: 11,nr2: 12,nr3: 13,nr4: 14,nr5: 15,nr6: 16,nr7: 17))
        try target.mainContext.save()
        let key = try rows(target.mainContext)[0].id
        try LotteryDeliverySync.set(true, keys: [key], context: target.mainContext)
        let first = try LottoBackupStore.importDraws(snapshot, context: target.mainContext)
        let second = try LottoBackupStore.importDraws(snapshot, context: target.mainContext)
        #expect(first.added == 3)
        #expect(second.added == 0)
        #expect(try rows(target.mainContext).count == 1)
        #expect(try rows(target.mainContext)[0].isRegistered == true)
        #expect(throws: (any Error).self) { try LottoBackupStore.restoreEverything(snapshot, context: target.mainContext) }
        #expect(try rows(target.mainContext).count == 1)
    }

    @Test func legacyFullBackupPreservesNewGamesAndUnspecifiedDeliveryStatus() throws {
        let c = try makeContainer(); try seed(c.mainContext)
        let original = try LottoBackupStore.snapshot(context: c.mainContext, content: .everything, settings: settings)
        let legacy = LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: original.jackpots, results: original.results)
        let before = try rows(c.mainContext)
        try LottoBackupStore.restoreEverything(try decode(encode(legacy)), context: c.mainContext)
        #expect(try rows(c.mainContext).map(\.id) == before.map(\.id))
        #expect(try rows(c.mainContext).map(\.isRegistered) == before.map(\.isRegistered))
    }

    @Test func separateOfflineContextsMergeChangesWithoutLosingOtherRows() throws {
        let a = try makeContainer(), b = try makeContainer()
        try LotteryDeliverySync.set(true, keys: ["shared","only-a"], context: a.mainContext, now: Date(timeIntervalSince1970: 100))
        try LotteryDeliverySync.set(false, keys: ["shared"], context: b.mainContext, now: Date(timeIntervalSince1970: 200))
        try LotteryDeliverySync.set(true, keys: ["only-b"], context: b.mainContext, now: Date(timeIntervalSince1970: 200))
        let fromA = try a.mainContext.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        let fromB = try b.mainContext.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        // Simulate delayed immutable change delivery in opposite orders.
        let left = LotteryDeliverySync.latest(fromA + fromB), right = LotteryDeliverySync.latest(fromB + fromA)
        #expect(left == right)
        #expect(left["shared"]?.registered == false)
        #expect(left["only-a"]?.registered == true)
        #expect(left["only-b"]?.registered == true)
    }

    @Test func truncatedFileFailsToDecodeAndLeavesExistingRowsUntouched() throws {
        let c = try makeContainer(); try seed(c.mainContext)
        let before = try rows(c.mainContext)
        #expect(throws: (any Error).self) { try decode(Data("{\"content\":\"everything\",".utf8)) }
        #expect(try rows(c.mainContext).map(\.id) == before.map(\.id))
    }
}

@MainActor
struct BackupCheckTests {
    @Test func checkUsesAnIndependentStoreAndKeepsPositiveAndNegativeMarks() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self, configurations: config)
        let context = container.mainContext
        context.insert(Result(dato: LotteryCalendar.date("2026-11-14")!,nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7))
        try context.save()
        let row = WeeklyLotteryReport.rows(lotto: try context.fetch(FetchDescriptor<Result>()), international: [])[0]
        try LotteryDeliverySync.set(true, keys: [row.id], context: context)
        try LotteryDeliverySync.set(false, keys: ["removed-row"], context: context)
        let settings = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        let snapshot = try LottoBackupStore.snapshot(context: context, content: .everything, settings: settings)
        let originalChanges = try context.fetchCount(FetchDescriptor<LotteryDeliveryChange>())
        let result = try LottoBackupStore.check(snapshot)
        #expect(result.lottoRows == 1)
        #expect(result.registeredRows == 1)
        #expect(try context.fetchCount(FetchDescriptor<LotteryDeliveryChange>()) == originalChanges)
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 1)
    }
    @Test func drawsOnlyCheckAndCorruptBackupCheckCannotModifyLiveStore() throws {
        let settings = LottoBackupSettings(tolerance: 0, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        let good = LottoBackupJackpot(dato: LotteryCalendar.date("2026-11-07")!,nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7,nr8: 8,weekNr: 45)
        let draws = LottoBackupSnapshot(content: .drawsOnly, exportedAt: .now, settings: settings, jackpots: [good], results: [])
        #expect(try LottoBackupStore.check(draws).drawCount == 1)
        var bad = draws
        bad.jackpots[0].nr8 = 99
        #expect(throws: (any Error).self) { try LottoBackupStore.check(bad) }
    }
}

@MainActor
struct FullArchiveBackupTests {
    @Test func completeBundledHistoryPassesBackupTrialRestore() throws {
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let lotto = try JSONDecoder().decode([JackPot].self, from: Data(contentsOf: base.appendingPathComponent("Lotto/Helpers/lotto.json")))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let international = try decoder.decode([InternationalLotteryRecord].self, from: Data(contentsOf: base.appendingPathComponent("Lotto/Helpers/international-draws.json")))
        let settings = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        let backup = LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: lotto.map(LottoBackupJackpot.init),
                                        results: [], internationalEntries: international, deliveryChanges: [])
        let result = try LottoBackupStore.check(backup)
        #expect(result.drawCount == 1393)
        #expect(result.lottoRows == 0)
        #expect(result.registeredRows == 0)
    }
}

@MainActor
struct LegacyOwnRowBackupTests {
    private func snapshot(date: String = "2026-04-11", value: Int = 128) -> LottoBackupSnapshot {
        let row = LottoBackupResult(dato: LotteryCalendar.date(date)!, nr1: 2,nr2: 4,nr3: 7,nr4: 8,nr5: 15,nr6: value,nr7: 25,weekNr: 15)
        let settings = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        return LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: [], results: [row])
    }
    @Test func legacyTypingMistakeIsRestoredExactlyAndReportedInsteadOfBlockingBackup() throws {
        let original = snapshot()
        let result = try LottoBackupStore.check(original)
        #expect(result.lottoRows == 1)
        #expect(result.warnings.count == 1)
        #expect(result.message.contains("128"))
        #expect(result.message.contains("11.04.2026"))
        let container = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        try LottoBackupStore.restoreEverything(original, context: container.mainContext)
        let restored = try container.mainContext.fetch(FetchDescriptor<Result>())
        #expect(restored.count == 1)
        #expect(restored[0].nr6 == 128)
        #expect(restored[0].dato == original.results[0].dato)
        // Recovery of historical data does not loosen validation for newly entered rows.
        #expect(LottoRules.rowValidationMessage(numbers: [2,4,7,8,15,128,25], drawDate: original.results[0].dato) != nil)
    }
    @Test func historicalNonDrawDateIsPreservedAndWarnedAbout() throws {
        let original = snapshot(date: "2026-04-10", value: 18)
        let result = try LottoBackupStore.check(original)
        #expect(result.warnings.count == 1)
        #expect(result.message.contains("10.04.2026"))
        #expect(result.message.contains("lørdag"))
        #expect(original.results[0].dato == LotteryCalendar.date("2026-04-10")!)
    }
}
