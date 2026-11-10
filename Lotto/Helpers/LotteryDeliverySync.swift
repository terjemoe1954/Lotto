import Foundation
import SwiftData

/// Immutable changes allow concurrent CloudKit copies to converge, including an undone mark.
@Model
final class LotteryDeliveryChange {
    var rowKey: String = ""
    var registered: Bool = false
    var changedAt: Date = Date()
    var changeID: String = UUID().uuidString
    init(rowKey: String, registered: Bool, changedAt: Date = .now, changeID: String = UUID().uuidString) {
        self.rowKey = rowKey
        self.registered = registered
        self.changedAt = changedAt
        self.changeID = changeID
    }
    var record: LotteryDeliveryRecord {
        LotteryDeliveryRecord(rowKey: rowKey, registered: registered, changedAt: changedAt, changeID: changeID)
    }
}

nonisolated struct LotteryDeliveryRecord: Codable, Equatable, Sendable {
    let rowKey: String
    let registered: Bool
    let changedAt: Date
    let changeID: String
}

@MainActor
enum LotteryDeliverySync {
    static func latest(_ records: [LotteryDeliveryRecord]) -> [String: LotteryDeliveryRecord] {
        records.reduce(into: [:]) { result, record in
            guard !record.rowKey.isEmpty else { return }
            if let previous = result[record.rowKey],
               previous.changedAt > record.changedAt || (previous.changedAt == record.changedAt && previous.changeID >= record.changeID) { return }
            result[record.rowKey] = record
        }
    }
    static func applying(_ rows: [LotteryReportRow], records: [LotteryDeliveryRecord]) -> [LotteryReportRow] {
        let state = latest(records)
        return rows.map { row in
            var result = row
            result.isRegistered = state[row.id]?.registered ?? false
            return result
        }
    }
    static func set(_ registered: Bool, keys: Set<String>, context: ModelContext, now: Date = .now) throws {
        let existing = latest(try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
        for key in keys where !key.isEmpty {
            guard existing[key]?.registered != registered else { continue }
            let time = max(now, (existing[key]?.changedAt ?? .distantPast).addingTimeInterval(0.001))
            context.insert(LotteryDeliveryChange(rowKey: key, registered: registered, changedAt: time))
        }
        try context.save()
    }
    /// Legacy marks are older than any real user action, even when imported on a second device later.
    static func migrateLegacy(rows: [LotteryReportRow], context: ModelContext, defaults: UserDefaults = .standard) throws {
        let weekly = WeeklyLotteryDelivery.keys(defaults.string(forKey: WeeklyLotteryDelivery.storageKey) ?? "")
        let legacy = WeeklyLotteryDelivery.keys(defaults.string(forKey: "transferredResultKeys") ?? "")
        let positives = WeeklyLotteryDelivery.applying(rows, registered: weekly, legacy: legacy).filter(\.isRegistered)
        let known = latest(try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
        var added = Set<String>()
        for row in positives where known[row.id] == nil && added.insert(row.id).inserted {
            context.insert(LotteryDeliveryChange(rowKey: row.id, registered: true, changedAt: Date(timeIntervalSince1970: 0)))
        }
        if !added.isEmpty { try context.save() }
    }
    /// Restore is a new user action. Keep false changes so older remote marks cannot reappear.
    static func restore(_ backup: [LotteryDeliveryRecord], context: ModelContext, now: Date = .now) throws {
        let current = latest(try context.fetch(FetchDescriptor<LotteryDeliveryChange>()).map(\.record))
        let desired = latest(backup)
        for key in Set(current.keys).union(desired.keys) {
            let time = max(now, (current[key]?.changedAt ?? .distantPast).addingTimeInterval(0.001))
            context.insert(LotteryDeliveryChange(rowKey: key, registered: desired[key]?.registered ?? false, changedAt: time))
        }
        // Caller saves this with restored rows in the same ModelContext.
    }
}
