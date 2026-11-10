import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor
struct InternationalLotteryTests {
    @Test func separatePoolsAllowSameNumber() throws {
        let date = LotteryCalendar.date("2026-10-07")!
        #expect(InternationalGame.vikinglotto.validation(main: [1, 11, 31, 32, 34, 44], extra: [1], date: date) == nil)
        #expect(InternationalGame.vikinglotto.validation(main: [1, 1, 31, 32, 34, 44], extra: [1], date: date) != nil)
        #expect(InternationalGame.vikinglotto.validation(main: [1, 11, 31, 32, 34, 44], extra: [6], date: date) != nil)
    }

    @Test func eurojackpotDrawDaysAndPools() throws {
        for text in ["2026-10-02", "2026-10-06"] {
            #expect(InternationalGame.eurojackpot.validation(main: [1, 2, 3, 4, 50], extra: [1, 12], date: LotteryCalendar.date(text)!) == nil)
        }
        #expect(InternationalGame.eurojackpot.validation(main: [1, 2, 3, 4, 50], extra: [1, 12], date: LotteryCalendar.date("2026-10-03")!) != nil)
        #expect(LotteryCalendar.text(InternationalGame.eurojackpot.nextDraw(onOrAfter: LotteryCalendar.date("2026-10-03")!)) == "2026-10-06")
    }

    @Test func decodesActualAPIResponses() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let viking = try InternationalLotteryUpdater.decode(Data(contentsOf: folder.appendingPathComponent("vikinglotto-response.json")), game: .vikinglotto)
        #expect(viking.count == 1)
        #expect(viking[0].mainNumbers == [1, 11, 31, 32, 34, 44])
        #expect(viking[0].extraNumbers == [1])
        let euro = try InternationalLotteryUpdater.decode(Data(contentsOf: folder.appendingPathComponent("eurojackpot-response.json")), game: .eurojackpot)
        #expect(euro.count == 2)
        #expect(euro[0].mainNumbers == [7, 12, 19, 28, 50])
        #expect(euro[0].extraNumbers == [1, 6])
    }

    @Test func bundledArchiveIsCompleteAndValid() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Lotto/Helpers/international-draws.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([InternationalLotteryRecord].self, from: Data(contentsOf: path))
        #expect(records.count == 603)
        #expect(Set(records.map(\.key)).count == records.count)
        for record in records { _ = try record.validatedModel() }
        for game in InternationalGame.allCases {
            let gameRecords = records.filter { $0.gameID == game.rawValue }
            let dates = Set(gameRecords.map { LotteryCalendar.text($0.date) })
            var day = game.nextDraw(onOrAfter: LotteryCalendar.archiveStart)
            let last = gameRecords.map(\.date).max()!
            while day <= last {
                #expect(dates.contains(LotteryCalendar.text(day)))
                day = game.nextDraw(onOrAfter: LotteryCalendar.calendar.date(byAdding: .day, value: 1, to: day)!)
            }
        }
    }

    @Test func newGamesPersistAlongsideExistingLotto() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, configurations: configuration)
        let context = container.mainContext
        context.insert(JackPot(dato: .now, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 5, nr6: 6, nr7: 7, nr8: 8))
        context.insert(InternationalLotteryEntry(game: .vikinglotto, isDraw: false, date: LotteryCalendar.date("2026-10-07")!, main: [1,2,3,4,5,6], extra: [1]))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<JackPot>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 1)
        try InternationalLotteryUpdater.seed(context: context)
        try InternationalLotteryUpdater.seed(context: context)
        // Seed may be unavailable in the test bundle; persistence must still keep the row.
        #expect(try context.fetch(FetchDescriptor<InternationalLotteryEntry>()).filter { !$0.isDraw }.count == 1)
    }

    @Test func backupRoundTripIncludesNewGamesAndLegacyRemainsReadable() throws {
        let record = InternationalLotteryRecord(gameID: "eurojackpot", isDraw: false, date: LotteryCalendar.date("2026-10-06")!, mainNumbers: [1,2,3,4,5], extraNumbers: [1,2])
        let settings = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false)
        let snapshot = LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: [], results: [], internationalEntries: [record])
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(snapshot)
        #expect(try decoder.decode(LottoBackupSnapshot.self, from: data).internationalEntries == [record])
        let legacy = LottoBackupSnapshot(exportedAt: .now, settings: settings, jackpots: [], results: [])
        #expect(try decoder.decode(LottoBackupSnapshot.self, from: encoder.encode(legacy)).internationalEntries == nil)
    }
}

@MainActor
struct LotteryMigrationTests {
    @Test func addingInternationalModelPreservesExistingStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("migration.store")
        func createOriginalStore() throws {
            let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: JackPot.self, Result.self, configurations: config)
            let context = ModelContext(container)
            context.insert(Result(dato: LotteryCalendar.date("2026-10-03")!, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 5, nr6: 6, nr7: 7))
            try context.save()
        }
        try createOriginalStore()
        let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let upgraded = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, configurations: config)
        let context = ModelContext(upgraded)
        let rows = try context.fetch(FetchDescriptor<Result>())
        #expect(rows.count == 1)
        #expect(rows.first?.nr7 == 7)
        context.insert(InternationalLotteryEntry(game: .eurojackpot, isDraw: false, date: LotteryCalendar.date("2026-10-06")!, main: [1,2,3,4,5], extra: [1,2]))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 1)
    }
}
