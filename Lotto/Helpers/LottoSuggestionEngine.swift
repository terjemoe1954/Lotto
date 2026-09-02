//
//  LottoSuggestionEngine.swift
//  Lotto
//
//  Created by Codex on 02/09/2026.
//

import Foundation

struct SuggestedRow: Identifiable, Hashable {
    let numbers: [Int]

    var id: String {
        numbers.map(String.init).joined(separator: "-")
    }
}

enum LottoSuggestionEngine {
    static func makeSuggestedRows(
        for date: Date,
        predictedNumbers: [Int],
        jackpots: [JackPot],
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

        var weightedNumbers = (1...34).map { number in
            (
                number: number,
                score: score(
                    for: number,
                    predictedSet: predictedSet,
                    sameWeekFrequency: sameWeekFrequency,
                    overallFrequency: overallFrequency
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
                offset: rows.count
            )

            if seen.insert(mergedRow).inserted {
                rows.append(SuggestedRow(numbers: mergedRow))
            }
        }

        var offset = 0
        while rows.count < rowCount && offset < 200 {
            let baseNumbers = predictedSet.isEmpty
                ? Array(weightedNumbers.prefix(7))
                : Array(predictedSet.sorted().prefix(7))

            let row = buildRow(
                startingWith: baseNumbers,
                weightedNumbers: weightedNumbers,
                predictedSet: predictedSet,
                offset: offset
            )

            if seen.insert(row).inserted {
                rows.append(SuggestedRow(numbers: row))
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
        predictedSet: Set<Int>,
        sameWeekFrequency: [Int: Int],
        overallFrequency: [Int: Int]
    ) -> Int {
        let predictionScore = predictedSet.contains(number) ? 1000 : 0
        let sameWeekScore = (sameWeekFrequency[number] ?? 0) * 100
        let overallScore = overallFrequency[number] ?? 0
        return predictionScore + sameWeekScore + overallScore
    }

    private static func buildRow(
        startingWith seedNumbers: [Int],
        weightedNumbers: [Int],
        predictedSet: Set<Int>,
        offset: Int
    ) -> [Int] {
        var row = seedNumbers.filter(LottoStatistics.validNumberRange.contains)
        var used = Set(row)

        let rotated = rotatedNumbers(from: weightedNumbers, by: offset)
        for number in rotated where row.count < 7 {
            if used.insert(number).inserted {
                row.append(number)
            }
        }

        if row.count < 7 {
            for number in 1...34 where row.count < 7 {
                if used.insert(number).inserted {
                    row.append(number)
                }
            }
        }

        let finalized = balanceRow(row, predictedSet: predictedSet)
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
}
