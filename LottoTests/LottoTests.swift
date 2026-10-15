//
//  LottoTests.swift
//  LottoTests
//
//  Created by Terje Moe on 02/09/2026.
//

import Foundation
import Testing
@testable import Lotto

struct LottoTests {
    @Test func formattedDateUsesExpectedNorwegianStyle() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2))!

        #expect(LottoDateSupport.formattedDate(date) == "02.09.2026")
    }

    @Test func normalizeRemovesTimeComponents() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 2,
            hour: 18,
            minute: 45
        ))!

        let normalized = LottoDateSupport.normalize(date)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: normalized)

        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 2)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
    }

    @Test func saturdayDetectionMatchesExpectedWeekday() {
        let calendar = Calendar(identifier: .gregorian)
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6))!

        #expect(LottoDateSupport.isSaturday(saturday))
        #expect(!LottoDateSupport.isSaturday(sunday))
        #expect(saturday.isSaturday)
    }

    @Test func statisticsCountOnlyValidNumbers() {
        let jackpots = [
            JackPot(dato: .now, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 35, nr6: 0, nr7: 2, nr8: 34),
            JackPot(dato: .now, nr1: 1, nr2: 34, nr3: 10, nr4: 12, nr5: 20, nr6: 30, nr7: 33, nr8: -1)
        ]

        let frequency = LottoStatistics.frequency(for: jackpots)

        #expect(frequency[1] == 2)
        #expect(frequency[2] == 2)
        #expect(frequency[34] == 2)
        #expect(frequency[35] == nil)
        #expect(frequency[0] == nil)
    }

    @Test func statisticsReturnAverageGapAndLastDate() {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let secondDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let thirdDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 17))!

        let jackpots = [
            JackPot(dato: firstDate, nr1: 7),
            JackPot(dato: secondDate, nr1: 7),
            JackPot(dato: thirdDate, nr1: 7)
        ]

        let stats = LottoStatistics.statsPerNumber(from: jackpots)

        #expect(stats.lastDates[7] == thirdDate)
        #expect(stats.avgGaps[7] == 7.0)
    }

    @Test func nextDatesAdvancePastReferenceDateWhenRequested() {
        let calendar = Calendar(identifier: .gregorian)
        let lastDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 20))!

        let nextDates = LottoStatistics.nextDatesPerNumber(
            avgGaps: [8: 7.0],
            lastDates: [8: lastDate],
            advancingPast: referenceDate
        )

        let expectedDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 24))!
        #expect(nextDates[8] == expectedDate)
    }

    @Test func rowValidationRejectsDuplicateNumbers() {
        let saturday = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 9, day: 5)
        )!

        let message = LottoRules.rowValidationMessage(
            numbers: [1, 2, 3, 4, 5, 5, 7],
            drawDate: saturday
        )

        #expect(message == "Samme tall kan ikke registreres flere ganger på samme rekke.")
    }

    @Test func rowValidationRejectsNumbersOutsideValidRange() {
        let saturday = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 9, day: 5)
        )!

        let message = LottoRules.rowValidationMessage(
            numbers: [1, 2, 3, 4, 5, 6, 35],
            drawDate: saturday
        )

        #expect(message == "Tall må være mellom 1 og 34.")
    }

    @Test func duplicateResultValidationRejectsSameNumbersOnSameDate() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 21))!
        let existingResults = [
            Result(dato: morning, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 5, nr6: 6, nr7: 7, weekNr: 36)
        ]

        let message = LottoRules.duplicateResultValidationMessage(
            numbers: [7, 6, 5, 4, 3, 2, 1],
            drawDate: evening,
            existingResults: existingResults
        )

        #expect(message == "Samme rekke er allerede lagret pa denne datoen.")
    }

    @Test func duplicateResultValidationAllowsSameNumbersOnDifferentDate() {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let secondDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        let existingResults = [
            Result(dato: firstDate, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 5, nr6: 6, nr7: 7, weekNr: 36)
        ]

        let message = LottoRules.duplicateResultValidationMessage(
            numbers: [1, 2, 3, 4, 5, 6, 7],
            drawDate: secondDate,
            existingResults: existingResults
        )

        #expect(message == nil)
    }

    @Test func jackpotValidationRejectsExistingDrawDate() {
        let calendar = Calendar(identifier: .gregorian)
        let saturdayMorning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 9))!
        let saturdayEvening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 21))!

        let message = LottoRules.jackpotValidationMessage(
            numbers: [1, 2, 3, 4, 5, 6, 7, 8],
            drawDate: saturdayEvening,
            existingDates: [saturdayMorning]
        )

        #expect(message == "Det finnes allerede en trekning registrert på denne datoen.")
    }

    @Test func sanitizeNumberInputKeepsOnlyDigitsAndCapsAt34() {
        #expect(LottoRules.sanitizeNumberInput("3a7") == "34")
        #expect(LottoRules.sanitizeNumberInput("09") == "9")
        #expect(LottoRules.sanitizeNumberInput("ab") == "")
    }

    @Test func jackpotImportAddsOnlyDatesThatDoNotExist() {
        let calendar = Calendar(identifier: .gregorian)
        let existingDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 21))!
        let matchingSeedDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 9))!
        let newSeedDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!

        let seedJackpots = [
            JackPot(dato: matchingSeedDate, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 5, nr6: 6, nr7: 7, nr8: 8),
            JackPot(dato: newSeedDate, nr1: 9, nr2: 10, nr3: 11, nr4: 12, nr5: 13, nr6: 14, nr7: 15, nr8: 16)
        ]

        let existingJackpot = JackPot(
            dato: existingDate,
            nr1: 1, nr2: 2, nr3: 3, nr4: 4,
            nr5: 5, nr6: 6, nr7: 7, nr8: 8
        )
        let plan = LottoRules.jackpotImportPlan(
            bundledJackpots: seedJackpots,
            existingJackpots: [existingJackpot]
        )

        #expect(plan.missing.count == 1)
        #expect(plan.missing.first?.dato == newSeedDate)
        #expect(plan.conflicts.isEmpty)
    }

    @Test func jackpotImportReportsDifferentNumbersOnExistingDate() {
        let calendar = Calendar(identifier: .gregorian)
        let existingDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 21))!
        let bundledDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 9))!
        let existing = JackPot(
            dato: existingDate,
            nr1: 1, nr2: 2, nr3: 3, nr4: 4,
            nr5: 5, nr6: 6, nr7: 7, nr8: 8
        )
        let bundled = JackPot(
            dato: bundledDate,
            nr1: 2, nr2: 3, nr3: 4, nr4: 5,
            nr5: 6, nr6: 7, nr7: 8, nr8: 9
        )

        let plan = LottoRules.jackpotImportPlan(
            bundledJackpots: [bundled],
            existingJackpots: [existing]
        )

        #expect(plan.missing.isEmpty)
        #expect(plan.conflicts.count == 1)
        #expect(plan.conflicts.first === bundled)
    }

    @Test func drawsOnlyBackupContainsNoPersonalRowsAndKeepsItsType() throws {
        let snapshot = LottoBackupSnapshot(
            content: .drawsOnly,
            exportedAt: .now,
            settings: LottoBackupSettings(
                tolerance: 0,
                appearanceModeRawValue: AppearanceMode.system.rawValue,
                excludeHighestGapFromAverage: false
            ),
            jackpots: [],
            results: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LottoBackupSnapshot.self, from: data)

        #expect(decoded.content == .drawsOnly)
        #expect(decoded.results.isEmpty)
    }

    @Test func duplicateJackpotsKeepOnlyBestEntryPerDate() {
        let calendar = Calendar(identifier: .gregorian)
        let drawDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 10))!
        let sameDayLater = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 22))!

        let complete = JackPot(
            dato: drawDate,
            nr1: 1, nr2: 2, nr3: 3, nr4: 4,
            nr5: 5, nr6: 6, nr7: 7, nr8: 8,
            weekNr: 36
        )
        let duplicate = JackPot(
            dato: sameDayLater,
            nr1: 1, nr2: 2, nr3: 3, nr4: 4,
            nr5: 5, nr6: 0, nr7: 0, nr8: 0,
            weekNr: 0
        )
        let unique = JackPot(
            dato: calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!,
            nr1: 9, nr2: 10, nr3: 11, nr4: 12,
            nr5: 13, nr6: 14, nr7: 15, nr8: 16,
            weekNr: 37
        )

        let duplicates = LottoRules.duplicateJackpots(in: [complete, duplicate, unique])

        #expect(duplicates.count == 1)
        #expect(duplicates.first === duplicate)
    }

    @Test func remoteDrawDecoderSortsAndValidatesNumbers() throws {
        let json = """
        {
          "gameResult": [{
            "drawDate": "2026-10-10T16:30:00.000Z",
            "winnerNumber": [
              {"number": "23", "type": 1},
              {"number": "3", "type": 1},
              {"number": "5", "type": 1},
              {"number": "19", "type": 1},
              {"number": "28", "type": 1},
              {"number": "2", "type": 1},
              {"number": "8", "type": 1},
              {"number": "1", "type": 2}
            ]
          }]
        }
        """

        let draws = try LottoDrawUpdater.decodeDraws(from: Data(json.utf8))

        #expect(draws.count == 1)
        #expect(draws[0].mainNumbers == [2, 3, 5, 8, 19, 23, 28])
        #expect(draws[0].extraNumber == 1)
    }

    @Test func remoteDrawDecoderRejectsDuplicateNumbers() {
        let json = """
        {
          "gameResult": [{
            "drawDate": "2026-10-10T16:30:00.000Z",
            "winnerNumber": [
              {"number": "2", "type": 1},
              {"number": "3", "type": 1},
              {"number": "5", "type": 1},
              {"number": "8", "type": 1},
              {"number": "19", "type": 1},
              {"number": "23", "type": 1},
              {"number": "28", "type": 1},
              {"number": "28", "type": 2}
            ]
          }]
        }
        """

        #expect(throws: LottoDrawUpdateError.self) {
            try LottoDrawUpdater.decodeDraws(from: Data(json.utf8))
        }
    }

    @Test func deliveryClipboardUsesOneFormattedRowPerLine() {
        let rows = [
            Result(nr1: 1, nr2: 3, nr3: 5, nr4: 8, nr5: 13, nr6: 21, nr7: 34),
            Result(nr1: 2, nr2: 4, nr3: 6, nr4: 10, nr5: 16, nr6: 24, nr7: 30)
        ]

        let text = LottoDeliveryBuilder.clipboardText(from: rows)

        #expect(text == "01 03 05 08 13 21 34\n02 04 06 10 16 24 30")
    }

    @Test func printLayoutKeepsAllRowsAcrossPages() {
        #expect(LottoPrintLayout.pageCount(for: 0) == 1)
        #expect(LottoPrintLayout.pageCount(for: 24) == 1)
        #expect(LottoPrintLayout.pageCount(for: 25) == 2)
        #expect(LottoPrintLayout.pageCount(for: 49) == 3)
    }

    @Test func winnerComparisonReturnsMatchedNumbersAndExtraNumber() {
        let date = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 9, day: 5)
        )!

        let result = ResultRow(id: "row-1", date: date, numbers: [1, 2, 3, 8, 10, 12, 14])
        let jackpot = JackpotRow(date: date, numbers: [2, 3, 4, 5, 6, 7, 8], extraNumber: 10)

        let comparison = LottoWinnerLogic.comparison(for: result, against: jackpot)

        #expect(comparison.matchCount == 3)
        #expect(comparison.matchedNumbers == [2, 3, 8])
        #expect(comparison.matchedExtraNumber == 10)
    }

    @Test func suggestionEngineReturns20UniqueRows() {
        let calendar = Calendar(identifier: .gregorian)
        let targetDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let weekNumber = LottoDateSupport.weekNumber(for: targetDate)

        let jackpots = [
            JackPot(dato: calendar.date(from: DateComponents(year: 2024, month: 8, day: 31))!, nr1: 1, nr2: 2, nr3: 3, nr4: 4, nr5: 5, nr6: 6, nr7: 7, nr8: 8, weekNr: weekNumber),
            JackPot(dato: calendar.date(from: DateComponents(year: 2025, month: 9, day: 6))!, nr1: 2, nr2: 4, nr3: 6, nr4: 8, nr5: 10, nr6: 12, nr7: 14, nr8: 16, weekNr: weekNumber),
            JackPot(dato: calendar.date(from: DateComponents(year: 2026, month: 1, day: 4))!, nr1: 9, nr2: 11, nr3: 13, nr4: 15, nr5: 17, nr6: 19, nr7: 21, nr8: 23, weekNr: 1)
        ]

        let rows = LottoSuggestionEngine.makeSuggestedRows(
            for: targetDate,
            predictedNumbers: [2, 4, 8, 12, 16, 20, 24, 28],
            jackpots: jackpots,
            rowCount: 20
        )

        #expect(rows.count == 20)
        #expect(Set(rows.map(\.id)).count == 20)
        #expect(rows.allSatisfy { $0.numbers.count == 7 })
        #expect(rows.allSatisfy { Set($0.numbers).count == 7 })
        #expect(rows.allSatisfy { $0.numbers.allSatisfy(LottoStatistics.validNumberRange.contains) })
    }

    @Test func suggestionEngineIncludesPredictedAndSameWeekMetadata() {
        let calendar = Calendar(identifier: .gregorian)
        let targetDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let weekNumber = LottoDateSupport.weekNumber(for: targetDate)

        let jackpots = [
            JackPot(
                dato: calendar.date(from: DateComponents(year: 2024, month: 8, day: 31))!,
                nr1: 4, nr2: 7, nr3: 10, nr4: 13, nr5: 16, nr6: 19, nr7: 22, nr8: 25,
                weekNr: weekNumber
            )
        ]

        let rows = LottoSuggestionEngine.makeSuggestedRows(
            for: targetDate,
            predictedNumbers: [4, 10, 18, 24, 30],
            jackpots: jackpots,
            mode: .trygg,
            rowCount: 3
        )

        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { !$0.sourceLabel.isEmpty })
        #expect(rows.contains { !$0.predictedMatches.isEmpty })
        #expect(rows.contains { !$0.sameWeekMatches.isEmpty })
    }

    @Test func suggestionEngineSupportsCustomRowCountAndModes() {
        let calendar = Calendar(identifier: .gregorian)
        let targetDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let weekNumber = LottoDateSupport.weekNumber(for: targetDate)

        let jackpots = [
            JackPot(dato: calendar.date(from: DateComponents(year: 2023, month: 9, day: 2))!, nr1: 1, nr2: 3, nr3: 5, nr4: 7, nr5: 9, nr6: 11, nr7: 13, nr8: 15, weekNr: weekNumber),
            JackPot(dato: calendar.date(from: DateComponents(year: 2024, month: 8, day: 31))!, nr1: 2, nr2: 4, nr3: 6, nr4: 8, nr5: 10, nr6: 12, nr7: 14, nr8: 16, weekNr: weekNumber)
        ]

        let safeRows = LottoSuggestionEngine.makeSuggestedRows(
            for: targetDate,
            predictedNumbers: [2, 4, 8, 12, 16, 20, 24],
            jackpots: jackpots,
            mode: .trygg,
            rowCount: 10
        )

        let chanceRows = LottoSuggestionEngine.makeSuggestedRows(
            for: targetDate,
            predictedNumbers: [2, 4, 8, 12, 16, 20, 24],
            jackpots: jackpots,
            mode: .sjansen,
            rowCount: 10
        )

        #expect(safeRows.count == 10)
        #expect(chanceRows.count == 10)
        #expect(Set(safeRows.map(\.id)).count == 10)
        #expect(Set(chanceRows.map(\.id)).count == 10)
        #expect(safeRows.map(\.id) != chanceRows.map(\.id))
    }

    @Test func suggestionEnginePrioritizesSameWeekAndPredictedNumbers() {
        let calendar = Calendar(identifier: .gregorian)
        let targetDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let weekNumber = LottoDateSupport.weekNumber(for: targetDate)

        let jackpots = [
            JackPot(dato: calendar.date(from: DateComponents(year: 2023, month: 9, day: 2))!, nr1: 5, nr2: 10, nr3: 15, nr4: 20, nr5: 25, nr6: 30, nr7: 34, nr8: 1, weekNr: weekNumber),
            JackPot(dato: calendar.date(from: DateComponents(year: 2024, month: 8, day: 31))!, nr1: 5, nr2: 10, nr3: 14, nr4: 18, nr5: 22, nr6: 26, nr7: 30, nr8: 34, weekNr: weekNumber)
        ]

        let rows = LottoSuggestionEngine.makeSuggestedRows(
            for: targetDate,
            predictedNumbers: [5, 10, 12, 18, 22, 30],
            jackpots: jackpots,
            rowCount: 5
        )

        #expect(!rows.isEmpty)
        #expect(rows[0].numbers.contains(5))
        #expect(rows[0].numbers.contains(10))
        #expect(rows[0].numbers.contains(30))
    }
}
