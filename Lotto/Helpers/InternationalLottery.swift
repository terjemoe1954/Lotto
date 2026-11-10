import Foundation
import SwiftData

/// Separate pools: the same value may occur in both main and extra numbers.
enum InternationalGame: String, CaseIterable, Codable, Identifiable {
    case vikinglotto, eurojackpot
    var id: String { rawValue }
    var title: String { self == .vikinglotto ? "Vikinglotto" : "Eurojackpot" }
    var mainCount: Int { self == .vikinglotto ? 6 : 5 }
    var mainMaximum: Int { self == .vikinglotto ? 48 : 50 }
    var extraCount: Int { self == .vikinglotto ? 1 : 2 }
    var extraMaximum: Int { self == .vikinglotto ? 5 : 12 }
    var extraTitle: String { self == .vikinglotto ? "Vikingtall" : "Stjernetall" }
    var weekdays: Set<Int> { self == .vikinglotto ? [4] : [3, 6] }
    var schedule: String { self == .vikinglotto ? "onsdag" : "tirsdag og fredag" }
    var apiName: String { self == .vikinglotto ? "vikinglotto" : "eurojackpot all" }

    func validation(main: [Int], extra: [Int], date: Date) -> String? {
        guard main.count == mainCount, Set(main).count == mainCount,
              main.allSatisfy({ (1...mainMaximum).contains($0) }) else {
            return "Velg \(mainCount) ulike hovedtall mellom 1 og \(mainMaximum)."
        }
        guard extra.count == extraCount, Set(extra).count == extraCount,
              extra.allSatisfy({ (1...extraMaximum).contains($0) }) else {
            return "Velg \(extraCount) ulike \(extraTitle.lowercased()) mellom 1 og \(extraMaximum)."
        }
        guard weekdays.contains(LotteryCalendar.calendar.component(.weekday, from: date)) else {
            return "Trekningsdagen for \(title) er \(schedule)."
        }
        return nil
    }

    func nextDraw(onOrAfter date: Date) -> Date {
        let start = LotteryCalendar.day(date)
        return (0...7).compactMap { LotteryCalendar.calendar.date(byAdding: .day, value: $0, to: start) }
            .first { weekdays.contains(LotteryCalendar.calendar.component(.weekday, from: $0)) } ?? start
    }
}

enum LotteryCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }
    static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func text(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func date(_ text: String) -> Date? {
        let pieces = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    }
    static var archiveStart: Date { date("2023-01-01")! }
}

/// Additive model: existing Lotto models and their CloudKit records stay intact.
@Model
final class InternationalLotteryEntry {
    var gameID: String = ""
    var isDraw: Bool = false
    var date: Date = Date()
    var mainNumbers: [Int] = []
    var extraNumbers: [Int] = []

    init(game: InternationalGame, isDraw: Bool, date: Date, main: [Int], extra: [Int]) {
        self.gameID = game.rawValue
        self.isDraw = isDraw
        self.date = LotteryCalendar.day(date)
        self.mainNumbers = main.sorted()
        self.extraNumbers = extra.sorted()
    }
    var numbersText: String {
        mainNumbers.map(String.init).joined(separator: " – ") + "  +  " + extraNumbers.map(String.init).joined(separator: " – ")
    }
    var archiveRecord: InternationalLotteryRecord {
        InternationalLotteryRecord(gameID: gameID, isDraw: isDraw, date: date, mainNumbers: mainNumbers, extraNumbers: extraNumbers)
    }
}

nonisolated struct InternationalLotteryRecord: Codable, Equatable, Sendable {
    var gameID: String
    var isDraw: Bool
    var date: Date
    var mainNumbers: [Int]
    var extraNumbers: [Int]

    @MainActor var key: String {
        "\(gameID)|\(isDraw)|\(LotteryCalendar.text(date))|\(mainNumbers.sorted())|\(extraNumbers.sorted())"
    }
    @MainActor func validatedModel() throws -> InternationalLotteryEntry {
        guard let game = InternationalGame(rawValue: gameID),
              game.validation(main: mainNumbers, extra: extraNumbers, date: date) == nil else {
            throw InternationalLotteryError.invalidDraw(LotteryCalendar.text(date))
        }
        return InternationalLotteryEntry(game: game, isDraw: isDraw, date: date, main: mainNumbers, extra: extraNumbers)
    }
}

enum InternationalLotteryError: LocalizedError {
    case invalidResponse, invalidDraw(String), conflict(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Resultattjenesten svarte ikke som forventet. Prøv igjen senere."
        case .invalidDraw(let date): return "Ugyldige tall i trekningen \(date). Ingen data fra denne forespørselen ble lagret."
        case .conflict(let date): return "Ulike resultater for \(date). Eksisterende trekning ble beholdt."
        }
    }
}

@MainActor
enum InternationalLotteryUpdater {
    private struct Response: Decodable { let gameResult: [Draw] }
    private struct Draw: Decodable {
        let drawDate: String
        let winnerNumber: [Number]
        let isFinalized: Bool
    }
    private struct Number: Decodable { let number: String; let type: Int }

    static func decode(_ data: Data, game: InternationalGame) throws -> [InternationalLotteryRecord] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return try response.gameResult.filter(\.isFinalized).map { draw in
            let main = draw.winnerNumber.filter { $0.type == 1 }.compactMap { Int($0.number) }.sorted()
            let extra = draw.winnerNumber.filter { $0.type == 2 }.compactMap { Int($0.number) }.sorted()
            guard let date = LotteryCalendar.date(draw.drawDate),
                  game.validation(main: main, extra: extra, date: date) == nil else {
                throw InternationalLotteryError.invalidDraw(String(draw.drawDate.prefix(10)))
            }
            return InternationalLotteryRecord(gameID: game.rawValue, isDraw: true, date: date, mainNumbers: main, extraNumbers: extra)
        }
    }

    /// Each successful window is saved, so an interrupted initial import resumes safely.
    static func update(game: InternationalGame, context: ModelContext,
                       progress: (String) -> Void) async throws -> Int {
        var added = 0
        let existing = try context.fetch(FetchDescriptor<InternationalLotteryEntry>())
        var byDate = Dictionary(grouping: existing.filter { $0.gameID == game.rawValue && $0.isDraw },
                               by: { LotteryCalendar.text($0.date) })
        // Recheck the last week to catch delayed finalization and corrections.
        // Without any archive, import from 2023 in resumable windows.
        let latest = existing.filter { $0.gameID == game.rawValue && $0.isDraw }.map(\.date).max()
        var start = latest.map { max(LotteryCalendar.archiveStart, LotteryCalendar.calendar.date(byAdding: .day, value: -7, to: $0)!) } ?? LotteryCalendar.archiveStart
        let end = LotteryCalendar.day(.now)
        while start <= end {
            try Task.checkCancellation()
            let stop = min(LotteryCalendar.calendar.date(byAdding: .day, value: 28, to: start)!,
                           LotteryCalendar.calendar.date(byAdding: .day, value: 1, to: end)!)
            progress("Henter \(game.title): \(LotteryCalendar.text(start))")
            var url = URLComponents(string: "https://api.norsk-tipping.no/LotteryGameInfo/v2/api/results/\(game.apiName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
            url.queryItems = [URLQueryItem(name: "fromDate", value: LotteryCalendar.text(start)),
                              URLQueryItem(name: "toDate", value: LotteryCalendar.text(stop))]
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw InternationalLotteryError.invalidResponse
            }
            let records = try decode(data, game: game).filter { $0.date >= start && $0.date < stop }
            // Validate conflicts before inserting any record in this window.
            for record in records {
                if let stored = byDate[LotteryCalendar.text(record.date)],
                   stored.contains(where: { $0.mainNumbers.sorted() != record.mainNumbers || $0.extraNumbers.sorted() != record.extraNumbers }) {
                    throw InternationalLotteryError.conflict(LotteryCalendar.text(record.date))
                }
            }
            for record in records where byDate[LotteryCalendar.text(record.date)] == nil {
                let entry = try record.validatedModel()
                context.insert(entry)
                byDate[LotteryCalendar.text(record.date)] = [entry]
                added += 1
            }
            try context.save()
            start = stop
        }
        return added
    }

    static func seed(context: ModelContext) throws {
        guard let url = Bundle.main.url(forResource: "international-draws", withExtension: "json") else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([InternationalLotteryRecord].self, from: Data(contentsOf: url))
        let existing = try context.fetch(FetchDescriptor<InternationalLotteryEntry>())
        var dates = Set(existing.filter(\.isDraw).map { "\($0.gameID)|\(LotteryCalendar.text($0.date))" })
        let models = try records.map { try $0.validatedModel() }
        for entry in models {
            let key = "\(entry.gameID)|\(LotteryCalendar.text(entry.date))"
            if dates.insert(key).inserted { context.insert(entry) }
        }
        try context.save()
    }
}
