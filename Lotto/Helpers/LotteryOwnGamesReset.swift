import Foundation
import SwiftData

/// Reset uses individual CloudKit-tracked deletions and newer delivery tombstones.
/// A checked backup must still match the local database at the final confirmation.
@MainActor enum LotteryOwnGamesReset {
    struct Prepared {
        let backupURL: URL
        let ownRows: Int
        let ledgerEntries: Int
        fileprivate let state: Data
    }
    enum Failure: LocalizedError {
        case pending, changed, backup
        var errorDescription: String? {
            switch self {
            case .pending: "Vent til andre endringer er lagret, og lag deretter backup på nytt."
            case .changed: "Dataene er endret siden backupen ble laget, for eksempel via iCloud. Lag og kontroller en ny backup før nullstilling."
            case .backup: "Backupfilen mangler eller er endret. Ingenting er nullstilt. Lag en ny backup."
            }
        }
    }
    static func prepare(context: ModelContext, settings: LottoBackupSettings,
                        backupDirectory: URL = URL.documentsDirectory.appendingPathComponent("Lotto-backups", isDirectory: true)) throws -> Prepared {
        guard !context.hasChanges else { throw Failure.pending }
        let snapshot = try LottoBackupStore.snapshot(context: context, content: .everything, settings: settings)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let url = backupDirectory.appendingPathComponent("Lotto-for-nullstilling-\(UUID().uuidString).json")
        try bytes.write(to: url, options: .atomic)
        let saved = try Data(contentsOf: url)
        guard saved == bytes else { throw Failure.backup }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        _ = try LottoBackupStore.check(decoder.decode(LottoBackupSnapshot.self, from: saved))
        return Prepared(backupURL: url,
                        ownRows: snapshot.results.count + (snapshot.internationalEntries ?? []).filter { !$0.isDraw }.count,
                        ledgerEntries: snapshot.ledger?.count ?? 0,
                        state: try canonical(snapshot))
    }
    static func reset(_ prepared: Prepared, context: ModelContext, settings: LottoBackupSettings,
                      defaults: UserDefaults = .standard) throws {
        guard !context.hasChanges else { throw Failure.pending }
        let current = try LottoBackupStore.snapshot(context: context, content: .everything, settings: settings)
        guard try canonical(current) == prepared.state else { throw Failure.changed }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(LottoBackupSnapshot.self, from: Data(contentsOf: prepared.backupURL))
            guard try canonical(backup) == prepared.state else { throw Failure.backup }
            _ = try LottoBackupStore.check(backup)
        } catch { throw Failure.backup }
        do {
            // Keep false events: old Levert marks arriving from another device must not win.
            try LotteryDeliverySync.restore([], context: context)
            for row in try context.fetch(FetchDescriptor<Result>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<InternationalLotteryEntry>()) where !row.isDraw { context.delete(row) }
            for entry in try context.fetch(FetchDescriptor<LotteryLedgerEntry>()) { context.delete(entry) }
            try context.save()
        } catch { context.rollback(); throw error }
        defaults.removeObject(forKey: WeeklyLotteryDelivery.storageKey)
        defaults.removeObject(forKey: "transferredResultKeys")
        defaults.removeObject(forKey: "system.lastSelections.v1")
    }
    private static func canonical(_ snapshot: LottoBackupSnapshot) throws -> Data {
        // Ignore export time and database fetch order, but compare every backed-up value.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as! [String: Any]
        object.removeValue(forKey: "exportedAt")
        for key in ["jackpots", "results", "internationalEntries", "deliveryChanges", "favorites", "ledger"] {
            if let records = object[key] as? [[String: Any]] {
                let encoded = try records.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                object[key] = try encoded.sorted { $0.lexicographicallyPrecedes($1) }.map { try JSONSerialization.jsonObject(with: $0) }
            }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
