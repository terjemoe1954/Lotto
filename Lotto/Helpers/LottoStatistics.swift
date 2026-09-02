//
//  LottoStatistics.swift
//  Lotto
//
//  Created by Codex on 02/09/2026.
//

import Foundation

struct LottoStatistics {
    static let validNumberRange = 1...34

    static func numbers(in jackpot: JackPot) -> [Int] {
        [jackpot.nr1, jackpot.nr2, jackpot.nr3, jackpot.nr4,
         jackpot.nr5, jackpot.nr6, jackpot.nr7, jackpot.nr8]
    }

    static func frequency(for jackpots: [JackPot]) -> [Int: Int] {
        var counts: [Int: Int] = [:]

        for jackpot in jackpots {
            for number in numbers(in: jackpot) where validNumberRange.contains(number) {
                counts[number, default: 0] += 1
            }
        }

        return counts
    }

    static func statsPerNumber(from jackpots: [JackPot]) -> (
        avgGaps: [Int: Double],
        lastDates: [Int: Date]
    ) {
        statsPerNumber(from: jackpots, excludeHighestGapFromAverage: false)
    }

    static func statsPerNumber(
        from jackpots: [JackPot],
        excludeHighestGapFromAverage: Bool
    ) -> (
        avgGaps: [Int: Double],
        lastDates: [Int: Date]
    ) {
        var appearances: [Int: [Date]] = [:]

        for jackpot in jackpots {
            let date = jackpot.dato
            for number in numbers(in: jackpot) where validNumberRange.contains(number) {
                appearances[number, default: []].append(date)
            }
        }

        var avgGaps: [Int: Double] = [:]
        var lastDates: [Int: Date] = [:]
        let calendar = Calendar.current

        for (number, dates) in appearances {
            let sortedDates = dates.sorted()
            lastDates[number] = sortedDates.last

            guard sortedDates.count >= 2 else { continue }

            var gaps: [Double] = []
            for index in 1..<sortedDates.count {
                let previousDate = sortedDates[index - 1]
                let currentDate = sortedDates[index]

                if let days = calendar.dateComponents([.day], from: previousDate, to: currentDate).day {
                    gaps.append(Double(days))
                }
            }

            if !gaps.isEmpty {
                avgGaps[number] = robustAverage(
                    for: gaps,
                    excludeHighestGapFromAverage: excludeHighestGapFromAverage
                )
            }
        }

        return (avgGaps, lastDates)
    }

    static func nextDatesPerNumber(
        avgGaps: [Int: Double],
        lastDates: [Int: Date],
        advancingPast referenceDate: Date? = nil
    ) -> [Int: Date] {
        var nextDates: [Int: Date] = [:]
        let calendar = Calendar.current

        for (number, lastDate) in lastDates {
            guard let avgDays = avgGaps[number] else { continue }

            let stepDays = max(1, Int(avgDays.rounded()))
            var candidate = calendar.date(byAdding: .day, value: stepDays, to: lastDate)

            if let referenceDate {
                while let currentCandidate = candidate, currentCandidate <= referenceDate {
                    candidate = calendar.date(byAdding: .day, value: stepDays, to: currentCandidate)
                }
            }

            if let candidate {
                nextDates[number] = candidate
            }
        }

        return nextDates
    }

    private static func robustAverage(
        for gaps: [Double],
        excludeHighestGapFromAverage: Bool
    ) -> Double {
        let sourceGaps = excludeHighestGapFromAverage ? gapsWithoutHighestValue(from: gaps) : gaps
        let sortedGaps = sourceGaps.sorted()
        let count = sortedGaps.count

        guard count > 0 else { return 0 }

        if count < 4 {
            let trimCount = max(1, count / 5)
            let startIndex = min(trimCount, max(0, count - 1))
            let endIndex = max(startIndex + 1, count - trimCount)
            let trimmed = Array(sortedGaps[startIndex..<endIndex])
            let sum = trimmed.reduce(0, +)
            return sum / Double(trimmed.count)
        }

        let midpoint = count / 2
        let lowerHalf: [Double]
        let upperHalf: [Double]

        if count.isMultiple(of: 2) {
            lowerHalf = Array(sortedGaps[..<midpoint])
            upperHalf = Array(sortedGaps[midpoint...])
        } else {
            lowerHalf = Array(sortedGaps[..<midpoint])
            upperHalf = Array(sortedGaps[(midpoint + 1)...])
        }

        let q1 = median(of: lowerHalf)
        let q3 = median(of: upperHalf)
        let iqr = q3 - q1

        if iqr <= 0 {
            return sortedGaps.reduce(0, +) / Double(count)
        }

        let lowerFence = q1 - 1.5 * iqr
        let upperFence = q3 + 1.5 * iqr
        let filtered = sortedGaps.filter { $0 >= lowerFence && $0 <= upperFence }

        if filtered.isEmpty {
            let trimCount = max(1, count / 5)
            let startIndex = min(trimCount, max(0, count - 1))
            let endIndex = max(startIndex + 1, count - trimCount)
            let trimmed = Array(sortedGaps[startIndex..<endIndex])
            let sum = trimmed.reduce(0, +)
            return sum / Double(trimmed.count)
        }

        return filtered.reduce(0, +) / Double(filtered.count)
    }

    private static func gapsWithoutHighestValue(from gaps: [Double]) -> [Double] {
        guard gaps.count > 1, let highest = gaps.max(), let index = gaps.firstIndex(of: highest) else {
            return gaps
        }

        var adjustedGaps = gaps
        adjustedGaps.remove(at: index)
        return adjustedGaps
    }

    private static func median(of values: [Double]) -> Double {
        let count = values.count

        if count == 0 {
            return .nan
        }

        if count.isMultiple(of: 2) {
            return (values[count / 2 - 1] + values[count / 2]) / 2.0
        }

        return values[count / 2]
    }
}
