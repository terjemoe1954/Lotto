//
//  LottoRules.swift
//  Lotto
//
//  Created by Codex on 02/09/2026.
//

import Foundation

enum LottoRules {
    static let validNumberRange = 1...34

    static func rowValidationMessage(numbers: [Int], drawDate: Date) -> String? {
        if numbers.contains(where: { !validNumberRange.contains($0) }) {
            return "Tall må være mellom 1 og 34."
        }

        if numbers.count != Set(numbers).count {
            return "Samme tall kan ikke registreres flere ganger på samme rekke."
        }

        if !drawDate.isSaturday {
            return "Trekningsdato må være en lørdag."
        }

        return nil
    }

    static func jackpotValidationMessage(
        numbers: [Int],
        drawDate: Date,
        existingDates: [Date]
    ) -> String? {
        if numbers.contains(where: { !validNumberRange.contains($0) }) {
            return "Tall må være mellom 1 og 34."
        }

        if numbers.count != Set(numbers).count {
            return "Samme tall kan ikke registreres flere ganger i samme trekning."
        }

        let normalizedDate = LottoDateSupport.normalize(drawDate)
        if existingDates.contains(where: { LottoDateSupport.normalize($0) == normalizedDate }) {
            return "Det finnes allerede en trekning registrert på denne datoen."
        }

        if !drawDate.isSaturday {
            return "Trekningsdato må være en lørdag."
        }

        return nil
    }

    static func sanitizeNumberInput(_ text: String) -> String {
        let digitsOnly = String(text.filter(\.isNumber).prefix(2))

        guard let value = Int(digitsOnly) else {
            return digitsOnly
        }

        return String(min(value, validNumberRange.upperBound))
    }

    static func shouldSeedJackpots(didSeedJackpots: Bool, existingCount: Int) -> Bool {
        !didSeedJackpots && existingCount == 0
    }

    static func missingSeedJackpots(seedJackpots: [JackPot], existingDates: [Date]) -> [JackPot] {
        let normalizedExistingDates = Set(existingDates.map(LottoDateSupport.normalize))
        return seedJackpots.filter { jackpot in
            !normalizedExistingDates.contains(LottoDateSupport.normalize(jackpot.dato))
        }
    }

    static func duplicateJackpots(in jackpots: [JackPot]) -> [JackPot] {
        var keeperByDate: [Date: JackPot] = [:]
        var duplicates: [JackPot] = []

        for jackpot in jackpots {
            let normalizedDate = LottoDateSupport.normalize(jackpot.dato)
            if let currentKeeper = keeperByDate[normalizedDate] {
                if jackpotQualityScore(jackpot) > jackpotQualityScore(currentKeeper) {
                    duplicates.append(currentKeeper)
                    keeperByDate[normalizedDate] = jackpot
                } else {
                    duplicates.append(jackpot)
                }
            } else {
                keeperByDate[normalizedDate] = jackpot
            }
        }

        return duplicates
    }

    private static func jackpotQualityScore(_ jackpot: JackPot) -> Int {
        let numbers = [jackpot.nr1, jackpot.nr2, jackpot.nr3, jackpot.nr4, jackpot.nr5, jackpot.nr6, jackpot.nr7, jackpot.nr8]
        let validUniqueCount = Set(numbers.filter(validNumberRange.contains)).count
        let nonZeroCount = numbers.filter { $0 != 0 }.count
        let hasWeekNumber = jackpot.weekNr > 0 ? 1 : 0
        return (validUniqueCount * 100) + (nonZeroCount * 10) + hasWeekNumber
    }
}

enum LottoWinnerLogic {
    static func comparison(
        for result: ResultRow,
        against jackpot: JackpotRow
    ) -> ResultComparison {
        let matchedNumbers = Set(result.numbers).intersection(Set(jackpot.numbers)).sorted()
        let matchedExtraNumber: Int?

        if let extraNumber = jackpot.extraNumber, result.numbers.contains(extraNumber) {
            matchedExtraNumber = extraNumber
        } else {
            matchedExtraNumber = nil
        }

        return ResultComparison(
            id: "\(result.id)-\(jackpot.date.timeIntervalSince1970)",
            result: result,
            jackpot: jackpot,
            matchedNumbers: matchedNumbers,
            matchedExtraNumber: matchedExtraNumber
        )
    }
}
