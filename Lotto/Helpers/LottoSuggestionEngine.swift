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
            return "Trygg"
        case .balansert:
            return "Balansert"
        case .sjansen:
            return "Sjansen"
        }
    }

    var description: String {
        switch self {
        case .trygg:
            return "Prioriterer predikerte tall og historikk fra samme uke."
        case .balansert:
            return "Blander prediksjon, samme uke og frekvens jevnt."
        case .sjansen:
            return "Sprer rekkene mer og slipper inn flere overraskelser."
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
    static func makeSuggestedRows(
        for date: Date,
        predictedNumbers: [Int],
        jackpots: [JackPot],
        mode: SuggestionMode = .balansert,
        rowCount: Int = 20
    ) -> [SuggestedRow] {
        guard rowCount > 0 else { return [] }

        let weekNumber = LottoDateSupport.weekNumber(for: date)
        let sameWeekJackpots = jackpots
            .filter { $0.weekNr == weekNumber }
            .sorted { $0.dato > $1.dato }

        let overallFrequency = LottoStatistics.frequency(for: jackpots)
        let sameWeekFrequency = LottoStatistics.frequency(for: sameWeekJackpots)
        let predictedSet = Set(predictedNumbers.filter(LottoStatistics.validNumberRange.contains))
        let sameWeekRows = sameWeekJackpots.map { normalizedRow(from: $0) }.filter { $0.count == 7 }
        let sameWeekSet = Set(sameWeekRows.flatMap { $0 })
        let maxOverallFrequency = overallFrequency.values.max() ?? 0

        var weightedNumbers = (1...34).map { number in
            (
                number: number,
                score: score(
                    for: number,
                    mode: mode,
                    predictedSet: predictedSet,
                    sameWeekFrequency: sameWeekFrequency,
                    overallFrequency: overallFrequency,
                    maxOverallFrequency: maxOverallFrequency
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.number < rhs.number
            }
            return lhs.score > rhs.score
        }
        .map(\.number)

        if weightedNumbers.isEmpty {
            weightedNumbers = Array(1...34)
        }

        var rows: [SuggestedRow] = []
        var seen: Set<[Int]> = []

        for historicalRow in sameWeekRows {
            guard rows.count < rowCount else { break }

            let mergedRow = buildRow(
                startingWith: historicalRow,
                weightedNumbers: weightedNumbers,
                predictedSet: predictedSet,
                mode: mode,
                offset: rows.count
            )

            if seen.insert(mergedRow).inserted {
                rows.append(
                    suggestedRow(
                        from: mergedRow,
                        predictedSet: predictedSet,
                        sameWeekSet: sameWeekSet,
                        sourceLabel: "Historisk uke"
                    )
                )
            }
        }

        var offset = 0
        while rows.count < rowCount && offset < 500 {
            let baseNumbers = predictedSet.isEmpty
                ? Array(weightedNumbers.prefix(7))
                : Array(predictedSet.sorted().prefix(7))

            let row = buildRow(
                startingWith: baseNumbers,
                weightedNumbers: weightedNumbers,
                predictedSet: predictedSet,
                mode: mode,
                offset: offset
            )

            if seen.insert(row).inserted {
                rows.append(
                    suggestedRow(
                        from: row,
                        predictedSet: predictedSet,
                        sameWeekSet: sameWeekSet,
                        sourceLabel: predictedSet.isEmpty ? "Historisk miks" : "Predikert miks"
                    )
                )
            }

            offset += 1
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

    private static func buildRow(
        startingWith seedNumbers: [Int],
        weightedNumbers: [Int],
        predictedSet: Set<Int>,
        mode: SuggestionMode,
        offset: Int
    ) -> [Int] {
        var row = seedNumbers.filter(LottoStatistics.validNumberRange.contains)
        var used = Set(row)
        let protectedCount: Int
        switch mode {
        case .trygg:
            protectedCount = 4
        case .balansert:
            protectedCount = 3
        case .sjansen:
            protectedCount = 2
        }
        let protectedNumbers = Set(row.prefix(protectedCount))
        let step = max(1, (offset % 5) + 1)
        let rotated = rotatedNumbers(from: weightedNumbers, by: offset)
        var index = 0

        while row.count < 7 && index < rotated.count * 3 {
            let number = rotated[index % rotated.count]
            if index.isMultiple(of: step) && used.insert(number).inserted {
                row.append(number)
            }
            index += 1
        }

        if row.count < 7 {
            for number in 1...34 where row.count < 7 {
                if used.insert(number).inserted {
                    row.append(number)
                }
            }
        }

        var finalized = balanceRow(row, predictedSet: predictedSet)
        finalized = diversifyRow(
            finalized,
            weightedNumbers: weightedNumbers,
            mode: mode,
            offset: offset,
            protectedNumbers: protectedNumbers
        )
        return Array(finalized.prefix(7)).sorted()
    }

    private static func rotatedNumbers(from numbers: [Int], by offset: Int) -> [Int] {
        guard !numbers.isEmpty else { return [] }
        let safeOffset = offset % numbers.count
        return Array(numbers[safeOffset...]) + Array(numbers[..<safeOffset])
    }

    private static func balanceRow(_ row: [Int], predictedSet: Set<Int>) -> [Int] {
        let sorted = row.sorted()
        guard sorted.count >= 7 else { return sorted }

        let low = sorted.filter { $0 <= 11 }
        let mid = sorted.filter { (12...22).contains($0) }
        let high = sorted.filter { $0 >= 23 }

        if !low.isEmpty, !mid.isEmpty, !high.isEmpty {
            return sorted
        }

        var adjusted = sorted
        let fallbackOrder = predictedSet.sorted() + Array(1...34)
        for number in fallbackOrder {
            guard LottoStatistics.validNumberRange.contains(number), !adjusted.contains(number) else { continue }
            adjusted.append(number)

            let recalcLow = adjusted.filter { $0 <= 11 }
            let recalcMid = adjusted.filter { (12...22).contains($0) }
            let recalcHigh = adjusted.filter { $0 >= 23 }

            if !recalcLow.isEmpty, !recalcMid.isEmpty, !recalcHigh.isEmpty {
                return adjusted.sorted()
            }
        }

        return adjusted.sorted()
    }

    private static func diversifyRow(
        _ row: [Int],
        weightedNumbers: [Int],
        mode: SuggestionMode,
        offset: Int,
        protectedNumbers: Set<Int>
    ) -> [Int] {
        guard row.count >= 7, !weightedNumbers.isEmpty else { return row.sorted() }

        var adjusted = row.sorted()
        let replacementBase: Int
        switch mode {
        case .trygg:
            replacementBase = 1
        case .balansert:
            replacementBase = 2
        case .sjansen:
            replacementBase = 3
        }
        let replacementCount = min(4, max(1, replacementBase + (offset % 2)))
        let rotated = rotatedNumbers(from: weightedNumbers, by: offset * 2 + 1)

        var rotatedIndex = 0
        for replacementIndex in 0..<replacementCount {
            while rotatedIndex < rotated.count {
                let candidate = rotated[rotatedIndex]
                rotatedIndex += 1

                guard !adjusted.contains(candidate) else { continue }

                let replaceableIndices = adjusted.indices.filter { !protectedNumbers.contains(adjusted[$0]) }
                guard !replaceableIndices.isEmpty else { break }

                let targetIndex = replaceableIndices[(replacementIndex + offset) % replaceableIndices.count]
                adjusted[targetIndex] = candidate
                break
            }
        }

        let uniqueSorted = Array(Set(adjusted)).sorted()
        if uniqueSorted.count == 7 {
            return uniqueSorted
        }

        var fallback = uniqueSorted
        for number in rotated where fallback.count < 7 && !fallback.contains(number) {
            fallback.append(number)
        }
        for number in 1...34 where fallback.count < 7 && !fallback.contains(number) {
            fallback.append(number)
        }
        return fallback.sorted()
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
