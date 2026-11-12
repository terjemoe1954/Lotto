import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor struct LotteryOwnRowStoreTests {
    private func store() throws -> ModelContainer {
        try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
    private func lotto(_ date: String, _ numbers: [Int] = [1,2,3,4,5,6,7], seconds: TimeInterval = 0) -> Result {
        Result(dato: LotteryCalendar.date(date)!.addingTimeInterval(seconds), nr1: numbers[0], nr2: numbers[1], nr3: numbers[2], nr4: numbers[3], nr5: numbers[4], nr6: numbers[5], nr7: numbers[6], weekNr: 45)
    }
    @Test func blocksRepeatedSaveIncludingPendingAndReorderedNumbersButAllowsOtherDraws() throws {
        let container = try store(), context = container.mainContext
        let original = lotto("2026-11-07")
        try LotteryOwnRowStore.insert(original, context: context)
        #expect(throws: LotteryOwnRowStore.SaveError.self) {
            try LotteryOwnRowStore.insert(lotto("2026-11-07",[7,6,5,4,3,2,1],seconds:3600), context: context)
        }
        try context.save()
        #expect(throws: LotteryOwnRowStore.SaveError.self) { try LotteryOwnRowStore.insert(lotto("2026-11-07"),context:context) }
        try LotteryOwnRowStore.insert(lotto("2026-11-14"),context:context)
        try LotteryOwnRowStore.insert(lotto("2025-11-08"),context:context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Result>()) == 3)
        #expect(original.nr1 == 1 && original.nr7 == 7)
    }
    @Test func distinguishesInternationalExtraNumbersGamesAndDraws() throws {
        let container = try store(), context = container.mainContext
        func row(_ extra: [Int], _ day: String = "2026-11-03", draw: Bool = false) -> InternationalLotteryEntry {
            InternationalLotteryEntry(game:.eurojackpot,isDraw:draw,date:LotteryCalendar.date(day)!,main:[1,2,3,4,5],extra:extra)
        }
        try LotteryOwnRowStore.insert(row([1,3]),context:context)
        #expect(throws: LotteryOwnRowStore.SaveError.self) { try LotteryOwnRowStore.insert(row([3,1]),context:context) }
        try LotteryOwnRowStore.insert(row([1,4]),context:context)
        try LotteryOwnRowStore.insert(row([1,3],"2026-11-06"),context:context)
        try LotteryOwnRowStore.insert(row([1,3],draw:true),context:context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 4)
        #expect(LotteryOwnRowStore.Key(game:"lotto",date:.now,main:[1]) != LotteryOwnRowStore.Key(game:"vikinglotto",date:.now,main:[1]))
    }
    @Test func oldBackupRestoresOneOriginalPerOwnRowAndKeepsDeliveryAndDraws() throws {
        let source = try store(), context = source.mainContext
        context.insert(lotto("2026-11-07"));context.insert(lotto("2026-11-07",[7,6,5,4,3,2,1],seconds:3600))
        for draw in [false,false,true] {
            context.insert(InternationalLotteryEntry(game:.vikinglotto,isDraw:draw,date:LotteryCalendar.date("2026-11-04")!,main:[1,2,3,4,5,6],extra:[1]))
        }
        let key=WeeklyLotteryReport.rows(lotto:try context.fetch(FetchDescriptor<Result>()),international:[])[0].id
        context.insert(LotteryDeliveryChange(rowKey:key,registered:true));try context.save()
        let backup=try LottoBackupStore.snapshot(context:context,content:.everything,settings:.init(tolerance:3,appearanceModeRawValue:"system",excludeHighestGapFromAverage:false))
        let encoder=JSONEncoder();encoder.outputFormatting = [.sortedKeys]
        let bytes=try encoder.encode(backup)
        let check=try LottoBackupStore.check(backup)
        #expect(check.lottoRows == 1 && check.vikingRows == 1 && check.drawCount == 1)
        #expect(check.duplicateRowsSkipped == 2)
        let target=try store();try LottoBackupStore.restoreEverything(backup,context:target.mainContext)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<Result>()) == 1)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<InternationalLotteryEntry>()) == 2)
        #expect(try target.mainContext.fetch(FetchDescriptor<LotteryDeliveryChange>()).first?.registered == true)
        #expect(try encoder.encode(backup) == bytes) // No mutation of the original backup.
    }
}
