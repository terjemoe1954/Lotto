//
//  LottoDateSupport.swift
//  Lotto
//
//  Created by Codex on 02/09/2026.
//

import Foundation

enum LottoDateSupport {
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    static func formattedDate(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    nonisolated static func weekNumber(for date: Date) -> Int {
        Calendar.current.component(.weekOfYear, from: date)
    }

    nonisolated static func normalize(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    nonisolated static func isSaturday(_ date: Date) -> Bool {
        Calendar.current.component(.weekday, from: date) == 7
    }

    nonisolated static func nextSaturday(onOrAfter date: Date) -> Date {
        let normalizedDate = normalize(date)
        let calendar = Calendar.current

        if isSaturday(normalizedDate) {
            return normalizedDate
        }

        for offset in 1...6 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: normalizedDate) else {
                continue
            }
            if isSaturday(candidate) {
                return candidate
            }
        }

        return normalizedDate
    }
}

extension Date {
    nonisolated var isSaturday: Bool {
        LottoDateSupport.isSaturday(self)
    }
}
