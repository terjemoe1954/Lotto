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
