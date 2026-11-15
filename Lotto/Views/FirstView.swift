//
//  ContentView.swift
//  Lotto
//
//  Created by Terje Moe on 30/01/2026.
//

import SwiftUI
import SwiftData

/// Main menu for the app with entry points to all features.
struct FirstView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \JackPot.dato, order: .forward) private var jackpots: [JackPot]
    @AppStorage("toleranse") var toleranse: Double = 3.0
    @AppStorage(LottoAppPreferences.appearanceModeKey) private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @Query(sort: \Result.dato, order: .reverse) private var ownRows: [Result]
    @State private var showingDraws = false
    @State private var selectedDraw: Date?
    @State private var showAll = false
    @State private var updating = false
    @State private var updateTask: Task<Void, Never>?
    @State private var updateMessage: String?
    @State private var showListRows = false
    @State private var showRegisterView = false
    @State private var showNumberCountView = false
    @State private var showMyLotteryView = false
    @State private var showListLotteryView = false
    @State private var showFindWinnerView = false
    @State private var showNumberPredictionForm = false
    @State private var showingSettings = false
    @State private var errorMessage: String?
    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    var body: some View {
        let snapshot = LottoHomeSnapshot(draws: jackpots.reversed().map { $0 }, rows: ownRows, selectedDate: selectedDraw)
        let draws = snapshot.draws
        let drawDates = snapshot.dates
        let activeDate = snapshot.activeDate
        let visibleRows = snapshot.selectedRows
        return NavigationStack {
            List {
                Section {
                    LotteryGameActionsView(rules: "7 hovedtall av 34 + 1 tilleggstall", schedule: "lørdag",
                                           newRow: { showMyLotteryView = true },
                                           suggestions: { showNumberPredictionForm = true },
                                           statistics: { showNumberCountView = true })
                }
                Section("Resultater fra Norsk Tipping") {
                    LabeledContent("Lagrede trekninger", value: "\(draws.count)")
                    if let latest = draws.first {
                        LabeledContent("Siste trekning", value: LotteryCalendar.text(latest.dato))
                    }
                    Button {
                        updateTask = Task { await refreshDraws() }
                    } label: {
                        HStack {
                            if updating { ProgressView() }
                            Text(updating ? "Oppdaterer …" : "Hent nye trekninger")
                        }
                    }.disabled(updating)
                    Text("Historikk fra 2011. Egne rekker lagres her; levering skjer hos Norsk Tipping.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Vis", selection: $showingDraws) {
                        Text("Mine rekker (\(ownRows.count))").tag(false)
                        Text("Trekninger (\(draws.count))").tag(true)
                    }.pickerStyle(.segmented)
                    if !showingDraws, let activeDate {
                        Picker("Trekningsdato", selection: Binding(get: { activeDate }, set: { selectedDraw = $0; showAll = false })) {
                            ForEach(drawDates, id: \.self) { date in Text(LotteryCalendar.text(date)).tag(date) }
                        }
                        Text("Bare dine rekker for valgt trekning vises.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Sortert etter flest rette hovedtall, deretter tilleggstall. Grønn markering gjelder ordinære premiegrupper; kontroller gevinst hos Norsk Tipping. Tilleggstrekninger og historiske regelendringer er ikke beregnet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if showingDraws {
                        if draws.isEmpty { Text("Ingen trekninger ennå. Trykk Hent nye trekninger.").foregroundStyle(.secondary) }
                        ForEach(showAll ? draws : Array(draws.prefix(50))) { draw in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(LotteryCalendar.text(draw.dato)).font(.caption).foregroundStyle(.secondary)
                                Text(numbers(draw).map(String.init).joined(separator: " · ") + " + \(draw.nr8)")
                                    .font(.headline).monospacedDigit()
                            }
                        }
                        if !showAll && draws.count > 50 { Button("Vis alle") { showAll = true } }
                        Button("Åpne trekningsliste", systemImage: "list.bullet") { showListRows = true }
                    } else {
                        if visibleRows.isEmpty {
                            Text("Ingen egne rekker for valgt trekning. Lagre en rekke eller velg en annen dato.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(showAll ? visibleRows : Array(visibleRows.prefix(50))) { row in
                            let comparison = snapshot.comparisons[row.persistentModelID]
                            VStack(alignment: .leading, spacing: 5) {
                                Text(LotteryCalendar.text(row.dato)).font(.caption).foregroundStyle(.secondary)
                                Text(numbers(row).map(String.init).joined(separator: " · ")).font(.headline).monospacedDigit()
                                if let comparison {
                                    Text("\(comparison.matchCount) hovedtall + \(comparison.matchedExtraNumber == nil ? 0 : 1) tilleggstall rette.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    if comparison.isPrize {
                                        Label("Gevinst – kontroller hos Norsk Tipping", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                } else { Text("Venter på trekningsresultat").font(.subheadline).foregroundStyle(.secondary) }
                            }
                            .listRowBackground(comparison?.isPrize == true ? Color.green.opacity(0.15) : Color.clear)
                            .contextMenu {
                                ShareLink(item: "Lotto \(LotteryCalendar.text(row.dato))\n\(numbers(row).map(String.init).joined(separator: " · "))") {
                                    Label("Del rekke", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                        if !showAll && visibleRows.count > 50 { Button("Vis alle") { showAll = true } }
                        Button("Liste og eksport", systemImage: "list.bullet") { showListLotteryView = true }
                        Button("Kontroller dine rekker", systemImage: "checkmark.circle") { showFindWinnerView = true }
                    }
                }
            }
            .navigationTitle("Lotto")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Innstillinger", systemImage: "gearshape") { showingSettings = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Registrer trekning", systemImage: "calendar.badge.plus") { showRegisterView = true }
                }
            }
        }

        .onDisappear { updateTask?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { updateTask?.cancel() }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .sheet(isPresented: $showNumberPredictionForm) {
            NumberPredictionForm()
        }
        .sheet(isPresented: $showMyLotteryView) {
            MyLotteryView()
        }
        .sheet(isPresented: $showListLotteryView) {
            ListLotteryView()
        }
        .sheet(isPresented: $showListRows) {
            ListRowsView()
        }
        .sheet(isPresented: $showRegisterView) {
            NewJackpotView()
        }
        .sheet(isPresented: $showNumberCountView) {
            NumberCountsView()
        }
        .sheet(isPresented: $showFindWinnerView) {
            FindWinnerView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(toleranse: $toleranse)
        }
        .alert("Lotto", isPresented: Binding(get: { updateMessage != nil }, set: { if !$0 { updateMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(updateMessage ?? "") }
        .alert("Feil", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private func numbers(_ row: Result) -> [Int] { [row.nr1,row.nr2,row.nr3,row.nr4,row.nr5,row.nr6,row.nr7] }
    private func numbers(_ row: JackPot) -> [Int] { [row.nr1,row.nr2,row.nr3,row.nr4,row.nr5,row.nr6,row.nr7] }
    @MainActor private func refreshDraws() async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        do {
            let result = try await LottoDrawUpdater.update(modelContext: context)
            updateMessage = "La til \(result.addedCount) nye trekninger."
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            updateMessage = "Kunne ikke fullføre oppdateringen. Lagrede trekninger er tilgjengelige, og du kan prøve igjen. \(error.localizedDescription)" }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }


}


#Preview {
    FirstView()
        .modelContainer(for: [JackPot.self, Result.self], inMemory: true)
}
