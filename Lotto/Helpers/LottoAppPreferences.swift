//
//  LottoAppPreferences.swift
//  Lotto
//
//  Created by Codex on 02/09/2026.
//

import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Lys"
        case .dark:
            return "Mork"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum LottoAppPreferences {
    static let appearanceModeKey = "appearanceMode"
    static let toleranceKey = "toleranse"
    static let excludeHighestGapKey = "excludeHighestGapFromAverage"

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Ukjent"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Ukjent"
    }
}
