//
//  LottoApp.swift
//  Lotto
//
//  Created by Terje Moe on 30/01/2026.
//

import SwiftUI
import SwiftData

/// App entry point and SwiftData container setup.
@main
struct StartApp: App {
    var body: some Scene {
        WindowGroup {
            FirstView()
        }
        .modelContainer(for: [JackPot.self, Result.self])
    }
    
    /// Logs where SwiftData files are stored (useful for troubleshooting).
    init() {
        print(URL.applicationSupportDirectory.path(percentEncoded: false))
    }
}
