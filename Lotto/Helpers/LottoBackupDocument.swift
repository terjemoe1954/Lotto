//
//  LottoBackupDocument.swift
//  Lotto
//
//  Created by Codex on 02/09/2026.
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LottoBackupSettings: Codable {
    var tolerance: Double
    var appearanceModeRawValue: String
    var excludeHighestGapFromAverage: Bool

    private enum CodingKeys: String, CodingKey {
        case tolerance
        case appearanceModeRawValue
        case excludeHighestGapFromAverage
    }

    nonisolated init(tolerance: Double, appearanceModeRawValue: String, excludeHighestGapFromAverage: Bool) {
        self.tolerance = tolerance
        self.appearanceModeRawValue = appearanceModeRawValue
        self.excludeHighestGapFromAverage = excludeHighestGapFromAverage
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tolerance = try container.decode(Double.self, forKey: .tolerance)
        appearanceModeRawValue = try container.decode(String.self, forKey: .appearanceModeRawValue)
        excludeHighestGapFromAverage = try container.decode(Bool.self, forKey: .excludeHighestGapFromAverage)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tolerance, forKey: .tolerance)
        try container.encode(appearanceModeRawValue, forKey: .appearanceModeRawValue)
        try container.encode(excludeHighestGapFromAverage, forKey: .excludeHighestGapFromAverage)
    }
}

struct LottoBackupJackpot: Codable {
    var dato: Date
    var nr1: Int
    var nr2: Int
    var nr3: Int
    var nr4: Int
    var nr5: Int
    var nr6: Int
    var nr7: Int
    var nr8: Int
    var weekNr: Int

    private enum CodingKeys: String, CodingKey {
        case dato, nr1, nr2, nr3, nr4, nr5, nr6, nr7, nr8, weekNr
    }

    init(_ jackpot: JackPot) {
        dato = jackpot.dato
        nr1 = jackpot.nr1
        nr2 = jackpot.nr2
        nr3 = jackpot.nr3
        nr4 = jackpot.nr4
        nr5 = jackpot.nr5
        nr6 = jackpot.nr6
        nr7 = jackpot.nr7
        nr8 = jackpot.nr8
        weekNr = jackpot.weekNr
    }

    nonisolated init(
        dato: Date,
        nr1: Int,
        nr2: Int,
        nr3: Int,
        nr4: Int,
        nr5: Int,
        nr6: Int,
        nr7: Int,
        nr8: Int,
        weekNr: Int
    ) {
        self.dato = dato
        self.nr1 = nr1
        self.nr2 = nr2
        self.nr3 = nr3
        self.nr4 = nr4
        self.nr5 = nr5
        self.nr6 = nr6
        self.nr7 = nr7
        self.nr8 = nr8
        self.weekNr = weekNr
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dato = try container.decode(Date.self, forKey: .dato)
        nr1 = try container.decode(Int.self, forKey: .nr1)
        nr2 = try container.decode(Int.self, forKey: .nr2)
        nr3 = try container.decode(Int.self, forKey: .nr3)
        nr4 = try container.decode(Int.self, forKey: .nr4)
        nr5 = try container.decode(Int.self, forKey: .nr5)
        nr6 = try container.decode(Int.self, forKey: .nr6)
        nr7 = try container.decode(Int.self, forKey: .nr7)
        nr8 = try container.decode(Int.self, forKey: .nr8)
        weekNr = try container.decode(Int.self, forKey: .weekNr)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dato, forKey: .dato)
        try container.encode(nr1, forKey: .nr1)
        try container.encode(nr2, forKey: .nr2)
        try container.encode(nr3, forKey: .nr3)
        try container.encode(nr4, forKey: .nr4)
        try container.encode(nr5, forKey: .nr5)
        try container.encode(nr6, forKey: .nr6)
        try container.encode(nr7, forKey: .nr7)
        try container.encode(nr8, forKey: .nr8)
        try container.encode(weekNr, forKey: .weekNr)
    }

    func makeModel() -> JackPot {
        JackPot(
            dato: dato,
            nr1: nr1,
            nr2: nr2,
            nr3: nr3,
            nr4: nr4,
            nr5: nr5,
            nr6: nr6,
            nr7: nr7,
            nr8: nr8,
            weekNr: weekNr
        )
    }
}

struct LottoBackupResult: Codable {
    var dato: Date
    var nr1: Int
    var nr2: Int
    var nr3: Int
    var nr4: Int
    var nr5: Int
    var nr6: Int
    var nr7: Int
    var weekNr: Int

    private enum CodingKeys: String, CodingKey {
        case dato, nr1, nr2, nr3, nr4, nr5, nr6, nr7, weekNr
    }

    init(_ result: Result) {
        dato = result.dato
        nr1 = result.nr1
        nr2 = result.nr2
        nr3 = result.nr3
        nr4 = result.nr4
        nr5 = result.nr5
        nr6 = result.nr6
        nr7 = result.nr7
        weekNr = result.weekNr
    }

    nonisolated init(
        dato: Date,
        nr1: Int,
        nr2: Int,
        nr3: Int,
        nr4: Int,
        nr5: Int,
        nr6: Int,
        nr7: Int,
        weekNr: Int
    ) {
        self.dato = dato
        self.nr1 = nr1
        self.nr2 = nr2
        self.nr3 = nr3
        self.nr4 = nr4
        self.nr5 = nr5
        self.nr6 = nr6
        self.nr7 = nr7
        self.weekNr = weekNr
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dato = try container.decode(Date.self, forKey: .dato)
        nr1 = try container.decode(Int.self, forKey: .nr1)
        nr2 = try container.decode(Int.self, forKey: .nr2)
        nr3 = try container.decode(Int.self, forKey: .nr3)
        nr4 = try container.decode(Int.self, forKey: .nr4)
        nr5 = try container.decode(Int.self, forKey: .nr5)
        nr6 = try container.decode(Int.self, forKey: .nr6)
        nr7 = try container.decode(Int.self, forKey: .nr7)
        weekNr = try container.decode(Int.self, forKey: .weekNr)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dato, forKey: .dato)
        try container.encode(nr1, forKey: .nr1)
        try container.encode(nr2, forKey: .nr2)
        try container.encode(nr3, forKey: .nr3)
        try container.encode(nr4, forKey: .nr4)
        try container.encode(nr5, forKey: .nr5)
        try container.encode(nr6, forKey: .nr6)
        try container.encode(nr7, forKey: .nr7)
        try container.encode(weekNr, forKey: .weekNr)
    }

    func makeModel() -> Result {
        Result(
            dato: dato,
            nr1: nr1,
            nr2: nr2,
            nr3: nr3,
            nr4: nr4,
            nr5: nr5,
            nr6: nr6,
            nr7: nr7,
            weekNr: weekNr
        )
    }
}

struct LottoBackupSnapshot: Codable {
    var exportedAt: Date
    var settings: LottoBackupSettings
    var jackpots: [LottoBackupJackpot]
    var results: [LottoBackupResult]

    private enum CodingKeys: String, CodingKey {
        case exportedAt
        case settings
        case jackpots
        case results
    }

    nonisolated init(
        exportedAt: Date,
        settings: LottoBackupSettings,
        jackpots: [LottoBackupJackpot],
        results: [LottoBackupResult]
    ) {
        self.exportedAt = exportedAt
        self.settings = settings
        self.jackpots = jackpots
        self.results = results
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        settings = try container.decode(LottoBackupSettings.self, forKey: .settings)
        jackpots = try container.decode([LottoBackupJackpot].self, forKey: .jackpots)
        results = try container.decode([LottoBackupResult].self, forKey: .results)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(settings, forKey: .settings)
        try container.encode(jackpots, forKey: .jackpots)
        try container.encode(results, forKey: .results)
    }
}

struct LottoBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var snapshot: LottoBackupSnapshot

    init(snapshot: LottoBackupSnapshot) {
        self.snapshot = snapshot
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshot = try decoder.decode(LottoBackupSnapshot.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        return FileWrapper(regularFileWithContents: data)
    }
}
