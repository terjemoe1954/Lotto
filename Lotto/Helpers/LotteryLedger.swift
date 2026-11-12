import Foundation
import SwiftData

nonisolated struct LotteryLedgerRecord: Codable, Equatable {
    var id: String
    var gameID: String
    var date: Date
    var stakeOre: Int
    var prizeOre: Int
    var note: String
    var isValid: Bool {
        ["lotto", "vikinglotto", "eurojackpot"].contains(gameID) && !id.isEmpty &&
        date.timeIntervalSince1970.isFinite && stakeOre >= 0 && prizeOre >= 0 &&
        stakeOre <= 100_000_000_000 && prizeOre <= 100_000_000_000 &&
        (stakeOre > 0 || prizeOre > 0)
    }
}

@Model final class LotteryLedgerEntry {
    var entryID: String = UUID().uuidString
    var gameID: String = "lotto"
    var date: Date = Date()
    var stakeOre: Int = 0
    var prizeOre: Int = 0
    var note: String = ""
    init(record: LotteryLedgerRecord) { apply(record) }
    func apply(_ value: LotteryLedgerRecord) {
        entryID = value.id; gameID = value.gameID; date = value.date
        stakeOre = value.stakeOre; prizeOre = value.prizeOre; note = value.note
    }
    var record: LotteryLedgerRecord {
        LotteryLedgerRecord(id: entryID, gameID: gameID, date: date, stakeOre: stakeOre, prizeOre: prizeOre, note: note)
    }
}

enum LotteryLedger {
    static func ore(_ text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty, parts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
              parts.count == 1 || (parts[1].count <= 2 && parts[1].allSatisfy({ $0.isASCII && $0.isNumber })),
              let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              amount >= 0, amount <= 1_000_000_000 else { return nil }
        return NSDecimalNumber(decimal: amount * 100).intValue
    }
    static func money(_ ore: Int) -> String {
        (Decimal(ore) / 100).formatted(.currency(code: "NOK").locale(Locale(identifier: "nb_NO")))
    }
    static func input(_ ore: Int) -> String { String(format: "%d,%02d", ore / 100, ore % 100) }
    static func totals(_ records: [LotteryLedgerRecord]) -> (stake: Int, prize: Int) {
        records.reduce((0,0)) { ($0.0 + $1.stakeOre, $0.1 + $1.prizeOre) }
    }
    static func shouldPause(stake: Int, budget: Int?) -> Bool { budget.map { stake >= $0 && $0 > 0 } ?? false }
}
