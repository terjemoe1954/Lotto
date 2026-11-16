import Foundation
import SwiftData
import Testing
@testable import Lotto

@MainActor struct LotteryRegistrationsTests {
    let date = LotteryCalendar.date("2026-11-21")!
    func store() throws -> ModelContainer {
        try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }
    func row(_ last: Int = 7) -> LotteryReportRow { .init(game: .lotto, date: date, mainNumbers: [1,2,3,4,5,6,last], extraNumbers: []) }
    @Test func bulkMarksOnlyRequestedRowsAndIsIdempotent() throws {
        let container = try store()
        let c = container.mainContext
        let current = LotterySystem.rows(game: .lotto, main: Array(1...12), extra: [], date: date)
        let old = LotteryReportRow(game: .lotto, date: LotteryCalendar.date("2026-11-14")!, mainNumbers: [1,2,3,4,5,6,7], extraNumbers: [])
        let keys = Set(current.map(\.id))
        try LotteryDeliverySync.set(true, keys: [old.id], context: c)
        let began = Date()
        try LotteryDeliverySync.set(true, keys: keys, context: c)
        let elapsed = Date().timeIntervalSince(began)
        let first = try c.fetchCount(FetchDescriptor<LotteryDeliveryChange>())
        try LotteryDeliverySync.set(true, keys: keys, context: c)
        #expect(try c.fetchCount(FetchDescriptor<LotteryDeliveryChange>()) == first)
        #expect(first == 793)
        let records = try c.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        #expect(LotteryDeliverySync.latest(records)[old.id]?.registered == true)
        #expect(LotteryDeliverySync.applying(current, records: records).allSatisfy { $0.isRegistered })
        #expect(elapsed < 5)
        print("LOTTO_BULK_792_SECONDS \(elapsed)")
    }
    @Test func correctedDeliveredRowMovesMarkWithoutDoubleExpenseAndProtectsDraws() throws {
        let container = try store()
        let c = container.mainContext
        let a = row(), b = row(8)
        _ = try LotterySystem.save([a], context: c)
        c.insert(JackPot(dato: date, nr1: 1,nr2: 2,nr3: 3,nr4: 4,nr5: 5,nr6: 6,nr7: 7,nr8: 8))
        try LotteryDeliverySync.set(true, keys: [a.id], context: c)
        try LotteryRegistrationStore.replace(a, with: b, context: c)
        #expect(try LotteryRegistrationStore.ownRows(context: c).map(\.id) == [b.id])
        let delivered = AutomaticLotteryLedger.deliveredRows(try c.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
        #expect(delivered.map(\.id) == [b.id])
        #expect(AutomaticLotteryLedger.items(rows: delivered, tables: []).reduce(0) { $0 + $1.record.stakeOre } == 500)
        #expect(try c.fetchCount(FetchDescriptor<JackPot>()) == 1)
    }
    @Test func invalidOrDuplicateCorrectionKeepsOriginalData() throws {
        let container = try store()
        let c = container.mainContext
        _ = try LotterySystem.save([row(),row(8)], context: c)
        #expect(throws: (any Error).self) { try LotteryRegistrationStore.replace(row(), with: row(8), context: c) }
        let invalid = LotteryReportRow(game: .lotto, date: date, mainNumbers: [1,1,2,3,4,5,6], extraNumbers: [])
        #expect(throws: (any Error).self) { try LotteryRegistrationStore.replace(row(), with: invalid, context: c) }
        #expect(try c.fetchCount(FetchDescriptor<Result>()) == 2)
        #expect(try c.fetchCount(FetchDescriptor<LotteryDeliveryChange>()) == 0)
    }
    @Test func deletingSavedRowCanKeepOrRemoveDeliveredHistory() throws {
        let container = try store()
        let c = container.mainContext
        _ = try LotterySystem.save([row()], context: c)
        try LotteryDeliverySync.set(true, keys: [row().id], context: c)
        try LotteryRegistrationStore.delete([row()], removeDelivery: false, context: c)
        #expect(try c.fetchCount(FetchDescriptor<Result>()) == 0)
        #expect(AutomaticLotteryLedger.deliveredRows(try c.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)).count == 1)
        try LotteryRegistrationStore.delete([row()], removeDelivery: true, context: c)
        #expect(AutomaticLotteryLedger.deliveredRows(try c.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)).isEmpty)
    }
    @Test func deletingSystemKeepsSharedRowsAndTheirDelivery() throws {
        let container = try store()
        let c = container.mainContext
        _ = try LotterySystem.saveSystem(game: .lotto, main: Array(1...8), extra: [], date: date, context: c)
        _ = try LotterySystem.saveSystem(game: .lotto, main: [1,2,3,4,5,6,7,9], extra: [], date: date, context: c)
        let original = LotterySystemSelection(gameID: "lotto", dateText: LotteryCalendar.text(date), main: Array(1...8), extra: [])
        let all = try LotteryRegistrationStore.ownRows(context: c)
        try LotteryDeliverySync.set(true, keys: Set(all.map(\.id)), context: c)
        try LotteryRegistrationStore.deleteSystem(original, removeDelivery: true, context: c, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let remaining = try LotteryRegistrationStore.ownRows(context: c)
        #expect(remaining.count == 8)
        #expect(remaining.allSatisfy { !$0.systems.contains(original) && $0.systems.count == 1 })
        #expect(AutomaticLotteryLedger.deliveredRows(try c.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)).count == 8)
    }
    @Test func replaceSystemPreservesManualPostsAndDoesNotInventDeliveries() throws {
        let container = try store()
        let c = container.mainContext
        _ = try LotterySystem.saveSystem(game: .lotto, main: Array(1...8), extra: [], date: date, context: c)
        let original = LotterySystemSelection(gameID: "lotto", dateText: LotteryCalendar.text(date), main: Array(1...8), extra: [])
        let old = try LotteryRegistrationStore.ownRows(context: c)
        let entry = LotteryLedgerEntry(record: .init(id: "manual", gameID: "lotto", date: date, stakeOre: 500, prizeOre: 0, note: "test"))
        c.insert(entry)
        try LotteryDeliverySync.set(true, keys: Set(old.map(\.id)), context: c)
        try LotteryRegistrationStore.replaceSystem(original, game: .lotto, main: Array(10...17), extra: [], date: date, removeOldDelivery: false, context: c, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let remaining = try LotteryRegistrationStore.ownRows(context: c)
        #expect(remaining.count == 8)
        #expect(remaining.allSatisfy { $0.mainNumbers.min()! >= 10 && !$0.systems.contains(original) })
        let changes = try c.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        #expect(AutomaticLotteryLedger.deliveredRows(changes).count == 8)
        #expect(LotteryDeliverySync.applying(remaining, records: changes).allSatisfy { !$0.isRegistered })
        #expect(try c.fetchCount(FetchDescriptor<LotteryLedgerEntry>()) == 1)
    }
    @Test func correctingOneSystemComponentDetachesOnlyThatComponent() throws {
        let container = try store()
        let c = container.mainContext
        _ = try LotterySystem.saveSystem(game: .lotto, main: Array(1...8), extra: [], date: date, context: c)
        let original = try LotteryRegistrationStore.ownRows(context: c).first!
        let corrected = LotteryReportRow(game: .lotto, date: date, mainNumbers: [20,21,22,23,24,25,26], extraNumbers: [])
        try LotteryRegistrationStore.replace(original, with: corrected, context: c)
        let result = try LotteryRegistrationStore.ownRows(context: c)
        #expect(result.count == 8)
        #expect(result.filter { !$0.systems.isEmpty }.count == 7)
        #expect(result.first { $0.id == corrected.id }?.systems.isEmpty == true)
    }
}
