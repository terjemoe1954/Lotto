//
//  Model.swift
//  Lotto app
//
//  Created by Terje Moe on 31/01/2026.
//
import SwiftUI
import SwiftData

/// A jackpot draw with eight numbers and a week number.
@Model
final class JackPot: Decodable {
    /// Draw date.
    var dato: Date = Date()
    /// Winning numbers 1-8 (nr8 is treated as extra number in the app).
    var nr1: Int = 0
    var nr2: Int = 0
    var nr3: Int = 0
    var nr4: Int = 0
    var nr5: Int = 0
    var nr6: Int = 0
    var nr7: Int = 0
    var nr8: Int = 0
    /// Week number for the draw.
    var weekNr: Int = 0
    
    init(
        dato: Date = .now,
        nr1: Int = 0, nr2: Int = 0, nr3: Int = 0, nr4: Int = 0,
        nr5: Int = 0, nr6: Int = 0, nr7: Int = 0, nr8: Int = 0,
        weekNr: Int = 0
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
    
    
    private enum CodingKeys: String, CodingKey {
        case dato = "dato"
        case nr1, nr2, nr3, nr4, nr5, nr6, nr7, nr8
    }
    
    /// Custom decoding for the date format in `lotto.json` (dd.MM.yyyy).
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 1. Decode the date as a String first
        let dateString = try container.decode(String.self, forKey: .dato)
        
        // 2. Set up a formatter to match "02.01.2016"
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        
        // 3. Convert string to Date
        if let date = formatter.date(from: dateString) {
            self.dato = date
        } else {
            throw DecodingError.dataCorruptedError(forKey: .dato, in: container, debugDescription: "Date string does not match format dd.MM.yyyy")
        }
        
        // Decode integers as normal
        self.nr1 = try container.decode(Int.self, forKey: .nr1)
        self.nr2 = try container.decode(Int.self, forKey: .nr2)
        self.nr3 = try container.decode(Int.self, forKey: .nr3)
        self.nr4 = try container.decode(Int.self, forKey: .nr4)
        self.nr5 = try container.decode(Int.self, forKey: .nr5)
        self.nr6 = try container.decode(Int.self, forKey: .nr6)
        self.nr7 = try container.decode(Int.self, forKey: .nr7)
        self.nr8 = try container.decode(Int.self, forKey: .nr8)
    }
    
}
