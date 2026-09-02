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
}

extension Date {
    nonisolated var isSaturday: Bool {
        LottoDateSupport.isSaturday(self)
    }
}
