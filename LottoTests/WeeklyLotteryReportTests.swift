import Foundation
import SwiftData
import PDFKit
import Testing
@testable import Lotto

@MainActor
struct WeeklyLotteryReportTests {
    private func row(_ game: LotteryReportGame, _ date: String, offset: Int = 0) -> LotteryReportRow {
        let main = game == .lotto ? [1,2,3,4,5,6,7 + offset] : game == .vikinglotto ? [1,2,3,4,5,6 + offset] : [1,2,3,4,5 + offset]
        return LotteryReportRow(game: game, date: LotteryCalendar.date(date)!, mainNumbers: main,
                                extraNumbers: game == .lotto ? [] : game == .vikinglotto ? [5] : [1,12])
    }
    @Test func isoWeekIncludesCorrectYearAcrossNewYear() {
        let week = LotteryReportWeek(date: LotteryCalendar.date("2021-01-01")!)
        #expect(week.year == 2020)
        #expect(week.number == 53)
        #expect(LotteryCalendar.text(week.start) == "2020-12-28")
        #expect(LotteryCalendar.text(week.end) == "2021-01-03")
        #expect(LotteryReportWeek.weeks(in: 2020) == 53)
        #expect(LotteryReportWeek.weeks(in: 2021) == 52)
    }
    @Test func filteringRespectsYearGameAndExplicitSelection() {
        let lotto = row(.lotto, "2026-11-14")
        let viking = row(.vikinglotto, "2026-11-11")
        let euro = row(.eurojackpot, "2026-11-10")
        let old = row(.lotto, "2025-11-15")
        let rows = [lotto,viking,euro,old]
        let week = LotteryReportWeek(year: 2026, number: 46)
        #expect(WeeklyLotteryReport.filtered(rows, week: week, games: Set(LotteryReportGame.allCases)).count == 3)
        #expect(WeeklyLotteryReport.filtered(rows, week: week, games: [.lotto,.eurojackpot]).count == 2)
        #expect(WeeklyLotteryReport.filtered(rows, week: week, games: Set(LotteryReportGame.allCases), selection: [viking.id]) == [viking])
        #expect(WeeklyLotteryReport.filtered(rows, week: week, games: Set(LotteryReportGame.allCases), selection: []).isEmpty)
    }
    @Test func bothEurojackpotDrawDaysInWeekAreIncluded() {
        let rows = [row(.eurojackpot, "2026-11-10"),row(.eurojackpot, "2026-11-13"),row(.eurojackpot, "2026-11-17")]
        let selected = WeeklyLotteryReport.filtered(rows, week: LotteryReportWeek(year: 2026, number: 46), games: [.eurojackpot])
        #expect(selected.count == 2)
    }
    @Test func adaptersExcludeWinningDrawsAndPreserveLegacyMarkKey() {
        let date = LotteryCalendar.date("2026-11-14")!
        let lotto = Result(dato: date, nr1: 7,nr2: 6,nr3: 5,nr4: 4,nr5: 3,nr6: 2,nr7: 1)
        let own = InternationalLotteryEntry(game: .vikinglotto, isDraw: false, date: LotteryCalendar.date("2026-11-11")!, main: [1,2,3,4,5,6], extra: [5])
        let draw = InternationalLotteryEntry(game: .vikinglotto, isDraw: true, date: own.date, main: [1,2,3,4,5,6], extra: [5])
        let rows = WeeklyLotteryReport.rows(lotto: [lotto], international: [own,draw])
        #expect(rows.count == 2)
        #expect(rows[0].extraNumbers.isEmpty)
        #expect(rows[0].legacyDeliveryKey == "\(LottoDateSupport.normalize(date).timeIntervalSince1970)-7-6-5-4-3-2-1")
    }
    @Test func stableKeysDeduplicateRowsAndKeepDatesAndPoolsSeparate() {
        let original = row(.vikinglotto, "2026-11-11")
        let reordered = LotteryReportRow(game: .vikinglotto, date: original.date, mainNumbers: Array(original.mainNumbers.reversed()), extraNumbers: [5])
        let changedExtra = LotteryReportRow(game: .vikinglotto, date: original.date, mainNumbers: original.mainNumbers, extraNumbers: [4])
        #expect(original.id == reordered.id)
        #expect(original.id != changedExtra.id)
        #expect(WeeklyLotteryReport.normalized([original,reordered,changedExtra]).count == 2)
        #expect(original.id != row(.vikinglotto, "2026-11-18").id)
        let numeric = WeeklyLotteryReport.normalized([row(.lotto,"2026-11-14",offset: 3),row(.lotto,"2026-11-14")])
        #expect(numeric[0].mainNumbers.last == 7)
    }
    @Test func marksRoundTripAndCanBeUndoneWithoutChangingRowIdentity() {
        let first = row(.lotto, "2026-11-14")
        let second = row(.eurojackpot, "2026-11-13")
        let encoded = WeeklyLotteryDelivery.encoded([first.id])
        let marked = WeeklyLotteryDelivery.applying([first,second], registered: WeeklyLotteryDelivery.keys(encoded), legacy: [])
        #expect(marked[0].isRegistered)
        #expect(!marked[1].isRegistered)
        #expect(marked[0].id == first.id)
        let undone = WeeklyLotteryDelivery.applying(marked, registered: [], legacy: [])
        #expect(!undone[0].isRegistered)
        var legacyRow = first
        legacyRow.legacyDeliveryKey = "existing-key"
        #expect(WeeklyLotteryDelivery.applying([legacyRow], registered: [], legacy: ["existing-key"])[0].isRegistered)
    }
    @Test func backupIncludesMarksWhileLegacyBackupLeavesThemUnspecified() throws {
        let original = LottoBackupSettings(tolerance: 3, appearanceModeRawValue: "system", excludeHighestGapFromAverage: false,
                                          weeklyRegisteredRows: "row-key", lottoTransferredRows: "legacy-key")
        let restored = try JSONDecoder().decode(LottoBackupSettings.self, from: JSONEncoder().encode(original))
        #expect(restored.weeklyRegisteredRows == "row-key")
        #expect(restored.lottoTransferredRows == "legacy-key")
        let old = Data("{\"tolerance\":3,\"appearanceModeRawValue\":\"system\",\"excludeHighestGapFromAverage\":false}".utf8)
        #expect(try JSONDecoder().decode(LottoBackupSettings.self, from: old).weeklyRegisteredRows == nil)
    }
    @Test func pageBreaksRetainAllRowsAndWorkbookAndPDFAreReadable() throws {
        let rows = (0..<20).flatMap { index -> [LotteryReportRow] in
            var lotto = row(.lotto,"2026-11-14", offset: index)
            lotto.isRegistered = index.isMultiple(of: 3)
            return [lotto,row(.vikinglotto,"2026-11-11",offset: index),row(.eurojackpot,index.isMultiple(of: 2) ? "2026-11-10" : "2026-11-13",offset: index)]
        }
        let ordered = WeeklyLotteryReport.normalized(rows)
        let pages = WeeklyLotteryReport.pages(ordered)
        #expect(pages.count == 3)
        #expect(pages.map(\.count) == [26,26,8])
        #expect(pages.flatMap { $0 } == ordered)
        let week = LotteryReportWeek(year: 2026, number: 46)
        let pdf = WeeklyLotteryPDF.data(rows: ordered, week: week)
        let document = try #require(PDFDocument(data: pdf))
        #expect(document.pageCount == 3)
        for index in 0..<3 {
            let text = document.page(at: index)?.string ?? ""
            #expect(text.contains("Uke 46, 2026"))
            #expect(text.contains("Side \(index + 1) av 3"))
        }
        let xlsx = WeeklyLotteryWorkbook.data(rows: ordered)
        #expect(Array(xlsx.prefix(4)) == [0x50,0x4b,0x03,0x04])
        #expect(WeeklyLotteryWorkbook.excelDate(LotteryCalendar.date("2026-11-10")!) == 46336)
        let qa = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: qa, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: qa) }
        try xlsx.write(to: qa.appendingPathComponent("weekly-report.xlsx"))
        try pdf.write(to: qa.appendingPathComponent("weekly-report.pdf"))
        #expect(try Data(contentsOf: qa.appendingPathComponent("weekly-report.xlsx")) == xlsx)
        #expect(try Data(contentsOf: qa.appendingPathComponent("weekly-report.pdf")) == pdf)
    }
}
