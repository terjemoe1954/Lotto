import Foundation
import SwiftData
import Testing
import PDFKit
@testable import Lotto

private struct SystemTestRandom: RandomNumberGenerator {
    var value: UInt64 = 87
    mutating func next() -> UInt64 {
        value &+= 0x9e3779b97f4a7c15
        var z = value
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
@MainActor struct LotterySystemMembershipTests {
    private let date = LotteryCalendar.date("2026-11-21")!
    private var settings: LottoBackupSettings { .init(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false) }
    private func store() throws -> ModelContainer {
        try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
    @Test func equalScoresDoNotLockLowNumbersIntoEveryRow() {
        var random = SystemTestRandom()
        let rows = LottoSuggestionEngine.makeSuggestedRows(for: date, predictedNumbers: Array(1...34), jackpots: [], rowCount: 100, using: &random)
        #expect(rows.count == 100)
        #expect(Set(rows.map(\.id)).count == 100)
        #expect(rows.filter { Set([1,2,3]).isSubset(of: Set($0.numbers)) }.count < 20)
        #expect(rows.allSatisfy { $0.numbers.count == 7 && Set($0.numbers).count == 7 })
        #expect(rows.flatMap(\.numbers).contains(34))
    }
    @Test func historicalFrequencyStillWeightsHighNumbersAndIgnoresFutureDraws() {
        let past = date.addingTimeInterval(-604800)
        let history = (0..<20).map { _ in JackPot(dato: past, nr1: 25,nr2: 26,nr3: 27,nr4: 28,nr5: 29,nr6: 30,nr7: 31,nr8: 32) }
        var a = SystemTestRandom(), b = SystemTestRandom()
        let rows = LottoSuggestionEngine.makeSuggestedRows(for: date, predictedNumbers: [], jackpots: history, rowCount: 100, using: &a)
        let future = JackPot(dato: date, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7,nr8: 8)
        let again = LottoSuggestionEngine.makeSuggestedRows(for: date, predictedNumbers: [], jackpots: history + [future], rowCount: 100, using: &b)
        #expect(rows == again)
        #expect(Set(rows[0].numbers).isSubset(of: Set(25...32)))
        #expect(rows.flatMap(\.numbers).filter { (25...32).contains($0) }.count > 200)
    }
    @Test func overlappingSystemsRetainBothSelectionsWithoutDuplicateStakesAndBackupRestoresThem() throws {
        let container = try store(), context = container.mainContext
        #expect(try LotterySystem.saveSystem(game: .lotto, main: Array(1...8), extra: [], date: date, context: context) == 8)
        #expect(try LotterySystem.saveSystem(game: .lotto, main: Array(1...7) + [9], extra: [], date: date, context: context) == 7)
        #expect(try LotterySystem.saveSystem(game: .lotto, main: Array(1...8), extra: [], date: date, context: context) == 0)
        let all = try context.fetch(FetchDescriptor<Result>())
        #expect(all.count == 15)
        let report = WeeklyLotteryReport.rows(lotto: all, international: [])
        #expect(report.count == 15)
        #expect(Set(report.flatMap(\.systems)).count == 2)
        #expect(report.filter { $0.systems.count == 2 }.count == 1)
        #expect(report.count * AutomaticLotteryLedger.priceOre(.lotto) == 7500)
        let snapshot = try LottoBackupStore.snapshot(context: context, content: .everything, settings: settings)
        #expect(try LottoBackupStore.check(snapshot).lottoRows == 15)
        let restored = try store()
        try LottoBackupStore.restoreEverything(snapshot, context: restored.mainContext)
        let rows = WeeklyLotteryReport.rows(lotto: try restored.mainContext.fetch(FetchDescriptor<Result>()), international: [])
        #expect(Set(rows.flatMap(\.systems)) == Set(report.flatMap(\.systems)))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let prepared = try LotteryOwnGamesReset.prepare(context: context, settings: settings, backupDirectory: dir)
        try LotteryOwnGamesReset.reset(prepared, context: context, settings: settings, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 0)
        try LottoBackupStore.restoreEverything(snapshot, context: context)
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 15)
    }
    @Test func internationalSystemMetadataAndLegacyBackupsRoundTrip() throws {
        let container = try store(), context = container.mainContext
        let day = LotteryCalendar.date("2026-11-20")!
        #expect(try LotterySystem.saveSystem(game: .eurojackpot, main: Array(1...6), extra: [1,2,3], date: day, context: context) == 18)
        let snapshot = try LottoBackupStore.snapshot(context: context, content: .everything, settings: settings)
        #expect(try LottoBackupStore.check(snapshot).euroRows == 18)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(LottoBackupSnapshot.self, from: encoder.encode(snapshot))
        #expect(back.internationalEntries?.allSatisfy { $0.systemMembershipJSON != nil } == true)
        let legacy = try decoder.decode(LottoBackupResult.self, from: Data("{\"dato\":\"2026-11-21T00:00:00Z\",\"nr1\":1,\"nr2\":2,\"nr3\":3,\"nr4\":4,\"nr5\":5,\"nr6\":6,\"nr7\":7,\"weekNr\":47}".utf8))
        #expect(legacy.makeModel().systemMembershipJSON == nil)
    }
    @Test func duplicateCleanupUnionsSystemLabelsAndPDFIncludesFullSystemOverview() throws {
        let container = try store(), context = container.mainContext
        _ = try LotterySystem.saveSystem(game: .lotto, main: Array(1...8), extra: [], date: date, context: context)
        let row = try #require(context.fetch(FetchDescriptor<Result>()).first)
        let duplicate = LottoBackupResult(row).makeModel()
        let another = LotterySystemSelection(gameID: "lotto", dateText: "2026-11-21", main: Array(1...9), extra: [])
        duplicate.systemMembershipJSON = LotterySystemSelection.encode([another]); context.insert(duplicate); try context.save()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try LotteryDuplicateCleanup.clean(context: context, settings: settings, backupDirectory: dir)
        let report = WeeklyLotteryReport.rows(lotto: try context.fetch(FetchDescriptor<Result>()), international: [])
        #expect(report.count == 8)
        #expect(Set(report.flatMap(\.systems)).count == 2)
        // Add more than one summary page, including a large extra-number pool.
        var sample = report
        for i in 0..<6 {
            let game: LotteryReportGame = i == 5 ? .eurojackpot : .lotto
            let selection = LotterySystemSelection(gameID: game.rawValue, dateText: i == 5 ? "2026-11-20" : "2026-11-21", main: i == 5 ? Array(1...10) : Array((i+1)...(i+8)), extra: i == 5 ? Array(1...12) : [])
            sample[i].systems.append(selection)
        }
        let data = WeeklyLotteryPDF.data(rows: sample, week: LotteryReportWeek(date: date))
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount >= 3)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        #expect(text.contains("Systemoversikt"))
        #expect(text.contains("Tilleggstall:"))
        let qa = FileManager.default.temporaryDirectory.appendingPathComponent("Lotto-System-QA", isDirectory: true)
        try FileManager.default.createDirectory(at: qa, withIntermediateDirectories: true)
        try data.write(to: qa.appendingPathComponent("system-report.pdf"))
        try WeeklyLotteryWorkbook.data(rows: sample).write(to: qa.appendingPathComponent("system-report.xlsx"))
        print("System QA directory: \(qa.path)")
    }
}
