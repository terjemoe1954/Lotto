//
//  SettingsView.swift
//  Lotto
//
//  Created by Terje Moe on 12/02/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// App settings (dark mode and prediction tolerance).
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var context
    @Binding var toleranse: Double
    @AppStorage(LottoAppPreferences.appearanceModeKey) private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @AppStorage(LottoAppPreferences.excludeHighestGapKey) private var excludeHighestGapFromAverage = false
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var backupDocument = LottoBackupDocument(
        snapshot: LottoBackupSnapshot(
            exportedAt: .now,
            settings: LottoBackupSettings(
                tolerance: 0,
                appearanceModeRawValue: AppearanceMode.system.rawValue,
                excludeHighestGapFromAverage: false
            ),
            jackpots: [],
            results: []
        )
    )
    @State private var backupFileName = "Lotto-backup.json"
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRawValue) ?? .system }
        nonmutating set { appearanceModeRawValue = newValue.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Utseende") {
                    Picker("Modus", selection: Binding(
                        get: { appearanceMode },
                        set: { appearanceMode = $0 }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Statistikk") {
                    Toggle("Fjern hoyeste verdi fra gjennomsnitt", isOn: $excludeHighestGapFromAverage)

                    HStack {
                        Text("Toleranse")
                        Spacer()
                        TextField("Dager", value: $toleranse, formatter: toleranceFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Text("0 betyr ingen toleranse for predikerte datoer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Backup") {
                    Button("Eksporter backup") {
                        exportBackup()
                    }

                    Button("Gjenopprett backup") {
                        isImportingBackup = true
                    }
                }

                Section("App") {
                    LabeledContent("Versjon", value: LottoAppPreferences.appVersion)
                    LabeledContent("Build", value: LottoAppPreferences.buildNumber)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ferdig") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFileName
            ) { result in
                switch result {
                case .success:
                    showAlert(title: "Backup", message: "Backup ble eksportert.")
                case .failure(let error):
                    showAlert(title: "Feil", message: "Kunne ikke eksportere backup: \(error.localizedDescription)")
                }
            }
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: [.json]
            ) { result in
                restoreBackup(from: result)
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
    }

    private var toleranceFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimum = 0
        return formatter
    }

    @MainActor
    private func exportBackup() {
        do {
            let jackpots = try context.fetch(FetchDescriptor<JackPot>())
            let results = try context.fetch(FetchDescriptor<Result>())
            let snapshot = LottoBackupSnapshot(
                exportedAt: .now,
                settings: LottoBackupSettings(
                    tolerance: toleranse,
                    appearanceModeRawValue: appearanceMode.rawValue,
                    excludeHighestGapFromAverage: excludeHighestGapFromAverage
                ),
                jackpots: jackpots.map(LottoBackupJackpot.init),
                results: results.map(LottoBackupResult.init)
            )

            backupDocument = LottoBackupDocument(snapshot: snapshot)
            backupFileName = "Lotto-backup-\(Date.now.formatted(.iso8601.year().month().day())).json"
            isExportingBackup = true
        } catch {
            showAlert(title: "Feil", message: "Kunne ikke lage backup: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func restoreBackup(from result: Swift.Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(LottoBackupSnapshot.self, from: data)

            try context.delete(model: JackPot.self)
            try context.delete(model: Result.self)

            for jackpot in snapshot.jackpots {
                context.insert(jackpot.makeModel())
            }

            for result in snapshot.results {
                context.insert(result.makeModel())
            }

            try context.save()

            toleranse = snapshot.settings.tolerance
            appearanceMode = AppearanceMode(rawValue: snapshot.settings.appearanceModeRawValue) ?? .system
            excludeHighestGapFromAverage = snapshot.settings.excludeHighestGapFromAverage

            showAlert(title: "Backup", message: "Backup ble gjenopprettet.")
        } catch {
            showAlert(title: "Feil", message: "Kunne ikke gjenopprette backup: \(error.localizedDescription)")
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

#Preview {
    SettingsView(toleranse: .constant(4.0))
}
