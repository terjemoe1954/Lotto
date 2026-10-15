//
//  SettingsView.swift
//  Lotto
//
//  Created by Terje Moe on 12/02/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum BackupRestoreScope {
    case everything
    case drawsOnly
}

private enum BackupExportScope {
    case everything
    case drawsOnly
}

/// App settings (dark mode and prediction tolerance).
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var context
    @Binding var toleranse: Double
    @AppStorage(LottoAppPreferences.appearanceModeKey) private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @AppStorage(LottoAppPreferences.excludeHighestGapKey) private var excludeHighestGapFromAverage = false
    @State private var isExportingBackup = false
    @State private var showingExportOptions = false
    @State private var isImportingBackup = false
    @State private var showingRestoreOptions = false
    @State private var restoreScope: BackupRestoreScope = .everything
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
    @State private var showingManual = false
    @State private var isUpdatingDraws = false

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
                    Button("Eksporter") {
                        showingExportOptions = true
                    }

                    Button("Gjenopprett fra backup") {
                        showingRestoreOptions = true
                    }

                    Text("Du kan gjenopprette hele backupen eller bare importere manglende trekninger.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Trekninger") {
                    Button {
                        Task {
                            await updateDraws()
                        }
                    } label: {
                        if isUpdatingDraws {
                            HStack {
                                ProgressView()
                                Text("Kontrollerer nye trekninger …")
                            }
                        } else {
                            Label("Oppdater trekninger", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isUpdatingDraws)

                    Text("Appen kontrollerer også automatisk etter nye trekninger ved oppstart.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Hjelp") {
                    Button("Apne manual") {
                        showingManual = true
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
            .confirmationDialog(
                "Hva vil du eksportere?",
                isPresented: $showingExportOptions,
                titleVisibility: .visible
            ) {
                Button("Full backup") {
                    exportBackup(scope: .everything)
                }

                Button("Bare trekninger") {
                    exportBackup(scope: .drawsOnly)
                }

                Button("Avbryt", role: .cancel) { }
            } message: {
                Text("En trekningseksport inneholder ikke dine egne rekker eller personlige innstillinger.")
            }
            .confirmationDialog(
                "Hva vil du gjenopprette?",
                isPresented: $showingRestoreOptions,
                titleVisibility: .visible
            ) {
                Button("Alt fra backup") {
                    restoreScope = .everything
                    isImportingBackup = true
                }

                Button("Bare trekninger") {
                    restoreScope = .drawsOnly
                    isImportingBackup = true
                }

                Button("Avbryt", role: .cancel) { }
            } message: {
                Text("Alt erstatter data og innstillinger på denne enheten. Bare trekninger beholder egne rekker og innstillinger.")
            }
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
            .sheet(isPresented: $showingManual) {
                LottoManualView()
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
    private func exportBackup(scope: BackupExportScope) {
        do {
            let jackpots = try context.fetch(FetchDescriptor<JackPot>())
            let results: [Result]
            let settings: LottoBackupSettings
            let content: LottoBackupContent

            switch scope {
            case .everything:
                results = try context.fetch(FetchDescriptor<Result>())
                settings = LottoBackupSettings(
                    tolerance: toleranse,
                    appearanceModeRawValue: appearanceMode.rawValue,
                    excludeHighestGapFromAverage: excludeHighestGapFromAverage
                )
                content = .everything
            case .drawsOnly:
                results = []
                settings = LottoBackupSettings(
                    tolerance: 0,
                    appearanceModeRawValue: AppearanceMode.system.rawValue,
                    excludeHighestGapFromAverage: false
                )
                content = .drawsOnly
            }

            let snapshot = LottoBackupSnapshot(
                content: content,
                exportedAt: .now,
                settings: settings,
                jackpots: jackpots.map(LottoBackupJackpot.init),
                results: results.map(LottoBackupResult.init)
            )

            backupDocument = LottoBackupDocument(snapshot: snapshot)
            let filePrefix = scope == .everything ? "Lotto-backup" : "Lotto-trekninger"
            backupFileName = "\(filePrefix)-\(Date.now.formatted(.iso8601.year().month().day())).json"
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

            if snapshot.content == .drawsOnly {
                let result = try importDraws(from: snapshot)
                showAlert(title: "Trekninger", message: result)
                return
            }

            switch restoreScope {
            case .everything:
                try restoreEverything(from: snapshot)
                showAlert(title: "Backup", message: "Hele backupen ble gjenopprettet.")
            case .drawsOnly:
                let result = try importDraws(from: snapshot)
                showAlert(title: "Trekninger", message: result)
            }
        } catch {
            showAlert(title: "Feil", message: "Kunne ikke gjenopprette backup: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func restoreEverything(from snapshot: LottoBackupSnapshot) throws {
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
    }

    @MainActor
    private func importDraws(from snapshot: LottoBackupSnapshot) throws -> String {
        let backupJackpots = snapshot.jackpots.map { $0.makeModel() }
        let existingJackpots = try context.fetch(FetchDescriptor<JackPot>())
        let importPlan = LottoRules.jackpotImportPlan(
            bundledJackpots: backupJackpots,
            existingJackpots: existingJackpots
        )

        for jackpot in importPlan.missing {
            context.insert(jackpot)
        }

        if !importPlan.missing.isEmpty {
            try context.save()
        }

        if importPlan.conflicts.isEmpty {
            return "\(importPlan.missing.count) nye trekninger ble importert. Egne rekker og innstillinger ble beholdt."
        }

        return "\(importPlan.missing.count) nye trekninger ble importert. \(importPlan.conflicts.count) konflikter ble hoppet over. Egne rekker og innstillinger ble beholdt."
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }

    @MainActor
    private func updateDraws() async {
        isUpdatingDraws = true
        defer { isUpdatingDraws = false }

        do {
            let result = try await LottoDrawUpdater.update(modelContext: context)
            let message = result.addedCount == 0
                ? "Alle tilgjengelige trekninger er allerede oppdatert."
                : "La til \(result.addedCount) nye trekninger."
            showAlert(title: "Trekninger", message: message)
        } catch {
            showAlert(
                title: "Kunne ikke oppdatere",
                message: "Kontroller internettforbindelsen og prøv igjen. \(error.localizedDescription)"
            )
        }
    }
}

private struct LottoManualView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    manualSection(
                        title: "Om forslagene",
                        lines: [
                            "Forslagene bygger pa predikerte tall, vinnerrekker fra tidligere ar i samme ukenummer og generell frekvens.",
                            "Predikerte tall er tall der neste beregnede dato ligger innen toleransen du har satt i settings.",
                            "Samme uke betyr tall som har forekommet i historiske trekninger i samme ukenummer som den valgte datoen."
                        ]
                    )

                    manualSection(
                        title: "Hvordan tallene velges",
                        lines: [
                            "Trygg prioriterer predikerte tall og historikk fra samme uke sterkest.",
                            "Balansert blander prediksjon, samme uke og generell frekvens jevnere.",
                            "Sjansen sprer rekkene mer og slipper inn flere overraskelser.",
                            "Alle forslag blir kontrollert slik at de inneholder 7 unike tall mellom 1 og 34."
                        ]
                    )

                    manualSection(
                        title: "Knapper i forslag",
                        lines: [
                            "Lagre lagrer rekken direkte som en innlevert rekke pa valgt dato.",
                            "Levere apner rekken i skjermbildet for Levere, ferdig utfylt med riktig dato, slik at du kan kontrollere eller endre den for lagring.",
                            "Print lager en utskriftsvennlig rapport med forslagene."
                        ]
                    )

                    manualSection(
                        title: "Eksport og backup",
                        lines: [
                            "I Mine rekker kan du markere valgte rekker og eksportere til Excel som CSV eller til Pages som TXT.",
                            "Hvis ingen rekker er markert, eksporteres alle rekker i gjeldende filter.",
                            "Backup i settings eksporterer og gjenoppretter baade trekninger, egne rekker og appinnstillinger."
                        ]
                    )

                    manualSection(
                        title: "iCloud og dubletter",
                        lines: [
                            "Ved bruk av flere enheter kan SwiftData og CloudKit midlertidig lage dubletter under synkronisering.",
                            "Appen rydder automatisk dubletter i trekninger ved oppstart og nar appen blir aktiv igjen.",
                            "Innlesing av historiske trekninger fra lotto.json er ogsa strammet inn for a redusere risikoen for doble poster."
                        ]
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ferdig") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func manualSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    SettingsView(toleranse: .constant(4.0))
}
