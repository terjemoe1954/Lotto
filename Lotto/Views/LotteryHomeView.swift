import SwiftUI
import SwiftData

struct LotteryHomeView: View {
    @AppStorage("selectedLottery") private var selection = "lotto"
    @State private var displayedSelection = UserDefaults.standard.string(forKey: "selectedLottery") ?? "lotto"
    @State private var switchingGame = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var preparedArchive = false
    @Environment(\.modelContext) private var context
    @State private var migrationError: String?
    @AppStorage("favorites.introSeen") private var favoritesIntroSeen = false
    @Query private var favoriteChanges: [LotteryFavoriteChange]
    @State private var showFavorites = false
    @State private var favoriteIntro = false
    @State private var showWeeklyReport = false
    @State private var showRegistrations = false
    @State private var showLedger = false
    @State private var showWinnings = false
    @State private var showSystem = false
    var body: some View {
        VStack(spacing: 0) {
            Picker("Spill", selection: Binding(get: { selection }, set: { game in
                guard game != selection else { return }
                switchingGame = true
                selection = game
            })) {
                Text("Lotto").tag("lotto")
                ForEach(InternationalGame.allCases) { game in Text(game.title).tag(game.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            HStack {
                Button("Favoritter", systemImage: "star") { favoriteIntro = false; showFavorites = true }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Ukesrapport", systemImage: "printer") { showWeeklyReport = true }
                    .buttonStyle(.bordered)
            }.padding(.horizontal).padding(.bottom, 4)
            HStack {
                Button("Mine gevinster", systemImage: "list.bullet") { showWinnings = true }
                Button("Systemspill", systemImage: "square.grid.3x3") { showSystem = true }
            }.buttonStyle(.bordered)
            HStack {
                Button("Spilleoversikt", systemImage: "list.bullet.rectangle") { showLedger = true }
                Button("Mine registreringer", systemImage: "square.and.pencil") { showRegistrations = true }
            }.buttonStyle(.bordered).padding(.bottom, 4)
            Group {
                if let game = InternationalGame(rawValue: displayedSelection) {
                    InternationalLotteryView(game: game).id(game)
                } else {
                    FirstView()
                }
            }
            .allowsHitTesting(!switchingGame)
            .overlay {
                if switchingGame {
                    ProgressView("Bytter spill …")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Bytter spill. Vent litt.")
                }
            }
        }
        .task(id: selection) {
            guard displayedSelection != selection else { switchingGame = false; return }
            switchingGame = true
            do {
                // Give the progress indicator a display frame before constructing the next screen.
                // Cancellation prevents an older selection from replacing a newer one.
                try await Task.sleep(for: .milliseconds(100))
                try Task.checkCancellation()
                displayedSelection = selection
                try await Task.sleep(for: .milliseconds(100))
                try Task.checkCancellation()
                switchingGame = false
            } catch is CancellationError { }
            catch { switchingGame = false }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            do {
                if !preparedArchive {
                    try Task.checkCancellation()
                    try LotteryArchivePreparation.prepare(context: context)
                    preparedArchive = true
                }
                try Task.checkCancellation()
                _ = try await LottoDrawUpdater.update(modelContext: context)
            } catch is CancellationError { }
            catch {
                // Network failures must not interrupt offline use. Archive failures are visible.
                if !preparedArchive { migrationError = "Kunne ikke klargjøre grunnarkivet: \(error.localizedDescription)" }
            }
        }
        .sheet(isPresented: $showFavorites) { LotteryFavoritesView(introductory: favoriteIntro) }
        .task {
            if !favoritesIntroSeen {
                if favoriteChanges.isEmpty { favoriteIntro = true; showFavorites = true }
                else { favoritesIntroSeen = true }
            }
        }
        .sheet(isPresented: $showWinnings) { LotteryWinningsView() }
        .sheet(isPresented: $showSystem) { LotterySystemView(initialGame: LotteryReportGame(rawValue: selection) ?? .lotto) }
        .sheet(isPresented: $showRegistrations) { LotteryRegistrationsView() }
        .sheet(isPresented: $showLedger) { LotteryLedgerView() }
        .sheet(isPresented: $showWeeklyReport) { WeeklyLotteryReportView() }
        .background { LotteryLegacyMigrationView(error: $migrationError) }
        .alert("Registreringsmarkeringer", isPresented: Binding(get: { migrationError != nil }, set: { if !$0 { migrationError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(migrationError ?? "") }
    }
}

struct InternationalLotteryView: View {
    let game: InternationalGame
    @Environment(\.scenePhase) private var scenePhase
    @State private var updateTask: Task<Void, Never>?
    @Environment(\.modelContext) private var context
    @Query(sort: \InternationalLotteryEntry.date, order: .reverse) private var entries: [InternationalLotteryEntry]
    @AppStorage(LottoAppPreferences.appearanceModeKey) private var appearance = AppearanceMode.system.rawValue
    @State private var editor: LotteryEditorMode?
    @State private var showStatistics = false
    @State private var showSuggestions = false
    @State private var showSettings = false
    @State private var updating = false
    @State private var progress = ""
    @State private var message: String?
    @State private var showingDraws = false
    @State private var showAll = false
    @State private var selectedDraw: Date?
    var body: some View {
        let snapshot = InternationalHomeSnapshot(entries: entries, game: game, selectedDate: selectedDraw)
        let draws = snapshot.draws
        let rows = snapshot.rows
        let drawDates = snapshot.dates
        let activeDate = snapshot.activeDate
        let source = showingDraws ? draws : snapshot.selectedRows
        let visible = showAll ? source : Array(source.prefix(50))
        return NavigationStack {
            List {
                Section {
                    LotteryGameActionsView(
                        rules: "\(game.mainCount) hovedtall av \(game.mainMaximum) + \(game.extraCount) \(game.extraTitle.lowercased()) av \(game.extraMaximum)",
                        schedule: game.schedule, newRow: { editor = .row },
                        suggestions: { showSuggestions = true }, statistics: { showStatistics = true })
                }
                Section("Resultater fra Norsk Tipping") {
                    LabeledContent("Lagrede trekninger", value: "\(draws.count)")
                    if let latest = draws.first { LabeledContent("Siste trekning", value: LotteryCalendar.text(latest.date)) }
                    Button {
                        updateTask = Task { await update() }
                    } label: {
                        HStack {
                            if updating { ProgressView() }
                            Text(updating ? "Oppdaterer …" : "Hent nye trekninger")
                        }
                    }.disabled(updating)
                    if updating { Text(progress).font(.caption).foregroundStyle(.secondary) }
                    Text("Historikk fra 2023. Bare ferdigbehandlede trekninger vises. Egne rekker lagres her; levering skjer hos Norsk Tipping.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Vis", selection: $showingDraws) {
                        Text("Mine rekker (\(rows.count))").tag(false)
                        Text("Trekninger (\(draws.count))").tag(true)
                    }.pickerStyle(.segmented)
                    if !showingDraws, let activeDate {
                        Picker("Trekningsdato", selection: Binding(get: { activeDate }, set: { selectedDraw = $0; showAll = false })) {
                            ForEach(drawDates, id: \.self) { date in Text(LotteryCalendar.text(date)).tag(date) }
                        }
                        Text("Bare dine rekker for valgt trekning vises.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if visible.isEmpty {
                        Text(showingDraws ? "Ingen trekninger ennå. Trykk Hent nye trekninger." : "Ingen egne rekker for valgt trekning. Lagre en rekke eller velg en annen dato.")
                            .foregroundStyle(.secondary)
                    }
                    if !showingDraws {
                        Text("Sortert etter flest rette hovedtall, deretter tilleggstall. Grønn markering gjelder dagens ordinære premiegrupper; kontroller gevinst hos Norsk Tipping. Tilleggstrekninger og historiske regelendringer er ikke beregnet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(visible) { entry in
                        let match = snapshot.matches[entry.persistentModelID]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(LotteryCalendar.text(entry.date)).font(.caption).foregroundStyle(.secondary)
                            Text(entry.numbersText).font(.headline).monospacedDigit()
                            if !entry.isDraw {
                                Text(match.map { "\($0.main) hovedtall + \($0.extra) \(game.extraTitle.lowercased()) rette. Sjekk eventuell premie hos Norsk Tipping." } ?? "Venter på trekningsresultat").font(.subheadline).foregroundStyle(.secondary)
                                if (match?.prize == true) { Label("Gevinst – kontroller hos Norsk Tipping", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                        }
                        .listRowBackground((match?.prize == true) ? Color.green.opacity(0.15) : Color.clear)
                        .contextMenu {
                            ShareLink(item: "\(game.title) \(LotteryCalendar.text(entry.date))\n\(entry.numbersText)") {
                                Label("Del rekke", systemImage: "square.and.arrow.up")
                            }
                            if !entry.isDraw {
                                Button("Slett rekke", role: .destructive) { delete(entry) }
                            }
                        }
                    }
                    if !showAll && source.count > 50 {
                        Button("Vis alle") { showAll = true }
                    }
                }
            }
            .navigationTitle(game.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Innstillinger", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Registrer trekning", systemImage: "calendar.badge.plus") { editor = .draw }
                }
            }
            .sheet(item: $editor) { mode in LotteryEntryEditor(game: game, mode: mode) }
            .sheet(isPresented: $showSuggestions) { InternationalSuggestionsView(game: game) }
            .sheet(isPresented: $showStatistics) { InternationalStatisticsView(game: game) }
            .sheet(isPresented: $showSettings) { LotterySettingsSheet() }
            .alert("\(game.title)", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(message ?? "") }
            .onDisappear { updateTask?.cancel() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { updateTask?.cancel() }
            }
        }
        .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).colorScheme)
    }

    private func delete(_ entry: InternationalLotteryEntry) {
        context.delete(entry)
        do { try context.save() } catch { context.rollback(); message = error.localizedDescription }
    }
    @MainActor private func update() async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        do {
            let count = try await InternationalLotteryUpdater.update(game: game, context: context) { progress = $0 }
            message = "La til \(count) nye trekninger."
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            message = "Kunne ikke fullføre oppdateringen. Lagrede trekninger er tilgjengelige, og du kan prøve igjen. \(error.localizedDescription)" }
    }
}

private struct LotterySettingsSheet: View {
    @AppStorage("toleranse") private var tolerance = 3.0
    var body: some View { SettingsView(toleranse: $tolerance) }
}

enum LotteryEditorMode: String, Identifiable {
    case row, draw
    var id: String { rawValue }
}

struct LotteryEntryEditor: View {
    let game: InternationalGame
    let mode: LotteryEditorMode
    var initialRow: InternationalSuggestedRow? = nil
    var initialDate: Date? = nil
    @Query private var favoriteChanges: [LotteryFavoriteChange]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var main = Set<Int>()
    @State private var extra = Set<Int>()
    @State private var errorMessage: String?
    private let columns = [GridItem(.adaptive(minimum: 44))]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Trekningsdato", selection: $date, displayedComponents: .date)
                    Text("Trekning \(game.schedule)").font(.caption).foregroundStyle(.secondary)
                }
                if mode == .row { LotteryOddsSummary(game: LotteryReportGame(rawValue: game.rawValue)!) }
                Section("Hovedtall: \(main.count) av \(game.mainCount)") {
                    numberGrid(maximum: game.mainMaximum, limit: game.mainCount, selection: $main)
                }
                Section("\(game.extraTitle): \(extra.count) av \(game.extraCount)") {
                    numberGrid(maximum: game.extraMaximum, limit: game.extraCount, selection: $extra)
                }
                if mode == .draw {
                    Text("Registrer bare bekreftede vinnertall. Samme dato kan ikke ha ulike resultater.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(mode == .draw ? "Ny trekning" : "Ny rekke")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") { save() }.disabled(main.count != game.mainCount || extra.count != game.extraCount)
                }
            }
            .onAppear {
                date = initialDate ?? game.nextDraw(onOrAfter: .now)
                if let initialRow {
                    main = Set(initialRow.mainNumbers)
                    extra = Set(initialRow.extraNumbers)
                } else if mode == .row {
                    let profile = LotteryFavorites.selection(for: LotteryReportGame(rawValue: game.rawValue)!, records: favoriteChanges.map(\.record))
                        .effective(for: LotteryReportGame(rawValue: game.rawValue)!)
                    main = Set(profile.mainNumbers)
                    extra = Set(profile.extraNumbers)
                }
            }
        }
    }
    private func numberGrid(maximum: Int, limit: Int, selection: Binding<Set<Int>>) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...maximum, id: \.self) { number in
                Button {
                    if selection.wrappedValue.contains(number) { selection.wrappedValue.remove(number) }
                    else if selection.wrappedValue.count < limit { selection.wrappedValue.insert(number) }
                } label: {
                    Text("\(number)").font(.body.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection.wrappedValue.contains(number) ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundStyle(selection.wrappedValue.contains(number) ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tall \(number)")
                .accessibilityAddTraits(selection.wrappedValue.contains(number) ? .isSelected : [])
            }
        }
    }
    private func save() {
        errorMessage = game.validation(main: main.sorted(), extra: extra.sorted(), date: date)
        guard errorMessage == nil else { return }
        if mode == .draw && LotteryCalendar.day(date) > LotteryCalendar.day(.now) {
            errorMessage = "En trekning kan ikke registreres før trekningsdagen."
            return
        }
        do {
            let existing = try context.fetch(FetchDescriptor<InternationalLotteryEntry>()).filter {
                $0.gameID == game.rawValue && $0.isDraw == (mode == .draw) && LotteryCalendar.day($0.date) == LotteryCalendar.day(date)
            }
            if mode == .draw && !existing.isEmpty { errorMessage = "Denne trekningen er allerede registrert."; return }
            if existing.contains(where: { Set($0.mainNumbers) == main && Set($0.extraNumbers) == extra }) {
                errorMessage = "Denne rekken er allerede lagret på denne datoen."; return
            }
            try LotteryOwnRowStore.insert(InternationalLotteryEntry(game: game, isDraw: mode == .draw, date: date, main: main.sorted(), extra: extra.sorted()), context: context)
            try context.save()
            dismiss()
        } catch { context.rollback(); errorMessage = error.localizedDescription }
    }
}

/// Shared action layout keeps all three game fronts consistent, including Dynamic Type.
struct LotteryGameActionsView: View {
    let rules: String
    let schedule: String
    let newRow: () -> Void
    let suggestions: () -> Void
    let statistics: () -> Void
    var body: some View {
        Text(rules)
        Text("Trekning \(schedule)").foregroundStyle(.secondary)
        ViewThatFits(in: .horizontal) {
            HStack {
                Button("Ny rekke", systemImage: "plus.circle", action: newRow)
                Spacer()
                Button("Forslag", systemImage: "wand.and.stars", action: suggestions)
            }
            VStack(alignment: .leading) {
                Button("Ny rekke", systemImage: "plus.circle", action: newRow)
                Button("Forslag", systemImage: "wand.and.stars", action: suggestions)
            }
        }.buttonStyle(.bordered)
        Button("Statistikk", systemImage: "chart.bar", action: statistics)
    }
}

/// Isolate legacy migration queries from picker/progress state changes in the parent.
/// They update for incoming data, not for each frame of a game switch.
private struct LotteryLegacyMigrationView: View {
    @Environment(\.modelContext) private var context
    @Query private var lottoRows: [Result]
    @Query private var internationalRows: [InternationalLotteryEntry]
    @Binding var error: String?
    private var keys: [String] {
        let weekly = UserDefaults.standard.string(forKey: WeeklyLotteryDelivery.storageKey) ?? ""
        let old = UserDefaults.standard.string(forKey: "transferredResultKeys") ?? ""
        guard !weekly.isEmpty || !old.isEmpty else { return [] }
        return WeeklyLotteryReport.rows(lotto: lottoRows, international: internationalRows).map(\.id)
    }
    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .task(id: keys) {
                guard !keys.isEmpty, !Task.isCancelled else { return }
                do {
                    try LotteryDeliverySync.migrateLegacy(
                        rows: WeeklyLotteryReport.rows(lotto: lottoRows, international: internationalRows), context: context)
                } catch {
                    context.rollback()
                    self.error = "Kunne ikke flytte registreringsmarkeringer: \(error.localizedDescription)"
                }
            }
    }
}
