//
//  LottoSuggestionEngine.swift
//  Lotto
//
//  Created by Codex on 02/09/2026.
//

import Foundation

enum SuggestionMode: String, CaseIterable, Identifiable, Codable {
    case trygg
    case balansert
    case sjansen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trygg:
            return "Historikk"
        case .balansert:
            return "Blandet"
        case .sjansen:
            return "Variasjon"
        }
    }

    var description: String {
        switch self {
        case .trygg:
            return "Legger mest vekt på historiske intervaller og samme uke i tidligere år."
        case .balansert:
            return "Blander historiske intervaller, samme uke og frekvens."
        case .sjansen:
            return "Sprer tallvalgene mer. Gir ikke høyere vinnersjanse."
        }
    }
}

struct SuggestedRow: Identifiable, Hashable {
    let numbers: [Int]
    let predictedMatches: [Int]
    let sameWeekMatches: [Int]
    let sourceLabel: String

    var id: String {
        numbers.map(String.init).joined(separator: "-")
    }
}

enum LottoSuggestionEngine {
    static func makeSuggestedRows(for date: Date, predictedNumbers: [Int], jackpots: [JackPot],
                                  mode: SuggestionMode = .balansert, rowCount: Int = 20,
                                  favoriteNumbers: [Int] = []) -> [SuggestedRow] {
        var generator = SystemRandomNumberGenerator()
        return makeSuggestedRows(for: date, predictedNumbers: predictedNumbers, jackpots: jackpots,
                                 mode: mode, rowCount: rowCount, favoriteNumbers: favoriteNumbers, using: &generator)
    }
    static func makeSuggestedRows<R: RandomNumberGenerator>(for date: Date, predictedNumbers: [Int], jackpots: [JackPot],
                                  mode: SuggestionMode = .balansert, rowCount: Int = 20,
                                  favoriteNumbers: [Int] = [], using generator: inout R) -> [SuggestedRow] {
        guard rowCount > 0 else { return [] }
        // Looking at a past date must not use that draw or any later results.
        let history = jackpots.filter { LottoDateSupport.normalize($0.dato) < LottoDateSupport.normalize(date) }
        let sameWeek = history.filter { $0.weekNr == LottoDateSupport.weekNumber(for: date) }
        let overall = LottoStatistics.frequency(for: history), weekly = LottoStatistics.frequency(for: sameWeek)
        let predicted = Set(predictedNumbers.filter(LottoStatistics.validNumberRange.contains))
        let weekSet = Set(sameWeek.flatMap { normalizedRow(from: $0) })
        let maximum = overall.values.max() ?? 0
        let scored = (1...34).map { n in
            (number: n, score: score(for: n, mode: mode, predictedSet: predicted,
                sameWeekFrequency: weekly, overallFrequency: overall, maxOverallFrequency: maximum))
        }
        let highest = scored.map(\.score).max() ?? 0
        let strength = mode == .trygg ? 8.0 : (mode == .balansert ? 4.0 : 1.5)
        let weights = scored.map { (number: $0.number, weight: 1 + (highest > 0 ? Double($0.score) / Double(highest) * strength : 0)) }
        // Randomize equal scores, rather than always locking the lowest numbers.
        let ranked = scored.shuffled(using: &generator).sorted { $0.score > $1.score }.map(\.number)
        let favorites = LotteryFavoriteSelection(mainNumbers: favoriteNumbers).effective(for: .lotto).mainNumbers
        let wanted = min(rowCount, 500) + (favorites.isEmpty ? 0 : 1)
        var rows: [SuggestedRow] = [], seen = Set<[Int]>()
        func append(_ values: [Int], label: String) {
            let n = values.sorted()
            guard seen.insert(n).inserted else { return }
            rows.append(suggestedRow(from: n, predictedSet: predicted, sameWeekSet: weekSet, sourceLabel: label))
        }
        if !favorites.isEmpty {
            append(favorites + ranked.filter { !favorites.contains($0) }.prefix(7 - favorites.count), label: "Favorittrekke")
        }
        if highest > 0 && rows.count < wanted {
            append(Array(ranked.prefix(7)), label: "Historisk vekting")
        }
        for attempt in 0..<(wanted * 200) {
            guard rows.count < wanted else { break }
            let values = LotteryWeightedSampling.sample(weights, count: 7, using: &generator)
            // Avoid batches full of rows differing by only one number. Relax only
            // for very large batches; uniqueness is always required.
            if attempt < wanted * 100 && rows.contains(where: { Set($0.numbers).intersection(values).count >= 6 }) { continue }
            append(values, label: mode == .sjansen ? "Variert utvalg" : "Vektet historikkmiks")
        }
        return rows
    }

    private static func normalizedRow(from jackpot: JackPot) -> [Int] {
        Array(Set([jackpot.nr1, jackpot.nr2, jackpot.nr3, jackpot.nr4, jackpot.nr5, jackpot.nr6, jackpot.nr7]))
            .filter(LottoStatistics.validNumberRange.contains)
            .sorted()
    }

    private static func score(
        for number: Int,
        mode: SuggestionMode,
        predictedSet: Set<Int>,
        sameWeekFrequency: [Int: Int],
        overallFrequency: [Int: Int],
        maxOverallFrequency: Int
    ) -> Int {
        let overallScore = overallFrequency[number] ?? 0
        let sameWeekScore = sameWeekFrequency[number] ?? 0

        switch mode {
        case .trygg:
            let predictionScore = predictedSet.contains(number) ? 1400 : 0
            return predictionScore + (sameWeekScore * 140) + (overallScore * 2)
        case .balansert:
            let predictionScore = predictedSet.contains(number) ? 1000 : 0
            return predictionScore + (sameWeekScore * 100) + overallScore
        case .sjansen:
            let predictionScore = predictedSet.contains(number) ? 650 : 0
            let rarityBonus = max(0, maxOverallFrequency - overallScore)
            return predictionScore + (sameWeekScore * 70) + rarityBonus
        }
    }

    private static func suggestedRow(
        from numbers: [Int],
        predictedSet: Set<Int>,
        sameWeekSet: Set<Int>,
        sourceLabel: String
    ) -> SuggestedRow {
        SuggestedRow(
            numbers: numbers,
            predictedMatches: numbers.filter { predictedSet.contains($0) },
            sameWeekMatches: numbers.filter { sameWeekSet.contains($0) },
            sourceLabel: sourceLabel
        )
    }
}
