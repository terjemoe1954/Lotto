import Foundation

/// Primitive, optional metadata travels with each constituent row through CloudKit
/// and existing backups. Older rows/backups simply have no system label.
nonisolated struct LotterySystemSelection: Codable, Hashable, Identifiable, Sendable {
    let gameID: String
    let dateText: String
    let main: [Int]
    let extra: [Int]
    var id: String { "\(gameID)|\(dateText)|\(main)|\(extra)" }
    var numbersText: String {
        main.map(String.init).joined(separator: " · ") + (extra.isEmpty ? "" : " + " + extra.map(String.init).joined(separator: " · "))
    }
    static func decode(_ text: String?) -> [Self] {
        guard let text, let bytes = text.data(using: .utf8) else { return [] }
        let records = (try? JSONDecoder().decode([Self].self, from: bytes)) ?? []
        return records.filter { record in
            let minimum = record.gameID == "lotto" ? 7 : (record.gameID == "vikinglotto" ? 6 : 5)
            let minExtra = record.gameID == "lotto" ? 0 : (record.gameID == "vikinglotto" ? 1 : 2)
            let maxMain = record.gameID == "eurojackpot" ? 10 : 12
            let maxNumber = record.gameID == "lotto" ? 34 : (record.gameID == "vikinglotto" ? 48 : 50)
            let maxExtra = record.gameID == "lotto" ? 0 : (record.gameID == "vikinglotto" ? 5 : 12)
            return ["lotto", "vikinglotto", "eurojackpot"].contains(record.gameID)
                && (minimum...maxMain).contains(record.main.count)
                && (minExtra...maxExtra).contains(record.extra.count)
                && (record.main.count > minimum || record.extra.count > minExtra)
                && Set(record.main).count == record.main.count && Set(record.extra).count == record.extra.count
                && record.main.allSatisfy { (1...maxNumber).contains($0) }
                && record.extra.allSatisfy { $0 >= 1 && $0 <= maxExtra }
                && record.main == record.main.sorted() && record.extra == record.extra.sorted()
                && record.dateText.count == 10
        }
    }
    static func encode(_ records: [Self]) -> String? {
        let unique = Array(Set(records)).sorted { $0.id < $1.id }
        guard !unique.isEmpty else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(unique) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func merging(_ a: String?, _ b: String?) -> String? { encode(decode(a) + decode(b)) }
}
