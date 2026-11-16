import Foundation
import SwiftData

/// Mutations only target own rows; official draw archives are never edited here.
@MainActor enum LotteryRegistrationStore {
    static func ownRows(context: ModelContext) throws -> [LotteryReportRow] {
        WeeklyLotteryReport.rows(lotto: try context.fetch(FetchDescriptor<Result>()), international:
            try context.fetch(FetchDescriptor<InternationalLotteryEntry>(predicate: #Predicate { !$0.isDraw })))
    }
    static func removeModels(keys: Set<String>, context: ModelContext) throws {
        for entry in try context.fetch(FetchDescriptor<Result>()) {
            if let row = WeeklyLotteryReport.rows(lotto: [entry], international: []).first, keys.contains(row.id) { context.delete(entry) }
        }
        for entry in try context.fetch(FetchDescriptor<InternationalLotteryEntry>(predicate: #Predicate { !$0.isDraw })) {
            if let row = WeeklyLotteryReport.rows(lotto: [], international: [entry]).first, keys.contains(row.id) { context.delete(entry) }
        }
    }
    static func insert(_ row: LotteryReportRow, context: ModelContext) {
        if row.game == .lotto {
            let n = row.mainNumbers.sorted()
            context.insert(Result(dato: row.date, nr1: n[0], nr2: n[1], nr3: n[2], nr4: n[3], nr5: n[4], nr6: n[5], nr7: n[6], weekNr: LottoDateSupport.weekNumber(for: row.date)))
        } else if let game = InternationalGame(rawValue: row.game.rawValue) {
            context.insert(InternationalLotteryEntry(game: game, isDraw: false, date: row.date, main: row.mainNumbers.sorted(), extra: row.extraNumbers.sorted()))
        }
    }
    static func replace(_ original: LotteryReportRow, with replacement: LotteryReportRow, context: ModelContext) throws {
        guard AutomaticLotteryLedger.valid(game: replacement.game, date: replacement.date, main: replacement.mainNumbers, extra: replacement.extraNumbers) else {
            throw LottoBackupValidationError.invalid("Kontroller tall, antall tall og trekningsdato.")
        }
        guard original.id != replacement.id else { return }
        let own = try ownRows(context: context)
        let changes = try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record)
        let delivered = LotteryDeliverySync.latest(changes)
        guard !own.contains(where: { $0.id == replacement.id }), delivered[replacement.id]?.registered != true else {
            throw LotteryOwnRowStore.SaveError.duplicate
        }
        do {
            try removeModels(keys: [original.id], context: context)
            insert(replacement, context: context)
            // Explicit correction replaces the old delivered row, rather than doubling expenses.
            try LotteryDeliverySync.stage(false, keys: [original.id], context: context)
            if delivered[original.id]?.registered == true {
                try LotteryDeliverySync.stage(true, keys: [replacement.id], context: context)
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    static func delete(_ rows: [LotteryReportRow], removeDelivery: Bool, context: ModelContext) throws {
        let keys = Set(rows.map(\.id))
        do {
            try removeModels(keys: keys, context: context)
            if removeDelivery { try LotteryDeliverySync.stage(false, keys: keys, context: context) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    /// Replace a complete saved system. Shared component rows retain their other memberships.
    static func replaceSystem(_ original: LotterySystemSelection, game: LotteryReportGame, main: [Int], extra: [Int], date: Date,
                              removeOldDelivery: Bool, context: ModelContext, defaults: UserDefaults = .standard) throws {
        if let error = LotterySystem.validation(game: game, main: main, extra: extra, date: date) { throw LottoBackupValidationError.invalid(error) }
        let replacement = LotterySystemSelection(gameID: game.rawValue, dateText: LotteryCalendar.text(date), main: main.sorted(), extra: extra.sorted())
        guard replacement.id != original.id else { return }
        do {
            try detachSystem(original, removeDelivery: removeOldDelivery, context: context)
            // saveSystem commits the detached old system and the replacement together.
            _ = try LotterySystem.saveSystem(game: game, main: main, extra: extra, date: date, context: context)
            updateRemembered(original, replacement: replacement, defaults: defaults)
        } catch { context.rollback(); throw error }
    }
    static func deleteSystem(_ system: LotterySystemSelection, removeDelivery: Bool, context: ModelContext, defaults: UserDefaults = .standard) throws {
        do { try detachSystem(system, removeDelivery: removeDelivery, context: context); try context.save(); updateRemembered(system, replacement: nil, defaults: defaults) }
        catch { context.rollback(); throw error }
    }
    private static func updateRemembered(_ original: LotterySystemSelection, replacement: LotterySystemSelection?, defaults: UserDefaults) {
        let key = "system.lastSelections.v1"
        let previous = LotterySystemSelection.decode(defaults.string(forKey: key))
        guard previous.contains(original) else { return }
        defaults.set(LotterySystemSelection.encode(previous.filter { $0.id != original.id } + (replacement.map { [$0] } ?? [])) ?? "", forKey: key)
    }
    private static func detachSystem(_ system: LotterySystemSelection, removeDelivery: Bool, context: ModelContext) throws {
        var removed = Set<String>()
        for entry in try context.fetch(FetchDescriptor<Result>()) {
            let groups = LotterySystemSelection.decode(entry.systemMembershipJSON)
            guard groups.contains(system) else { continue }
            let remaining = groups.filter { $0 != system }
            if remaining.isEmpty {
                if let row = WeeklyLotteryReport.rows(lotto: [entry], international: []).first { removed.insert(row.id) }
                context.delete(entry)
            } else { entry.systemMembershipJSON = LotterySystemSelection.encode(remaining) }
        }
        for entry in try context.fetch(FetchDescriptor<InternationalLotteryEntry>(predicate: #Predicate { !$0.isDraw })) {
            let groups = LotterySystemSelection.decode(entry.systemMembershipJSON)
            guard groups.contains(system) else { continue }
            let remaining = groups.filter { $0 != system }
            if remaining.isEmpty {
                if let row = WeeklyLotteryReport.rows(lotto: [], international: [entry]).first { removed.insert(row.id) }
                context.delete(entry)
            } else { entry.systemMembershipJSON = LotterySystemSelection.encode(remaining) }
        }
        if removeDelivery { try LotteryDeliverySync.stage(false, keys: removed, context: context) }
    }
}
