import Foundation
import Observation

/// Derived from the synced delivery log, never inserted as manual ledger entries.
/// This avoids duplicate expenses when two devices calculate the same row.
struct AutomaticLotteryLedgerItem: Identifiable {
    let row: LotteryReportRow
    let prizeOre: Int?
    var id: String { "automatic|" + row.id }
    var record: LotteryLedgerRecord {
        LotteryLedgerRecord(id: id, gameID: row.game.rawValue, date: row.date,
                            stakeOre: AutomaticLotteryLedger.priceOre(row.game), prizeOre: prizeOre ?? 0, note: "Automatisk fra Levert")
    }
}

struct LotteryPrizeTable: Codable, Equatable {
    let gameID: String
    let date: Date
    let main: [Int]
    let extra: [Int]
    /// Only actual per-winning-row amounts. A rolled-over jackpot is absent, not zero.
    let payouts: [Int: Int]
    var key: String { gameID + "|" + LotteryCalendar.text(date) }
}

enum AutomaticLotteryLedger {
    // Ordinary single-row prices, verified against Norsk Tipping's rules November 2026.
    static func priceOre(_ game: LotteryReportGame) -> Int {
        switch game { case .lotto: return 500; case .vikinglotto: return 800; case .eurojackpot: return 2500 }
    }

    /// Keys contain the complete played row, so deleting a saved suggestion does not erase expenses.
    static func deliveredRows(_ changes: [LotteryDeliveryRecord]) -> [LotteryReportRow] {
        WeeklyLotteryReport.normalized(LotteryDeliverySync.latest(changes).values.filter(\.registered).compactMap { parse($0.rowKey) })
    }

    static func parse(_ key: String) -> LotteryReportRow? {
        let parts = key.components(separatedBy: "|")
        guard parts.count == 4, let game = LotteryReportGame(rawValue: parts[0]),
              let date = LotteryCalendar.date(parts[1]), LotteryCalendar.text(date) == parts[1],
              date >= LotteryCalendar.archiveStart,
              let main = try? JSONDecoder().decode([Int].self, from: Data(parts[2].utf8)),
              let extra = try? JSONDecoder().decode([Int].self, from: Data(parts[3].utf8)),
              valid(game: game, date: date, main: main, extra: extra) else { return nil }
        return LotteryReportRow(game: game, date: date, mainNumbers: main, extraNumbers: extra, isRegistered: true)
    }

    static func valid(game: LotteryReportGame, date: Date, main: [Int], extra: [Int], draw: Bool = false) -> Bool {
        if game == .lotto {
            let numbers = main + extra
            return main.count == 7 && extra.count == (draw ? 1 : 0) && Set(numbers).count == numbers.count &&
                numbers.allSatisfy { (1...34).contains($0) } && LotteryCalendar.calendar.component(.weekday, from: date) == 7
        }
        return InternationalGame(rawValue: game.rawValue)?.validation(main: main, extra: extra, date: date) == nil
    }

    static func tier(game: LotteryReportGame, main: Int, extra: Int) -> Int? {
        switch game {
        case .lotto:
            switch main { case 7: return 1; case 6: return extra == 1 ? 2 : 3; case 5: return 4; case 4: return 5; default: return nil }
        case .vikinglotto:
            switch main { case 6: return extra == 1 ? 1 : 2; case 5: return extra == 1 ? 3 : 4; case 4: return 5; case 3: return 6; default: return nil }
        case .eurojackpot:
            let groups = [(5,2),(5,1),(5,0),(4,2),(4,1),(3,2),(4,0),(2,2),(3,1),(3,0),(1,2),(2,1)]
            return groups.firstIndex { $0.0 == main && $0.1 == extra }.map { $0 + 1 }
        }
    }

    static func items(rows: [LotteryReportRow], tables: [LotteryPrizeTable]) -> [AutomaticLotteryLedgerItem] {
        let byKey = Dictionary(tables.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        return WeeklyLotteryReport.normalized(rows).filter(\.isRegistered).map { row in
            guard let table = byKey[row.game.rawValue + "|" + LotteryCalendar.text(row.date)] else {
                return AutomaticLotteryLedgerItem(row: row, prizeOre: nil)
            }
            let main = Set(row.mainNumbers).intersection(table.main).count
            let extra = row.game == .lotto ? Set(row.mainNumbers).intersection(table.extra).count : Set(row.extraNumbers).intersection(table.extra).count
            let amount: Int?
            if let tier = tier(game: row.game, main: main, extra: extra) { amount = table.payouts[tier] }
            else { amount = 0 }
            return AutomaticLotteryLedgerItem(row: row, prizeOre: amount)
        }
    }
}

/// Public result data only; delivery marks and own numbers are never sent to the API.
enum LotteryPrizeAPI {
    private struct Response: Decodable { let gameResult: [Draw] }
    private struct Draw: Decodable {
        let drawDate: String
        let isFinalized: Bool
        let winnerNumber: [Number]
        let prize: [Prize]?
    }
    private struct Number: Decodable { let number: String; let type: Int }
    private struct Prize: Decodable { let id: Int; let name: String; let value: String; let winners: String }

    private static func payoutOre(_ text: String) -> Int? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty, parts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
              parts.count == 1 || (parts[1].count <= 2 && parts[1].allSatisfy({ $0.isASCII && $0.isNumber })),
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value <= 100_000_000_000 else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }

    static func decode(_ data: Data, game: LotteryReportGame) throws -> [LotteryPrizeTable] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return try response.gameResult.filter(\.isFinalized).map { draw in
            let main = draw.winnerNumber.filter { $0.type == 1 }.compactMap { Int($0.number) }.sorted()
            let extra = draw.winnerNumber.filter { $0.type == 2 }.compactMap { Int($0.number) }.sorted()
            guard let date = LotteryCalendar.date(String(draw.drawDate.prefix(10))),
                  LotteryCalendar.text(date) == String(draw.drawDate.prefix(10)),
                  AutomaticLotteryLedger.valid(game: game, date: date, main: main, extra: extra, draw: true) else {
                throw InternationalLotteryError.invalidDraw(String(draw.drawDate.prefix(10)))
            }
            let names: [String]
            switch game {
            case .lotto: names = ["7rette","6+1rette","6rette","5rette","4rette"]
            case .vikinglotto: names = ["6+1","6+0","5+1","5+0","4","3"]
            case .eurojackpot: names = ["5+2","5+1","5+0","4+2","4+1","3+2","4+0","2+2","3+1","3+0","1+2","2+1"]
            }
            var payouts: [Int: Int] = [:]
            for prize in draw.prize ?? [] {
                let name = prize.name.lowercased().filter { !$0.isWhitespace }
                guard (1...names.count).contains(prize.id), names[prize.id - 1] == name,
                      let winners = Int(prize.winners), winners > 0,
                      let ore = payoutOre(prize.value), ore > 0 else { continue }
                if let previous = payouts[prize.id], previous != ore { throw InternationalLotteryError.invalidResponse }
                payouts[prize.id] = ore
            }
            return LotteryPrizeTable(gameID: game.rawValue, date: date, main: main, extra: extra, payouts: payouts)
        }
    }

    static func fetch(game: LotteryReportGame, from: Date, to: Date, session: URLSession = .shared) async throws -> [LotteryPrizeTable] {
        let name = game == .eurojackpot ? "eurojackpot%20all" : game.rawValue
        var url = URLComponents(string: "https://api.norsk-tipping.no/LotteryGameInfo/v2/api/results/" + name)!
        url.queryItems = [URLQueryItem(name: "fromDate", value: LotteryCalendar.text(from)), URLQueryItem(name: "toDate", value: LotteryCalendar.text(to))]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InternationalLotteryError.invalidResponse }
        return try decode(data, game: game).filter { $0.date >= from && $0.date < to }
    }
}

@MainActor @Observable final class LotteryPrizeCache {
    static let shared = LotteryPrizeCache()
    private(set) var tables: [LotteryPrizeTable] = []
    private(set) var updating = false
    private(set) var error: String?
    private let file: URL
    init(file: URL = URL.applicationSupportDirectory.appendingPathComponent("lottery-prizes-v1.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode([LotteryPrizeTable].self, from: data) { tables = stored }
    }
    typealias Fetch = (LotteryReportGame, Date, Date) async throws -> [LotteryPrizeTable]
    func refresh(rows: [LotteryReportRow], now: Date = .now, fetch: Fetch = { try await LotteryPrizeAPI.fetch(game: $0, from: $1, to: $2) }) async {
        // A changed delivery log may start a new view task while the old one is cancelling.
        // Wait for that request to release the cache rather than dropping the new rows.
        while updating {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        updating = true; error = nil
        defer { updating = false }
        var byKey = Dictionary(tables.map { ($0.key,$0) }, uniquingKeysWith: { _, last in last })
        do {
            for game in LotteryReportGame.allCases {
                var dates = Set(rows.filter { $0.game == game && $0.date <= now }.map { LotteryCalendar.day($0.date) })
                while let first = dates.min() {
                    try Task.checkCancellation()
                    let stop = min(LotteryCalendar.calendar.date(byAdding: .day, value: 28, to: first)!,
                                   LotteryCalendar.calendar.date(byAdding: .day, value: 1, to: LotteryCalendar.day(now))!)
                    let fetched = try await fetch(game, first, stop)
                    for table in fetched { byKey[table.key] = table }
                    dates = dates.filter { $0 >= stop }
                    tables = byKey.values.sorted { $0.key < $1.key }
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(tables).write(to: file, options: .atomic)
                }
            }
        } catch is CancellationError { }
        catch { self.error = "Kunne ikke hente alle premier. Lagrede beløp er beholdt; resten står som venter. Prøv Oppdater premier igjen." }
    }
}
