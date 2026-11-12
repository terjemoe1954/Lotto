import Foundation
import SwiftData

struct LottoBackupImportResult {
    var added = 0
    var conflicts = 0
}

enum LottoBackupValidationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return "Backupen kan ikke brukes: \(reason)" }
    }
}

/// The settings UI and integration tests use the same snapshot/restore implementation.
@MainActor
enum LottoBackupStore {
    static func snapshot(context: ModelContext, content: LottoBackupContent,
                         settings: LottoBackupSettings) throws -> LottoBackupSnapshot {
        let all = content == .everything
        return LottoBackupSnapshot(content: content, exportedAt: .now, settings: settings,
            jackpots: try context.fetch(FetchDescriptor<JackPot>(sortBy: [SortDescriptor(\.dato)])).map(LottoBackupJackpot.init),
            results: all ? try context.fetch(FetchDescriptor<Result>(sortBy: [SortDescriptor(\.dato)])).map(LottoBackupResult.init) : [],
            internationalEntries: try context.fetch(FetchDescriptor<InternationalLotteryEntry>())
                .filter { all || $0.isDraw }.map(\.archiveRecord),
            deliveryChanges: all ? LotteryDeliverySync.latest(try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
                .values.sorted { $0.rowKey < $1.rowKey } : nil,
            favorites: all ? LotteryFavorites.latest(try context.fetch(FetchDescriptor<LotteryFavoriteChange>()).map(\.record)).values.sorted { $0.gameID < $1.gameID } : nil,
            ledger: all ? try context.fetch(FetchDescriptor<LotteryLedgerEntry>()).map(\.record) : nil)
    }

    static func restoreEverything(_ snapshot: LottoBackupSnapshot, context: ModelContext) throws {
        guard snapshot.content == .everything else { throw LottoBackupValidationError.invalid("Filen inneholder bare trekninger.") }
        try validate(snapshot, includePersonal: true)
        let snapshot = LotteryOwnRowStore.uniqueOwnRows(in: snapshot)
        let international = try snapshot.internationalEntries?.map { try $0.validatedModel() }
        do {
            // Individual deletes remain pending until the final save; a failure can roll back the replacement.
            if let international {
                for entry in try context.fetch(FetchDescriptor<InternationalLotteryEntry>()) { context.delete(entry) }
                for entry in international { context.insert(entry) }
            }
            for entry in try context.fetch(FetchDescriptor<JackPot>()) { context.delete(entry) }
            for entry in try context.fetch(FetchDescriptor<Result>()) { context.delete(entry) }
            for jackpot in snapshot.jackpots { context.insert(jackpot.makeModel()) }
            for result in snapshot.results { context.insert(result.makeModel()) }
            if let changes = snapshot.deliveryChanges {
                try LotteryDeliverySync.restore(changes, context: context)
            } else if snapshot.settings.weeklyRegisteredRows != nil || snapshot.settings.lottoTransferredRows != nil {
                let rows = WeeklyLotteryReport.rows(lotto: try context.fetch(FetchDescriptor<Result>()),
                    international: try context.fetch(FetchDescriptor<InternationalLotteryEntry>()))
                let marked = WeeklyLotteryDelivery.applying(rows,
                    registered: WeeklyLotteryDelivery.keys(snapshot.settings.weeklyRegisteredRows ?? ""),
                    legacy: WeeklyLotteryDelivery.keys(snapshot.settings.lottoTransferredRows ?? ""))
                let records = marked.filter(\.isRegistered).map {
                    LotteryDeliveryRecord(rowKey: $0.id, registered: true, changedAt: .now, changeID: UUID().uuidString)
                }
                try LotteryDeliverySync.restore(records, context: context)
            }
            if let favorites = snapshot.favorites { try LotteryFavorites.restore(favorites, context: context) }
            if let ledger = snapshot.ledger {
                for entry in try context.fetch(FetchDescriptor<LotteryLedgerEntry>()) { context.delete(entry) }
                for record in ledger { context.insert(LotteryLedgerEntry(record: record)) }
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }

    static func importDraws(_ snapshot: LottoBackupSnapshot, context: ModelContext) throws -> LottoBackupImportResult {
        try validate(snapshot, includePersonal: false)
        let models = try (snapshot.internationalEntries ?? []).filter(\.isDraw).map { try $0.validatedModel() }
        let existing = try context.fetch(FetchDescriptor<InternationalLotteryEntry>()).filter(\.isDraw)
        var byDate = Dictionary(grouping: existing, by: { "\($0.gameID)|\(LotteryCalendar.text($0.date))" })
        let plan = LottoRules.jackpotImportPlan(bundledJackpots: snapshot.jackpots.map { $0.makeModel() },
                                              existingJackpots: try context.fetch(FetchDescriptor<JackPot>()))
        var result = LottoBackupImportResult(added: plan.missing.count, conflicts: plan.conflicts.count)
        do {
            for entry in models {
                let key = "\(entry.gameID)|\(LotteryCalendar.text(entry.date))"
                if let stored = byDate[key] {
                    if stored.contains(where: { $0.mainNumbers.sorted() != entry.mainNumbers || $0.extraNumbers.sorted() != entry.extraNumbers }) {
                        result.conflicts += 1
                    }
                } else {
                    context.insert(entry)
                    byDate[key] = [entry]
                    result.added += 1
                }
            }
            for entry in plan.missing { context.insert(entry) }
            if result.added > 0 { try context.save() }
            return result
        } catch { context.rollback(); throw error }
    }

    private static func validate(_ snapshot: LottoBackupSnapshot, includePersonal: Bool) throws {
        for row in snapshot.jackpots {
            let values = [row.nr1,row.nr2,row.nr3,row.nr4,row.nr5,row.nr6,row.nr7,row.nr8]
            guard values.allSatisfy(LottoRules.validNumberRange.contains), Set(values).count == 8,
                  row.dato.timeIntervalSince1970.isFinite, row.dato.isSaturday else {
                throw LottoBackupValidationError.invalid("En Lotto-trekning har ugyldige tall eller dato.")
            }
        }
        for row in snapshot.internationalEntries ?? [] where includePersonal || row.isDraw {
            _ = try row.validatedModel()
        }
        guard includePersonal else { return }
        guard snapshot.settings.tolerance.isFinite, snapshot.settings.tolerance >= 0 else {
            throw LottoBackupValidationError.invalid("Toleransen er ugyldig.")
        }
        for row in snapshot.results {
            // A backup must preserve previously saved rows, including legacy typing mistakes.
            // Current row entry still uses LottoRules; historical range/day issues are warnings.
            guard row.dato.timeIntervalSince1970.isFinite else {
                throw LottoBackupValidationError.invalid("En egen Lotto-rekke har en dato som ikke kan leses.")
            }
        }
        for record in snapshot.favorites ?? [] {
            guard let game = LotteryReportGame(rawValue: record.gameID), record.changedAt.timeIntervalSince1970.isFinite,
                  !record.changeID.isEmpty, record.selection.validation(for: game) == nil else {
                throw LottoBackupValidationError.invalid("Favoritttallene er ugyldige.")
            }
        }
        for record in snapshot.ledger ?? [] {
            guard record.isValid else { throw LottoBackupValidationError.invalid("Spilleoversikten har ugyldige beløp eller dato.") }
        }
        guard Set((snapshot.ledger ?? []).map(\.id)).count == (snapshot.ledger ?? []).count else {
            throw LottoBackupValidationError.invalid("Spilleoversikten har dupliserte poster.")
        }
        for change in snapshot.deliveryChanges ?? [] {
            guard !change.rowKey.isEmpty, !change.changeID.isEmpty, change.changedAt.timeIntervalSince1970.isFinite else {
                throw LottoBackupValidationError.invalid("En registreringsmarkering er ugyldig.")
            }
        }
    }
}

struct LottoBackupCheckResult {
    let lottoRows: Int
    let vikingRows: Int
    let euroRows: Int
    let drawCount: Int
    let registeredRows: Int
    var warnings: [String] = []
    var duplicateRowsSkipped = 0
    var message: String {
        var summary = "Backupfilen ble lest og prøvegjenopprettet.\n\nLotto: \(lottoRows) egne rekker\nVikinglotto: \(vikingRows) egne rekker\nEurojackpot: \(euroRows) egne rekker\nTrekninger: \(drawCount)\nRegistrerte rekker: \(registeredRows)"
        if duplicateRowsSkipped > 0 { summary += "\n\n\(duplicateRowsSkipped) ekstra kopier av egne rekker hoppes over ved gjenoppretting. Backupfilen endres ikke." }
        guard !warnings.isEmpty else { return summary }
        let notice = warnings.count == 1 ? "Varsel: Én eldre rekke har tall eller dato som bør kontrolleres. Den er bevart uendret." : "Varsel: \(warnings.count) eldre rekker har tall eller dato som bør kontrolleres. De er bevart uendret."
        return summary + "\n\n" + notice + "\n" + warnings.prefix(3).joined(separator: "\n") + (warnings.count > 3 ? "\nFlere varsler: \(warnings.count - 3)." : "")
    }
}

extension LottoBackupStore {
    /// Reads the selected file into an independent local database; never uses the app's live context.
    static func check(_ snapshot: LottoBackupSnapshot) throws -> LottoBackupCheckResult {
        try validate(snapshot, includePersonal: snapshot.content == .everything)
        let originalOwnCount = snapshot.results.count + (snapshot.internationalEntries ?? []).filter { !$0.isDraw }.count
        let snapshot = LotteryOwnRowStore.uniqueOwnRows(in: snapshot)
        let skipped = originalOwnCount - snapshot.results.count - (snapshot.internationalEntries ?? []).filter { !$0.isDraw }.count
        let container = try ModelContainer(for: JackPot.self, Result.self, InternationalLotteryEntry.self, LotteryDeliveryChange.self, LotteryFavoriteChange.self, LotteryLedgerEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        if snapshot.content == .drawsOnly {
            let imported = try importDraws(snapshot, context: context)
            guard imported.conflicts == 0 else { throw LottoBackupValidationError.invalid("Filen inneholder ulike resultater på samme dato.") }
        } else {
            try restoreEverything(snapshot, context: context)
            let restored = try self.snapshot(context: context, content: .everything, settings: snapshot.settings)
            guard try signatures(restored.jackpots) == signatures(snapshot.jackpots),
                  try signatures(restored.results) == signatures(snapshot.results) else {
                throw LottoBackupValidationError.invalid("Lotto-dataene stemte ikke etter prøvegjenoppretting.")
            }
            let expectedInternational = try (snapshot.internationalEntries ?? []).map { try $0.validatedModel().archiveRecord }
            guard try signatures(restored.internationalEntries ?? []) == signatures(expectedInternational) else {
                throw LottoBackupValidationError.invalid("Vikinglotto/Eurojackpot-dataene stemte ikke etter prøvegjenoppretting.")
            }
            let rows = WeeklyLotteryReport.rows(lotto: snapshot.results.map { $0.makeModel() },
                international: try (snapshot.internationalEntries ?? []).map { try $0.validatedModel() })
            let expected = snapshot.deliveryChanges.map { LotteryDeliverySync.applying(rows, records: $0) }
                ?? WeeklyLotteryDelivery.applying(rows,
                    registered: WeeklyLotteryDelivery.keys(snapshot.settings.weeklyRegisteredRows ?? ""),
                    legacy: WeeklyLotteryDelivery.keys(snapshot.settings.lottoTransferredRows ?? ""))
            let actual = LotteryDeliverySync.applying(rows, records: restored.deliveryChanges ?? [])
            guard expected.map(\.isRegistered) == actual.map(\.isRegistered) else {
                throw LottoBackupValidationError.invalid("Registreringsmarkeringene stemte ikke etter prøvegjenoppretting.")
            }
            if let favorites = snapshot.favorites {
                let desired = LotteryFavorites.latest(favorites)
                let actual = LotteryFavorites.latest(restored.favorites ?? [])
                for game in LotteryReportGame.allCases {
                    let expected = desired[game.rawValue]?.selection ?? LotteryFavoriteSelection()
                    guard (actual[game.rawValue]?.selection ?? LotteryFavoriteSelection()) == expected else {
                        throw LottoBackupValidationError.invalid("Favoritttallene stemte ikke etter prøvegjenoppretting.")
                    }
                }
            }
            if let ledger = snapshot.ledger {
                guard try signatures(restored.ledger ?? []) == signatures(ledger) else {
                    throw LottoBackupValidationError.invalid("Spilleoversikten stemte ikke etter prøvegjenoppretting.")
                }
            }
            // Removed marks must also survive, even when they refer to a row no longer in the backup.
            if let changes = snapshot.deliveryChanges {
                let state = LotteryDeliverySync.latest(restored.deliveryChanges ?? [])
                for (key, change) in LotteryDeliverySync.latest(changes) where state[key]?.registered != change.registered {
                    throw LottoBackupValidationError.invalid("En fjernet avhuking ble ikke bevart.")
                }
            }
        }
        let national = try context.fetch(FetchDescriptor<Result>())
        let international = try context.fetch(FetchDescriptor<InternationalLotteryEntry>())
        let rows = LotteryDeliverySync.applying(WeeklyLotteryReport.rows(lotto: national, international: international),
            records: try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
        return LottoBackupCheckResult(lottoRows: national.count,
            vikingRows: international.filter { !$0.isDraw && $0.gameID == InternationalGame.vikinglotto.rawValue }.count,
            euroRows: international.filter { !$0.isDraw && $0.gameID == InternationalGame.eurojackpot.rawValue }.count,
            drawCount: try context.fetchCount(FetchDescriptor<JackPot>()) + international.filter(\.isDraw).count,
            registeredRows: rows.filter(\.isRegistered).count,
            warnings: snapshot.content == .everything ? personalRowWarnings(snapshot) : [],
            duplicateRowsSkipped: skipped)
    }
    static func personalRowWarnings(_ snapshot: LottoBackupSnapshot) -> [String] {
        snapshot.results.enumerated().compactMap { index, row in
            guard row.dato.timeIntervalSince1970.isFinite else { return nil }
            let numbers = [row.nr1,row.nr2,row.nr3,row.nr4,row.nr5,row.nr6,row.nr7]
            guard let reason = LottoRules.rowValidationMessage(numbers: numbers, drawDate: row.dato) else { return nil }
            return "Rekke \(index + 1), \(WeeklyLotteryReport.dateText(row.dato)): \(numbers.map(String.init).joined(separator: ", ")). \(reason)"
        }
    }
    private static func signatures<T: Encodable>(_ values: [T]) throws -> [String] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try values.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.sorted()
    }
}
