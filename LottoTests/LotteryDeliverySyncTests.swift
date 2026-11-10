import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor
struct LotteryDeliverySyncTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: LotteryDeliveryChange.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
    private func row() -> LotteryReportRow {
        LotteryReportRow(game: .lotto, date: LotteryCalendar.date("2026-11-14")!, mainNumbers: [1,2,3,4,5,6,7], extraNumbers: [])
    }
    @Test func arrivalOrderDuplicatesAndTiesConverge() {
        let time = Date(timeIntervalSince1970: 100)
        let mark = LotteryDeliveryRecord(rowKey: "row", registered: true, changedAt: time, changeID: "a")
        let undo = LotteryDeliveryRecord(rowKey: "row", registered: false, changedAt: time.addingTimeInterval(1), changeID: "b")
        #expect(LotteryDeliverySync.latest([mark,undo,mark])["row"]?.registered == false)
        #expect(LotteryDeliverySync.latest([undo,mark])["row"]?.registered == false)
        let tie = LotteryDeliveryRecord(rowKey: "row", registered: true, changedAt: undo.changedAt, changeID: "z")
        #expect(LotteryDeliverySync.latest([tie,undo]) == LotteryDeliverySync.latest([undo,tie]))
        #expect(LotteryDeliverySync.latest([tie,undo])["row"]?.changeID == "z")
    }
    @Test func legacyImportIsIdempotentAndCannotOverrideUndo() throws {
        let container = try container()
        let context = container.mainContext
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let row = row()
        defaults.set(WeeklyLotteryDelivery.encoded([row.id]), forKey: WeeklyLotteryDelivery.storageKey)
        try LotteryDeliverySync.migrateLegacy(rows: [row], context: context, defaults: defaults)
        try LotteryDeliverySync.migrateLegacy(rows: [row], context: context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<LotteryDeliveryChange>()) == 1)
        try LotteryDeliverySync.set(false, keys: [row.id], context: context)
        try LotteryDeliverySync.migrateLegacy(rows: [row], context: context, defaults: defaults)
        let records = try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        #expect(!LotteryDeliverySync.applying([row], records: records)[0].isRegistered)
        // A second device imports its old positive mark after the undo: the undo still wins.
        let lateImport = LotteryDeliveryRecord(rowKey: row.id, registered: true, changedAt: Date(timeIntervalSince1970: 0), changeID: UUID().uuidString)
        #expect(!LotteryDeliverySync.applying([row], records: records + [lateImport])[0].isRegistered)
    }
    @Test func setPreservesUndoAndIsMonotonicWithClockChanges() throws {
        let container = try container()
        let context = container.mainContext
        try LotteryDeliverySync.set(true, keys: ["a"], context: context, now: Date(timeIntervalSince1970: 100))
        try LotteryDeliverySync.set(true, keys: ["a"], context: context)
        #expect(try context.fetchCount(FetchDescriptor<LotteryDeliveryChange>()) == 1)
        try LotteryDeliverySync.set(false, keys: ["a"], context: context, now: Date(timeIntervalSince1970: 50))
        let records = try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        #expect(LotteryDeliverySync.latest(records)["a"]?.registered == false)
        #expect(LotteryDeliverySync.latest(records)["a"]!.changedAt > Date(timeIntervalSince1970: 100))
    }
    @Test func restoreCreatesNewChangesAndClearsMarksMissingFromBackup() throws {
        let container = try container()
        let context = container.mainContext
        try LotteryDeliverySync.set(true, keys: ["a","b"], context: context)
        let backup = [LotteryDeliveryRecord(rowKey: "a", registered: false, changedAt: .distantPast, changeID: "old"),
                      LotteryDeliveryRecord(rowKey: "c", registered: true, changedAt: .distantPast, changeID: "old2")]
        try LotteryDeliverySync.restore(backup, context: context)
        try context.save()
        let resolved = LotteryDeliverySync.latest(try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
        #expect(resolved["a"]?.registered == false)
        #expect(resolved["b"]?.registered == false)
        #expect(resolved["c"]?.registered == true)
    }
    @Test func newBackupRoundTripsChangesAndLegacyHasNoChangesField() throws {
        let settings = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        let record = LotteryDeliveryRecord(rowKey: "a", registered: false, changedAt: Date(timeIntervalSince1970: 100), changeID: "undo")
        let snapshot = LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: [], results: [], deliveryChanges: [record])
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        #expect(try decoder.decode(LottoBackupSnapshot.self, from: encoder.encode(snapshot)).deliveryChanges == [record])
        let legacy = LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: [], results: [])
        #expect(try decoder.decode(LottoBackupSnapshot.self, from: encoder.encode(legacy)).deliveryChanges == nil)
    }
    @Test func addingChangeModelPreservesExistingRowsAndPersistsMarks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("store")
        func seed() throws {
            let original = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(original)
            context.insert(Result(dato: LotteryCalendar.date("2026-11-14")!, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7))
            try context.save()
        }
        try seed()
        func upgrade() throws {
            let upgraded = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(upgraded)
            #expect(try context.fetchCount(FetchDescriptor<Result>()) == 1)
            try LotteryDeliverySync.set(true, keys: [row().id], context: context)
        }
        try upgrade()
        let reopened = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self,
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(reopened)
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<LotteryDeliveryChange>()) == 1)
        #expect(try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).first?.registered == true)
    }
}
