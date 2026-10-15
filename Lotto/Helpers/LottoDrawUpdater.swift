import Foundation
import SwiftData

struct LottoDrawUpdateResult: Equatable, Sendable {
    let addedCount: Int
    let latestDrawDate: Date?
}

enum LottoDrawUpdateError: LocalizedError {
    case invalidResponse
    case invalidDraw(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Norsk Tipping svarte ikke som forventet."
        case .invalidDraw(let date):
            return "Trekningen \(date) inneholder ugyldige tall."
        }
    }
}

struct LottoRemoteDraw: Equatable, Sendable {
    let date: Date
    let mainNumbers: [Int]
    let extraNumber: Int
}

enum LottoDrawUpdater {
    private static let endpoint = "https://api.norsk-tipping.no/LotteryGameInfo/v2/api/results/lotto"
    private static let maximumDaysPerRequest = 28

    @MainActor
    static func update(modelContext: ModelContext) async throws -> LottoDrawUpdateResult {
        let descriptor = FetchDescriptor<JackPot>(sortBy: [SortDescriptor(\JackPot.dato, order: .reverse)])
        let existing = try modelContext.fetch(descriptor)
        let calendar = Calendar(identifier: .gregorian)
        let latestDate = existing.first.map { LottoDateSupport.normalize($0.dato) }
        let fallbackDate = calendar.date(from: DateComponents(year: 2011, month: 8, day: 27)) ?? .distantPast
        let startDate = calendar.date(byAdding: .day, value: 1, to: latestDate ?? fallbackDate) ?? fallbackDate
        let today = LottoDateSupport.normalize(.now)

        guard startDate <= today else {
            return LottoDrawUpdateResult(addedCount: 0, latestDrawDate: latestDate)
        }

        let remoteDraws = try await fetchDraws(from: startDate, through: today)
        let existingDates = Set(existing.map { LottoDateSupport.normalize($0.dato) })
        let newDraws = remoteDraws.filter { !existingDates.contains(LottoDateSupport.normalize($0.date)) }

        for draw in newDraws {
            modelContext.insert(JackPot(
                dato: draw.date,
                nr1: draw.mainNumbers[0],
                nr2: draw.mainNumbers[1],
                nr3: draw.mainNumbers[2],
                nr4: draw.mainNumbers[3],
                nr5: draw.mainNumbers[4],
                nr6: draw.mainNumbers[5],
                nr7: draw.mainNumbers[6],
                nr8: draw.extraNumber,
                weekNr: LottoDateSupport.weekNumber(for: draw.date)
            ))
        }

        if !newDraws.isEmpty {
            try modelContext.save()
        }

        return LottoDrawUpdateResult(
            addedCount: newDraws.count,
            latestDrawDate: newDraws.map(\.date).max() ?? latestDate
        )
    }

    static func fetchDraws(
        from startDate: Date,
        through endDate: Date,
        session: URLSession = .shared
    ) async throws -> [LottoRemoteDraw] {
        let calendar = Calendar(identifier: .gregorian)
        var currentStart = LottoDateSupport.normalize(startDate)
        let normalizedEnd = LottoDateSupport.normalize(endDate)
        var drawsByDate: [Date: LottoRemoteDraw] = [:]

        while currentStart <= normalizedEnd {
            let inclusiveEnd = min(
                calendar.date(byAdding: .day, value: maximumDaysPerRequest - 1, to: currentStart) ?? normalizedEnd,
                normalizedEnd
            )
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
            let data = try await requestData(from: currentStart, to: exclusiveEnd, session: session)

            for draw in try decodeDraws(from: data) {
                drawsByDate[LottoDateSupport.normalize(draw.date)] = draw
            }

            guard let nextStart = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) else {
                break
            }
            currentStart = nextStart
        }

        return drawsByDate.values.sorted { $0.date < $1.date }
    }

    static func decodeDraws(from data: Data) throws -> [LottoRemoteDraw] {
        let response = try JSONDecoder().decode(APIResponse.self, from: data)

        return try response.gameResult.map { result in
            let dateText = String(result.drawDate.prefix(10))
            guard let date = date(from: dateText) else {
                throw LottoDrawUpdateError.invalidDraw(dateText)
            }

            let mainNumbers = result.winnerNumber
                .filter { $0.type == 1 }
                .compactMap { Int($0.number) }
                .sorted()
            let extraNumbers = result.winnerNumber
                .filter { $0.type == 2 }
                .compactMap { Int($0.number) }

            let allNumbers = mainNumbers + extraNumbers.prefix(1)
            guard mainNumbers.count == 7,
                  extraNumbers.count == 1,
                  Set(allNumbers).count == 8,
                  allNumbers.allSatisfy(LottoRules.validNumberRange.contains),
                  date.isSaturday else {
                throw LottoDrawUpdateError.invalidDraw(dateText)
            }

            return LottoRemoteDraw(
                date: date,
                mainNumbers: mainNumbers,
                extraNumber: extraNumbers[0]
            )
        }
    }

    private static func requestData(
        from startDate: Date,
        to endDate: Date,
        session: URLSession
    ) async throws -> Data {
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "fromDate", value: apiDate(startDate)),
            URLQueryItem(name: "toDate", value: apiDate(endDate))
        ]

        guard let url = components?.url else {
            throw LottoDrawUpdateError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LottoDrawUpdateError.invalidResponse
        }
        return data
    }

    private static func apiDate(_ date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func date(from text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2])
        )
    }

    private struct APIResponse: Decodable {
        let gameResult: [APIDraw]
    }

    private struct APIDraw: Decodable {
        let drawDate: String
        let winnerNumber: [APINumber]
    }

    private struct APINumber: Decodable {
        let number: String
        let type: Int
    }
}
