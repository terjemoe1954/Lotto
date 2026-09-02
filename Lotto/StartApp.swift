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
    private let sharedModelContainer: ModelContainer = {
        let configuration = ModelConfiguration(cloudKitDatabase: .automatic)

        do {
            return try ModelContainer(
                for: JackPot.self,
                Result.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            FirstView()
        }
        .modelContainer(sharedModelContainer)
    }
    
    /// Logs where SwiftData files are stored (useful for troubleshooting).
    init() {
        print(URL.applicationSupportDirectory.path(percentEncoded: false))
    }
}
